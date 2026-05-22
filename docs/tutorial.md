# Tutorial: Spice GitOps control plane on Kind

This guide follows the architecture in this repository: **GitHub** (GitOps source of truth), **Argo CD** (reconcile), **HashiCorp Vault** + **External Secrets Operator** (secrets), **ingress-nginx**, and the **Next.js control plane** (user + admin UI). It is **Kind-first** and splits **day‑0 bootstrap** (one-time automation) from **day‑2 operations** (webapp only).

Prerequisites:

- Docker, [Kind](https://kind.sigs.k8s.io/docs/user/quick-start/), `kubectl`, and [Helm 3](https://helm.sh/docs/intro/install/).
- A **GitHub repository** you control (fork or copy this repo), and a **PAT** or fine-grained token with **`contents: write`** on that repo (for the control plane) and read for Argo CD.

Throughout **Part A**, each step ends with **Validate**: commands to run and what you should see. **Parts B–D** add validations for the **control-plane image (GHCR)**, the control-plane Secret, and the running web UI. If a check fails, fix it before continuing (see [Troubleshooting](#troubleshooting) below).

---

## Part A — Day 0: create the Kind cluster

1. Create the cluster (ingress-ready node labels and host port mappings are in [`hack/kind-config.yaml`](../hack/kind-config.yaml)):

   ```bash
   make kind-create
   ```

   **Validate:**

   ```bash
   kind get clusters
   kubectl config current-context
   kubectl get nodes
   ```

   Expect: cluster name **`spice-gitops`** (see [`Makefile`](../Makefile) `CLUSTER_NAME`), kubectl context is **`kind-spice-gitops`**, every node **`Ready`**.

2. Install **ingress-nginx** (controller uses **hostPort** 80/443 so Kind’s `extraPortMappings` in [`hack/kind-config.yaml`](../hack/kind-config.yaml) reach nginx; a plain high `NodePort` alone would not):

   ```bash
   helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
   helm repo update
   helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
     -n ingress-nginx --create-namespace \
     -f gitops/bootstrap/values-ingress-nginx.yaml
   ```

   **Validate:**

   ```bash
   kubectl -n ingress-nginx wait --for=condition=available deploy --all --timeout=120s
   kubectl -n ingress-nginx get pods
   curl -sI --connect-timeout 3 http://127.0.0.1/ | head -5
   ```

   Expect: ingress controller pod(s) **`Running`**, `curl` returns **`HTTP/1.1`** (often **404** from nginx with no matching `Ingress` — that is fine; **connection refused** means host port 80 is not wired to the controller).

3. Install **Vault** (reference values enable a **dev-style** server suitable only for disposable labs; see comments in [`gitops/bootstrap/values-vault.yaml`](../gitops/bootstrap/values-vault.yaml)):

   ```bash
   helm repo add hashicorp https://helm.releases.hashicorp.com
   helm repo update
   helm upgrade --install vault hashicorp/vault -n vault --create-namespace \
     -f gitops/bootstrap/values-vault.yaml
   ```

   **Validate:**

   ```bash
   kubectl -n vault wait --for=condition=ready pod/vault-0 --timeout=120s
   kubectl -n vault get svc vault
   kubectl -n vault exec vault-0 -- vault status -format=json
   ```

   Expect: `vault-0` **`Running`**, Service **`vault`** exists in namespace **`vault`**, `vault status` shows **`sealed`** **false** (dev mode auto-unseals).

4. Install **External Secrets Operator**:

   ```bash
   helm repo add external-secrets https://charts.external-secrets.io
   helm repo update
   helm upgrade --install external-secrets external-secrets/external-secrets \
     -n external-secrets --create-namespace \
     -f gitops/bootstrap/values-external-secrets.yaml
   ```

   **Validate:**

   ```bash
   kubectl -n external-secrets wait --for=condition=available deploy --all --timeout=120s
   kubectl get pods -n external-secrets
   kubectl get crd clustersecretstores.external-secrets.io
   ```

   Expect: ESO pod(s) **`Running`**, CRD **`clustersecretstores.external-secrets.io`** exists with **`Established`** (if `kubectl get crd ...` returns **NotFound**, fix the Helm release: `helm status -n external-secrets external-secrets`, reinstall with `installCRDs: true` as in [`gitops/bootstrap/values-external-secrets.yaml`](../gitops/bootstrap/values-external-secrets.yaml)). Do **not** apply the `ClusterSecretStore` until this CRD exists.

5. **Vault token for ESO** (lab pattern): External Secrets needs a **Kubernetes Secret** that contains the Vault token. The committed [`ClusterSecretStore`](../gitops/bootstrap/manifests/cluster-secret-store.yaml) points at:

   - **Secret name:** `vault-eso-token`
   - **Namespace:** `external-secrets` (same namespace where you installed the ESO Helm release in step 4)
   - **Data key:** `token` (the literal string value of your Vault token)

   **5a — Get a Vault token (dev only):** read the root token from Vault pod logs once (do **not** do this in production):

   ```bash
   kubectl -n vault logs vault-0 | head -80
   ```

   Look for a line like `Root Token: hvs.xxxxx` and copy the token value (everything after `Root Token:`).

   **5b — Create the Secret in `external-secrets`:** substitute the real token (keep the quotes so the shell does not mangle special characters):

   ```bash
   kubectl -n external-secrets create secret generic vault-eso-token \
     --from-literal=token='PASTE_YOUR_VAULT_TOKEN_HERE'
   ```

   If the Secret already exists from a previous attempt, either delete it first or recreate it:

   ```bash
   kubectl -n external-secrets delete secret vault-eso-token --ignore-not-found
   kubectl -n external-secrets create secret generic vault-eso-token \
     --from-literal=token='PASTE_YOUR_VAULT_TOKEN_HERE'
   ```

   **5c — Validate the Secret:**

   ```bash
   kubectl -n external-secrets get secret vault-eso-token -o jsonpath='{.data.token}' | base64 -d | wc -c
   kubectl -n external-secrets get secret vault-eso-token -o jsonpath='{.data.token}' | base64 -d; echo
   ```

   Expect: byte count **greater than zero** (non-empty token), decoded value matches your Vault root token (avoid shared screens / logs in real environments).

6. **KV mount** (before the ClusterSecretStore): enable KV v2 at path `secret` so it matches [`cluster-secret-store.yaml`](../gitops/bootstrap/manifests/cluster-secret-store.yaml) (`spec.provider.vault.path: secret`). Example:

   ```bash
   kubectl -n vault exec -it vault-0 -- vault secrets enable -path=secret kv-v2
   ```

   If the mount already exists, Vault prints an error such as `path is already in use` — that is fine; continue to step 7.

   **Validate:**

   ```bash
   kubectl -n vault exec vault-0 -- vault secrets list
   ```

   Expect: a line for mount path **`secret/`** (KV v2 engine).

7. Apply the **ClusterSecretStore** (edit `server` in the manifest if your Vault Service differs), then confirm it becomes **Ready**:

   ```bash
   kubectl apply -f gitops/bootstrap/manifests/cluster-secret-store.yaml
   kubectl get clustersecretstore vault-backend
   ```

   **Validate:**

   ```bash
   kubectl wait --for=jsonpath='{.status.conditions[?(@.type=="Ready")].status}'=True clustersecretstore/vault-backend --timeout=120s
   kubectl get clustersecretstore vault-backend
   ```

   Expect: **`READY`** column **True** (may take a few seconds). If **`InvalidProviderConfig`** or **`READY=False`**, inspect Events:

   ```bash
   kubectl describe clustersecretstore vault-backend
   ```

   Typical causes: **`vault-eso-token` missing or wrong key** (must be data key `token` in namespace `external-secrets`); **wrong Vault URL** in the manifest (default `http://vault.vault.svc.cluster.local:8200` matches a Helm release named `vault` in namespace `vault`); **token invalid or expired**; **Vault pod not Ready**; **no KV v2 mount at path `secret`** (fix step 6, then `kubectl delete clustersecretstore vault-backend --ignore-not-found` and re-apply this manifest).

   If the store object is missing entirely, every `ExternalSecret` that references `vault-backend` stays **Degraded** with `ClusterSecretStore ... not found`.

   > **Note:** `kubectl wait` with `jsonpath` requires kubectl **1.27+**. On older kubectl, poll with `kubectl get clustersecretstore vault-backend` until `READY` is **True**, or rely on `describe` above.

8. Install **Argo CD**:

   ```bash
   helm repo add argo https://argoproj.github.io/argo-helm
   helm repo update
   helm upgrade --install argocd argo/argo-cd -n argocd --create-namespace \
     -f gitops/bootstrap/values-argocd.yaml
   ```

   **Validate:**

   ```bash
   kubectl -n argocd rollout status deploy/argocd-server --timeout=180s
   kubectl -n argocd get pods
   kubectl -n argocd get secret argocd-initial-admin-secret
   kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d | wc -c
   kubectl -n argocd get ingress
   curl -sI -H "Host: argocd.127.0.0.1.nip.io" --connect-timeout 3 http://127.0.0.1/ | head -5
   ```

   **Argo CD initial `admin` password:** log in to the UI (or CLI) as user **`admin`**. To print the bootstrap password from the cluster (stored base64-encoded in the Secret):

   ```bash
   kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
   ```

   The decoded string has no trailing newline. After you change the admin password or delete `argocd-initial-admin-secret`, this Secret is gone and you must use whatever credentials you configured instead.

   Expect: `argocd-server` (and related) pods **`Running`**, the **`kubectl ... get secret argocd-initial-admin-secret`** line succeeds (Secret present), password length **> 0** bytes from the **`wc -c`** line (unless you already removed the Secret after rotating the admin user), an **Ingress** for Argo CD (see [`values-argocd.yaml`](../gitops/bootstrap/values-argocd.yaml) `server.ingress`), `curl` returns **`HTTP/1.1`** with **`302`** or **`200`** (not connection refused). Open **`http://argocd.127.0.0.1.nip.io/`** in a browser if you use the default hostname, then sign in as **`admin`** with the password from the command above.

9. **Wire Argo CD to GitHub**: create a `repository` Secret in `argocd` (see [`gitops/bootstrap/manifests/github-repo-secret.example.yaml`](../gitops/bootstrap/manifests/github-repo-secret.example.yaml)). Replace org/repo and PAT, then:

   ```bash
   kubectl apply -f gitops/bootstrap/manifests/github-repo-secret.example.yaml
   ```

   **Validate:**

   ```bash
   kubectl -n argocd get secret -l argocd.argoproj.io/secret-type=repository
   kubectl -n argocd get secret github-gitops -o jsonpath='{.data.url}' | base64 -d; echo
   ```

   Expect: at least one **repository** Secret with label **`argocd.argoproj.io/secret-type=repository`**. If you applied the example as-is, **`github-gitops`** exists and its `url` decodes to your GitHub **HTTPS** repo URL (no `CHANGE_ME` left). If you created the Secret under another name, substitute it in the `jsonpath` command.

10. **Replace placeholders** in GitOps manifests with your GitHub coordinates:

    - [`gitops/apps/app-project.yaml`](../gitops/apps/app-project.yaml)
    - [`gitops/apps/applicationset-spice-instances.yaml`](../gitops/apps/applicationset-spice-instances.yaml)
    - [`gitops/apps/application-control-plane.yaml`](../gitops/apps/application-control-plane.yaml)
    - [`gitops/bootstrap/manifests/application-root.yaml`](../gitops/bootstrap/manifests/application-root.yaml)

    Commit and push these changes to your GitHub `main` branch.

    **Validate (local repo):**

    ```bash
    if grep -rF 'CHANGE_ME' gitops/apps/ gitops/bootstrap/manifests/application-root.yaml 2>/dev/null; then
      echo 'ERROR: replace CHANGE_ME placeholders'
      exit 1
    else
      echo 'OK: no CHANGE_ME in listed paths'
    fi
    git status
    ```

    Expect: **`OK: no CHANGE_ME...`**, then `git status` shows a clean tree after commit (or only commits you still intend to push).

11. **Bootstrap the root Application** (one-time; this file is intentionally **outside** `gitops/apps/` to avoid self-recursion):

    ```bash
    kubectl apply -f gitops/bootstrap/manifests/application-root.yaml
    ```

    **Validate:**

    ```bash
    kubectl -n argocd get application platform-gitops -o wide
    kubectl -n argocd get applications
    kubectl -n argocd wait --for=jsonpath='{.status.health.status}'=Healthy application/platform-gitops --timeout=600s
    ```

    Expect: **`platform-gitops`** exists; **Sync** moves toward **Synced** and **Health** toward **Healthy** as child `Application`s under [`gitops/apps/`](../gitops/apps/) reconcile (first sync can take several minutes). If children stay **Unknown** for Git, re-check the repository Secret (step 9) and repo URLs in manifests.

    > **Note:** `kubectl wait` may time out while children are still syncing; re-run `kubectl -n argocd get applications` until the **control-plane** and instance apps look healthy, or use the Argo CD UI (**Optional: break-glass** below).

12. **Namespaces**: ensure `spice-instances` and `control-plane` exist (the control-plane `Application` uses `CreateNamespace=true`; you can also create them manually).

    **Validate:**

    ```bash
    kubectl get ns spice-instances control-plane
    ```

    Expect: both namespaces **`Active`**. If missing, either wait for Argo to create **`control-plane`**, or `kubectl create namespace spice-instances` (and **`control-plane`**) manually, then sync again.

---

## Part B — Control plane image on GHCR (Kind pulls like any cluster)

**Kind uses the same image as production:** [`deploy/helm/control-plane/values.yaml`](../deploy/helm/control-plane/values.yaml) points at **`ghcr.io/<owner>/<repo>/control-plane`** with an immutable **`image.tag`** (Git SHA) after CI runs. Kind nodes pull from **ghcr.io** over the network (no `kind load`).

Publishing is automated by [`.github/workflows/control-plane-image.yml`](../.github/workflows/control-plane-image.yml) (pushes to **`main`** that touch `apps/control-plane/**`, or **workflow_dispatch**): it pushes **`linux/amd64`** and **`linux/arm64`** (manifest list) as **`latest`** and **`:<git-sha>`** to GHCR, then commits the new **`image.tag`** into Git so Argo rolls the Deployment.

1. In GitHub, run **Actions → Control plane image → Run workflow** on `main` at least once (or merge a change under `apps/control-plane/` so the workflow runs). Wait until it finishes and the follow-up commit has updated **`image.tag`** in Git.
2. Ensure the GHCR package is **pullable from the Kind nodes** (outbound HTTPS to **ghcr.io**): keep the package **public**, or configure [`imagePullSecrets`](../deploy/helm/control-plane/values.yaml) plus a docker-registry secret in the **`control-plane`** namespace.

**Validate:**

```bash
kind get clusters | grep -F 'spice-gitops' || kind get clusters
# Optional: confirm the tag in Git matches what you expect Argo to deploy
grep -E '^\s+repository:|^\s+tag:' deploy/helm/control-plane/values.yaml
```

Expect: cluster **`spice-gitops`** exists when you continue from Part A; `repository` / `tag` reference GHCR (tag is a **40-character SHA** after CI, or **`latest`** only before the first successful publish—prefer running the workflow first so Argo pulls a real tag).

### Optional: local image into Kind (air-gapped / fast iteration)

If you cannot use GHCR from Kind, build and load a local tag, then override Helm on the Argo `Application` (for example **`image.repository=spice-control-plane`**, **`image.tag=latest`**) after:

```bash
make image-build
make image-load-local
```

---

## Part C — Secrets for the control plane workload

Create the `control-plane` namespace Secret expected by [`deploy/helm/control-plane/values.yaml`](../deploy/helm/control-plane/values.yaml):

```bash
kubectl create namespace control-plane --dry-run=client -o yaml | kubectl apply -f -

kubectl -n control-plane create secret generic control-plane-secrets \
  --from-literal=github_token='YOUR_GITHUB_TOKEN' \
  --from-literal=vault_token='YOUR_VAULT_TOKEN' \
  --from-literal=admin_api_key='YOUR_LONG_RANDOM_ADMIN_KEY'
```

**Validate:**

```bash
for k in github_token vault_token admin_api_key; do
  echo -n "$k: "
  kubectl -n control-plane get secret control-plane-secrets -o jsonpath="{.data.$k}" | wc -c
done
```

Expect: each key reports a **non-zero** base64 payload size (typically tens of characters or more).

Edit [`deploy/helm/control-plane/values.yaml`](../deploy/helm/control-plane/values.yaml) (or use `--set` when installing) so that:

- `env.githubOwner`, `env.githubRepo`, `env.githubBranch` match your repository.
- `ingress.host` is a hostname under `127.0.0.1.nip.io` (or your DNS) pointing at `127.0.0.1` where Kind maps ports 80/443.

Argo CD will deploy the chart when the `control-plane` `Application` syncs from Git. The workload image defaults to **GHCR**; after the first successful run of the **Control plane image** workflow, `image.tag` in Git is the commit SHA that built that image so each release rolls out cleanly.

**Validate (after Argo has synced the `control-plane` app at least once):**

```bash
kubectl -n argocd get application control-plane -o wide
kubectl -n control-plane rollout status deploy/control-plane --timeout=300s
kubectl -n control-plane exec deploy/control-plane -- node -e "fetch('http://127.0.0.1:3000/api/health').then(r=>r.text().then(t=>{console.log(t);if(!r.ok)process.exit(1)}))"
```

Expect: **`control-plane`** `Application` is **Synced** / **Healthy** (may take a minute after Git push), Deployment reaches **available**, the `node` one-liner prints JSON like **`{"ok":true,...}`**. If the `Application` is missing, complete step 11 and push chart changes so Argo creates it.

---

## Part D — Day 2: operate only through the webapp

After the ingress is reachable:

1. Open `https://<your-control-plane-host>/` (or `http://` if you terminate TLS elsewhere).
2. **Instances**: each instance must include **`ownerLayerSlug`** and matching **`spiceai.additionalLabels["owner-layer-slug"]`** in `instances/<name>/values.yaml` (the **New instance** form sets both). Argo deploys the [`charts/spice-instance`](../charts/spice-instance) chart, which requires `ownerLayerSlug` and labels Spice pods for cost attribution.
3. **Secrets**: the **Vault** panel writes KV to `spice/instances/<name>`; the chart’s `ExternalSecret` syncs into the Kubernetes `Secret` referenced by Spice `additionalEnv` (see [Spice Helm env pattern](https://spiceai.org/docs/deployment/kubernetes)).
4. **Admin** (`/admin`): paste `ADMIN_API_KEY` to load stack summary (Argo Applications, ESO resources, Vault health, pod snapshots) and **Load cost summary** (Git-declared estimates, live pods with `owner-layer-slug`, optional OpenCost + AWS Cost Explorer). Use **Sync** / **Refresh** on an Argo `Application` name (for example `spice-example`) without opening the Argo UI.

**Validate (through ingress, same host as `ingress.host` in chart values):**

```bash
CP_HOST=control-plane.127.0.0.1.nip.io
curl -sf "http://${CP_HOST}/api/health"
curl -sfI "http://${CP_HOST}/" | head -5
```

Expect: JSON **`{"ok":true,...}`** from `/api/health`, and **`HTTP/1.1`** from `/` (**`200`** or a Next.js redirect — not connection refused). Set **`CP_HOST`** to match your `deploy/helm/control-plane/values.yaml` `ingress.host` if you changed it.

### Cost governance (Kind as EKS)

- **Budgets**: defaults and per-slug caps live in [`deploy/helm/control-plane/budgets.default.yaml`](../deploy/helm/control-plane/budgets.default.yaml) (mounted into the pod as `/config/budgets.yaml`). Mirror for docs in [`gitops/cost/budgets.yaml`](../gitops/cost/budgets.yaml). Tune `maxInstancesPerSlug` / optional `maxEstimatedMonthlyUsdPerSlug`, sync the `control-plane` app, and restart if needed.
- **Declared cost estimates**: the control plane uses configurable **vCPU / GiB-month** factors. Set `cost.pricingJson` for explicit numbers, or **`cost.nodeInstanceType`** (Helm → **`COST_NODE_INSTANCE_TYPE`**) to pick a built-in EC2 reference (see [`apps/control-plane/src/lib/aws-pricing.ts`](../apps/control-plane/src/lib/aws-pricing.ts)). **`AWS_REGION`** is echoed in the cost summary for “Kind as EKS” alignment with Cost Explorer.
- **Remote MCP (FastMCP)**: **sidecar** on the control-plane pod serves **Streamable HTTP** at **`https://<ingress.host>/mcp`** (see [`apps/control-plane-mcp/README.md`](../apps/control-plane-mcp/README.md)). It is **enabled by default** in [`deploy/helm/control-plane/values.yaml`](../deploy/helm/control-plane/values.yaml) (`mcp.enabled`); set **`mcp.enabled: false`** to turn it off. Run the [**Control plane MCP image**](../.github/workflows/control-plane-mcp-image.yml) workflow (or merge a change under `apps/control-plane-mcp/`) so **`ghcr.io/<owner>/<repo>/control-plane-mcp`** exists before the pod can pull the sidecar. Optionally wire **`mcp.auth.*`** for `Authorization: Bearer`, sync Argo, then point Cursor / Claude at that URL.
- **OpenCost** (optional): see **Optional: Prometheus + OpenCost (Kind)** below. After OpenCost runs, set **`cost.opencostBaseUrl`** on the control-plane chart (in-cluster API, typically `http://opencost.opencost.svc.cluster.local:9003` when the OpenCost release name is **`opencost`**). The OpenCost **UI** can be exposed on port 80 via ingress; see [`gitops/addons/opencost/README.md`](../gitops/addons/opencost/README.md).
- **AWS Cost Explorer** (optional, real AWS only): attach an IAM role to the control-plane `ServiceAccount` (**IRSA**) using [`docs/iam-control-plane-cost-explorer.json`](../docs/iam-control-plane-cost-explorer.json), set `serviceAccount.annotations.eks.amazonaws.com/role-arn`, and set `cost.awsCostExplorerEnabled: "true"`. The API returns **account-level** last-30d unblended cost (not per slug). Skip on Kind unless you intentionally wire cloud credentials.
- **Kyverno** (optional admission): after [Kyverno](https://kyverno.io/) is installed, apply [`gitops/bootstrap/manifests/kyverno-require-owner-layer-slug.yaml`](../gitops/bootstrap/manifests/kyverno-require-owner-layer-slug.yaml) so Pods in **`spice-instances`** must carry label **`owner-layer-slug`**.
- **CI**: PRs touching `gitops/instances/**/values.yaml` run [`.github/workflows/validate-instances.yml`](../.github/workflows/validate-instances.yml) (`helm template` per instance).

### Optional: kube-prometheus-stack + OpenCost (Kind)

OpenCost (see [`gitops/addons/opencost/values-kind.yaml`](../gitops/addons/opencost/values-kind.yaml)) queries in-cluster Prometheus at **`http://kps-kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090`** (Helm release **`kps`**, namespace **`monitoring`**). If that Service does not exist, OpenCost logs show **`no such host`** / **`Prometheus communication error`** and the UI stays empty or degraded. Install **kube-prometheus-stack first**, then **OpenCost**, then point the control plane at OpenCost.

1. **Add Helm repos** (once per machine):

   ```bash
   helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
   helm repo add opencost https://opencost.github.io/opencost-helm-chart
   helm repo update
   ```

2. **Install kube-prometheus-stack** (Prometheus Operator + Prometheus + **Grafana**; Kind values — see [`gitops/addons/kube-prometheus-stack/README.md`](../gitops/addons/kube-prometheus-stack/README.md)):

   ```bash
   helm upgrade --install kps prometheus-community/kube-prometheus-stack \
     --version 85.2.2 \
     -n monitoring --create-namespace \
     -f gitops/addons/kube-prometheus-stack/values-kind.yaml
   kubectl -n monitoring rollout status deploy/kps-kube-prometheus-stack-operator --timeout=300s
   kubectl -n monitoring rollout status statefulset/prometheus-kps-kube-prometheus-stack-prometheus --timeout=300s
   kubectl -n monitoring rollout status deploy/kps-grafana --timeout=300s
   ```

   **Validate:**

   ```bash
   kubectl -n monitoring get svc kps-kube-prometheus-stack-prometheus
   ```

   Expect: Service **`kps-kube-prometheus-stack-prometheus`** in namespace **`monitoring`**, port **9090**, **`CLUSTER-IP`** assigned. Grafana ingress (same tutorial ingress-nginx on host port **80**): **`http://grafana.127.0.0.1.nip.io/`** (login **`admin` / `admin`** unless you changed it).

3. **Install OpenCost** (internal Prometheus client points at `kps` + **ingress-nginx** UI host `opencost.127.0.0.1.nip.io` — see [`gitops/addons/opencost/README.md`](../gitops/addons/opencost/README.md)):

   ```bash
   helm upgrade --install opencost opencost/opencost -n opencost --create-namespace \
     --version 1.33.1 -f gitops/addons/opencost/values-kind.yaml
   kubectl -n opencost rollout status deploy/opencost --timeout=300s
   ```

   **Validate:**

   ```bash
   kubectl -n opencost get ingress,svc,pods
   curl -sI --connect-timeout 3 -H "Host: opencost.127.0.0.1.nip.io" http://127.0.0.1/ | head -5
   ```

   Expect: **`Ingress`** for `opencost.127.0.0.1.nip.io`, OpenCost pod(s) **`Running`**, `curl` returns **`HTTP/1.1`** from nginx (not connection refused).

4. **Wire the control plane** (commit or override Helm values, then sync Argo):

   - Set **`cost.opencostBaseUrl`** to `http://opencost.opencost.svc.cluster.local:9003` (in-cluster allocation API on port **9003**).
   - Sync the **`control-plane`** `Application` and wait for rollout.

5. **Optional warnings:** OpenCost may still log missing series for **`kubecost_*`** network metrics unless you run Kubecost exporters; that is normal on a minimal Prometheus stack and does not block basic allocation views once Prometheus is up.

### Troubleshooting

| Symptom | Things to check |
|---------|------------------|
| OpenCost logs **`lookup kps-kube-prometheus-stack-prometheus.monitoring... no such host`** or empty UI | OpenCost expects Prometheus from **kube-prometheus-stack** (`kps` in `monitoring`). Install the stack per **Optional: kube-prometheus-stack + OpenCost (Kind)** above, then `kubectl -n opencost rollout restart deploy/opencost`. |
| OpenCost warnings about **`kubecost_pod_network_egress_bytes_total`** (or other `kubecost_*` metrics) | Normal without Kubecost exporters; core allocation can still work from standard kubelet / cAdvisor / kube-state-metrics scrapes. |
| `403` from GitHub API | Token scopes, `GITHUB_OWNER` / `GITHUB_REPO`, branch name, and whether branch protection blocks the automation user. |
| Argo `Unknown` / sync errors | Repo Secret in `argocd` namespace, placeholder URLs still present, or chart path `charts/spice-instance` / `valueFiles` path. |
| Vault read/write errors | `VAULT_TOKEN` in the control-plane Secret, KV v2 mount path, and Vault policies allowing the token to read/write `spice/instances/*`. |
| Control plane API returns **`fetch failed`** when saving instance secrets | The app calls Vault from inside the pod using **`VAULT_ADDR`**. Use the Vault **Service** DNS (default in chart: `http://vault.vault.svc.cluster.local:8200`). Hostnames like `vault-0.vault.svc.cluster.local` are usually wrong and fail DNS. Set `env.vaultAddr` in [`deploy/helm/control-plane/values.yaml`](../deploy/helm/control-plane/values.yaml), sync the `control-plane` app, and restart the deployment if needed. |
| ClusterSecretStore **InvalidProviderConfig** / `READY=False` | Run `kubectl describe clustersecretstore vault-backend` and read **Events** / status (connection errors, 403, “could not get secret”, wrong key). Confirm `kubectl -n external-secrets get secret vault-eso-token` and the data key is **`token`**. Confirm Vault is up (`kubectl -n vault get pods`) and the KV v2 mount exists at path **`secret`** (tutorial step 6). Fix the issue, then `kubectl delete clustersecretstore vault-backend --ignore-not-found` and `kubectl apply -f gitops/bootstrap/manifests/cluster-secret-store.yaml` so the controller re-validates. |
| ExternalSecret **Degraded** — `ClusterSecretStore "vault-backend" not found` | The store is **cluster-scoped** and must be applied once (after ESO CRDs and the `vault-eso-token` Secret). Run `kubectl apply -f gitops/bootstrap/manifests/cluster-secret-store.yaml` and `kubectl get clustersecretstore vault-backend`. If you renamed the store, set `externalSecret.clusterSecretStoreName` in the instance `values.yaml` to match. |
| ExternalSecret not syncing | `ClusterSecretStore` status, `vault-eso-token` Secret, and `externalSecret.vaultPath` in instance `values.yaml`. |
| `ClusterRole is not permitted in project spice-platform` | The `AppProject` **`clusterResourceWhitelist`** must allow RBAC objects installed by the control-plane chart. Update [`gitops/apps/app-project.yaml`](../gitops/apps/app-project.yaml) to include `ClusterRole` and `ClusterRoleBinding` for group `rbac.authorization.k8s.io`, commit, push, and sync. |
| `Resource not found in cluster: ... ClusterRoleBinding` / `ClusterRole` | Argo is comparing live state before a successful sync, or the UI is stale after fixing `AppProject`. Apply the updated [`gitops/apps/app-project.yaml`](../gitops/apps/app-project.yaml) if needed, then **Hard Refresh** and **Sync** the `control-plane` Application. List cluster RBAC and look for the release name plus `-gitops` (for example `control-plane-gitops` when `helm.releaseName` is `control-plane`). |
| `control-plane.*.nip.io` does not load (connection refused, timeout) | Kind maps **host** `127.0.0.1:80` to the **node** port 80. Bootstrap values must set **`controller.hostPort.enabled: true`** (see [`gitops/bootstrap/values-ingress-nginx.yaml`](../gitops/bootstrap/values-ingress-nginx.yaml)); otherwise the Service uses a high `NodePort` and nothing listens on 80. Re-run the Helm upgrade for ingress-nginx, wait for the controller pod to be Ready, then try `curl -sI -H "Host: control-plane.127.0.0.1.nip.io" http://127.0.0.1/`. On macOS, another process using port 80 can block Kind; check with `sudo lsof -iTCP:80 -sTCP:LISTEN`. |
| `argocd.*.nip.io` does not load | Same ingress-nginx / Kind port **80** checklist as the row above. Confirm the Argo CD Ingress exists: `kubectl -n argocd get ingress`. Re-apply values with `helm upgrade --install argocd ... -f gitops/bootstrap/values-argocd.yaml` if `server.ingress.enabled` was still false. |
| `ImagePullBackOff` / **`Failed to pull image`** `ghcr.io/.../control-plane` | Confirm the **Control plane image** workflow has run and the tag in Git matches GHCR. Kind needs outbound access to **ghcr.io**. For a **private** package, add a docker-registry pull secret in `control-plane` and set **`imagePullSecrets`** in [`deploy/helm/control-plane/values.yaml`](../deploy/helm/control-plane/values.yaml). For **air-gapped Kind**, use Part B optional **`make image-load-local`** and override Helm `image.repository` / `image.tag`. |
| `ImagePullBackOff` for **`.../control-plane-mcp`** | The chart defaults **`mcp.enabled: true`**; the sidecar image must exist in GHCR. Run the [**Control plane MCP image**](../.github/workflows/control-plane-mcp-image.yml) workflow (or temporarily set **`mcp.enabled: false`** until the image is available). Same pull-secret / public rules as the Next.js image. |
| **`no match for platform in manifest`** | The image manifest did not include your node’s CPU (common: **linux/arm64** Kind on Apple Silicon vs an **amd64-only** CI build). Re-run the **Control plane image** workflow after [`.github/workflows/control-plane-image.yml`](../.github/workflows/control-plane-image.yml) publishes **multi-arch** (`linux/amd64` + `linux/arm64`), then sync Argo / restart the Deployment. |
| `Resource not found in cluster: v1/Service:control-plane` | Namespaced objects were applied to **`default`** while Argo tracks **`control-plane`**. This chart now pins `metadata.namespace` (see `deploy/helm/control-plane/templates/_helpers.tpl`). Commit/push, **Refresh + Sync** the `control-plane` Application; remove stray `Service`/`Deployment` in `default` if they exist (check with `kubectl get svc,deploy -n default`). |

---

## Optional: break-glass

- Prefer the Ingress URL **`http://argocd.127.0.0.1.nip.io/`** (see [`gitops/bootstrap/values-argocd.yaml`](../gitops/bootstrap/values-argocd.yaml)); it stays available whenever ingress-nginx and Argo CD are running.
- If the Ingress is broken or you are off-cluster: `kubectl -n argocd port-forward svc/argocd-server 8080:80` (HTTP service port when `server.insecure` is enabled).
- Never rely on port-forward for routine operations if you want a strict control-plane-only workflow.

---

## References

- [Spice Helm — Kubernetes](https://spiceai.org/docs/deployment/kubernetes)
- [Argo CD ApplicationSet](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/)
- [External Secrets — Vault](https://external-secrets.io/latest/provider/hashicorp-vault/)
- [OpenCost addon](../gitops/addons/opencost/README.md) and [kube-prometheus-stack addon](../gitops/addons/kube-prometheus-stack/README.md) (Kind cost stack + Grafana)
