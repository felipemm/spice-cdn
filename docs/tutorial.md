# Tutorial: Spice GitOps control plane on Kind

This guide follows the architecture in this repository: **GitHub** (GitOps source of truth), **Argo CD** (reconcile), **HashiCorp Vault** + **External Secrets Operator** (secrets), **ingress-nginx**, and the **Next.js control plane** (user + admin UI). It is **Kind-first** and splits **day‑0 bootstrap** (one-time automation) from **day‑2 operations** (webapp only).

Prerequisites:

- Docker, [Kind](https://kind.sigs.k8s.io/docs/user/quick-start/), `kubectl`, and [Helm 3](https://helm.sh/docs/intro/install/).
- A **GitHub repository** you control (fork or copy this repo), and a **PAT** or fine-grained token with **`contents: write`** on that repo (for the control plane) and read for Argo CD.

---

## Part A — Day 0: create the Kind cluster

1. Create the cluster (ingress-ready node labels and host port mappings are in [`hack/kind-config.yaml`](../hack/kind-config.yaml)):

   ```bash
   make kind-create
   ```

2. Install **ingress-nginx** (controller uses **hostPort** 80/443 so Kind’s `extraPortMappings` in [`hack/kind-config.yaml`](../hack/kind-config.yaml) reach nginx; a plain high `NodePort` alone would not):

   ```bash
   helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
   helm repo update
   helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
     -n ingress-nginx --create-namespace \
     -f gitops/bootstrap/values-ingress-nginx.yaml
   ```

3. Install **Vault** (reference values enable a **dev-style** server suitable only for disposable labs; see comments in [`gitops/bootstrap/values-vault.yaml`](../gitops/bootstrap/values-vault.yaml)):

   ```bash
   helm repo add hashicorp https://helm.releases.hashicorp.com
   helm repo update
   helm upgrade --install vault hashicorp/vault -n vault --create-namespace \
     -f gitops/bootstrap/values-vault.yaml
   ```

   Wait for `vault-0` to be Running. With `server.dev.enabled`, Vault auto-unseals in dev mode for local testing only.

4. Install **External Secrets Operator**:

   ```bash
   helm repo add external-secrets https://charts.external-secrets.io
   helm repo update
   helm upgrade --install external-secrets external-secrets/external-secrets \
     -n external-secrets --create-namespace \
     -f gitops/bootstrap/values-external-secrets.yaml
   ```

   **Verify CRDs before you apply the ClusterSecretStore (step 7):** if you apply `ClusterSecretStore` too early, `kubectl` will report `no matches for kind "ClusterSecretStore"` because the API is not registered yet. Wait until the CRD exists:

   ```bash
   kubectl get pods -n external-secrets
   kubectl get crd clustersecretstores.external-secrets.io
   ```

   You should see the CRD (Established). If `kubectl get crd ...` returns **NotFound**, fix the Helm release first (`helm status -n external-secrets external-secrets`, reinstall with `installCRDs: true` as in [`gitops/bootstrap/values-external-secrets.yaml`](../gitops/bootstrap/values-external-secrets.yaml)).

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

   **5c — Verify (optional):**

   ```bash
   kubectl -n external-secrets get secret vault-eso-token -o jsonpath='{.data.token}' | base64 -d; echo
   ```

   You should see your token printed (avoid shared screens / logs in real environments).

6. **KV mount** (before the ClusterSecretStore): enable KV v2 at path `secret` so it matches [`cluster-secret-store.yaml`](../gitops/bootstrap/manifests/cluster-secret-store.yaml) (`spec.provider.vault.path: secret`). Example:

   ```bash
   kubectl -n vault exec -it vault-0 -- vault secrets enable -path=secret kv-v2
   ```

   If the mount already exists, Vault prints an error such as `path is already in use` — that is fine; continue to step 7.

7. Apply the **ClusterSecretStore** (edit `server` in the manifest if your Vault Service differs), then confirm it becomes **Ready**:

   ```bash
   kubectl apply -f gitops/bootstrap/manifests/cluster-secret-store.yaml
   kubectl get clustersecretstore vault-backend
   ```

   You should see `READY` **True** after a short wait. If `STATUS` is **InvalidProviderConfig** or `READY` stays **False**, inspect the controller message (it usually names the exact failure):

   ```bash
   kubectl describe clustersecretstore vault-backend
   ```

   Typical causes: **`vault-eso-token` missing or wrong key** (must be data key `token` in namespace `external-secrets`); **wrong Vault URL** in the manifest (default `http://vault.vault.svc.cluster.local:8200` matches a Helm release named `vault` in namespace `vault`); **token invalid or expired**; **Vault pod not Ready**; **no KV v2 mount at path `secret`** (fix step 6, then delete and re-apply the ClusterSecretStore or wait for reconciliation).

   If the store object is missing entirely, every `ExternalSecret` that references `vault-backend` stays **Degraded** with `ClusterSecretStore ... not found`.

8. Install **Argo CD**:

   ```bash
   helm repo add argo https://argoproj.github.io/argo-helm
   helm repo update
   helm upgrade --install argocd argo/argo-cd -n argocd --create-namespace \
     -f gitops/bootstrap/values-argocd.yaml
   ```

9. **Wire Argo CD to GitHub**: create a `repository` Secret in `argocd` (see [`gitops/bootstrap/manifests/github-repo-secret.example.yaml`](../gitops/bootstrap/manifests/github-repo-secret.example.yaml)). Replace org/repo and PAT, then:

   ```bash
   kubectl apply -f gitops/bootstrap/manifests/github-repo-secret.example.yaml
   ```

10. **Replace placeholders** in GitOps manifests with your GitHub coordinates:

    - [`gitops/apps/app-project.yaml`](../gitops/apps/app-project.yaml)
    - [`gitops/apps/applicationset-spice-instances.yaml`](../gitops/apps/applicationset-spice-instances.yaml)
    - [`gitops/apps/application-control-plane.yaml`](../gitops/apps/application-control-plane.yaml)
    - [`gitops/bootstrap/manifests/application-root.yaml`](../gitops/bootstrap/manifests/application-root.yaml)

    Commit and push these changes to your GitHub `main` branch.

11. **Bootstrap the root Application** (one-time; this file is intentionally **outside** `gitops/apps/` to avoid self-recursion):

    ```bash
    kubectl apply -f gitops/bootstrap/manifests/application-root.yaml
    ```

    In the Argo CD UI (optional break-glass) or via automation, confirm `platform-gitops` syncs and child resources become Healthy.

12. **Namespaces**: ensure `spice-instances` and `control-plane` exist (the control-plane `Application` uses `CreateNamespace=true`; you can also create them manually).

---

## Part B — Build and load the control plane image

From the repository root:

```bash
make image-build
make image-load
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

Edit [`deploy/helm/control-plane/values.yaml`](../deploy/helm/control-plane/values.yaml) (or use `--set` when installing) so that:

- `env.githubOwner`, `env.githubRepo`, `env.githubBranch` match your repository.
- `ingress.host` is a hostname under `127.0.0.1.nip.io` (or your DNS) pointing at `127.0.0.1` where Kind maps ports 80/443.

Argo CD will deploy the chart when the `control-plane` `Application` syncs from Git.

---

## Part D — Day 2: operate only through the webapp

After the ingress is reachable:

1. Open `https://<your-control-plane-host>/` (or `http://` if you terminate TLS elsewhere).
2. **Instances**: create, edit `values.yaml`, delete — all commits go to GitHub under `instances/<name>/values.yaml`.
3. **Secrets**: the **Vault** panel writes KV to `spice/instances/<name>`; the chart’s `ExternalSecret` syncs into the Kubernetes `Secret` referenced by Spice `additionalEnv` (see [Spice Helm env pattern](https://spiceai.org/docs/deployment/kubernetes)).
4. **Admin** (`/admin`): paste `ADMIN_API_KEY` to load stack summary (Argo Applications, ESO resources, Vault health, pod snapshots). Use **Sync** / **Refresh** on an Argo `Application` name (for example `spice-example`) without opening the Argo UI.

### Troubleshooting

| Symptom | Things to check |
|---------|------------------|
| `403` from GitHub API | Token scopes, `GITHUB_OWNER` / `GITHUB_REPO`, branch name, and whether branch protection blocks the automation user. |
| Argo `Unknown` / sync errors | Repo Secret in `argocd` namespace, placeholder URLs still present, or chart path `charts/spice-instance` / `valueFiles` path. |
| Vault read/write errors | `VAULT_TOKEN` in the control-plane Secret, KV v2 mount path, and Vault policies allowing the token to read/write `spice/instances/*`. |
| ClusterSecretStore **InvalidProviderConfig** / `READY=False` | Run `kubectl describe clustersecretstore vault-backend` and read **Events** / status (connection errors, 403, “could not get secret”, wrong key). Confirm `kubectl -n external-secrets get secret vault-eso-token` and the data key is **`token`**. Confirm Vault is up (`kubectl -n vault get pods`) and the KV v2 mount exists at path **`secret`** (tutorial step 6). Fix the issue, then `kubectl delete clustersecretstore vault-backend --ignore-not-found` and `kubectl apply -f gitops/bootstrap/manifests/cluster-secret-store.yaml` so the controller re-validates. |
| ExternalSecret **Degraded** — `ClusterSecretStore "vault-backend" not found` | The store is **cluster-scoped** and must be applied once (after ESO CRDs and the `vault-eso-token` Secret). Run `kubectl apply -f gitops/bootstrap/manifests/cluster-secret-store.yaml` and `kubectl get clustersecretstore vault-backend`. If you renamed the store, set `externalSecret.clusterSecretStoreName` in the instance `values.yaml` to match. |
| ExternalSecret not syncing | `ClusterSecretStore` status, `vault-eso-token` Secret, and `externalSecret.vaultPath` in instance `values.yaml`. |
| `ClusterRole is not permitted in project spice-platform` | The `AppProject` **`clusterResourceWhitelist`** must allow RBAC objects installed by the control-plane chart. Update [`gitops/apps/app-project.yaml`](../gitops/apps/app-project.yaml) to include `ClusterRole` and `ClusterRoleBinding` for group `rbac.authorization.k8s.io`, commit, push, and sync. |
| `Resource not found in cluster: ... ClusterRoleBinding` / `ClusterRole` | Argo is comparing live state before a successful sync, or the UI is stale after fixing `AppProject`. Apply the updated [`gitops/apps/app-project.yaml`](../gitops/apps/app-project.yaml) if needed, then **Hard Refresh** and **Sync** the `control-plane` Application. List cluster RBAC and look for the release name plus `-gitops` (for example `control-plane-gitops` when `helm.releaseName` is `control-plane`). |
| `control-plane.*.nip.io` does not load (connection refused, timeout) | Kind maps **host** `127.0.0.1:80` to the **node** port 80. Bootstrap values must set **`controller.hostPort.enabled: true`** (see [`gitops/bootstrap/values-ingress-nginx.yaml`](../gitops/bootstrap/values-ingress-nginx.yaml)); otherwise the Service uses a high `NodePort` and nothing listens on 80. Re-run the Helm upgrade for ingress-nginx, wait for the controller pod to be Ready, then try `curl -sI -H "Host: control-plane.127.0.0.1.nip.io" http://127.0.0.1/`. On macOS, another process using port 80 can block Kind; check with `sudo lsof -iTCP:80 -sTCP:LISTEN`. |
| `Resource not found in cluster: v1/Service:control-plane` | Namespaced objects were applied to **`default`** while Argo tracks **`control-plane`**. This chart now pins `metadata.namespace` (see `deploy/helm/control-plane/templates/_helpers.tpl`). Commit/push, **Refresh + Sync** the `control-plane` Application; remove stray `Service`/`Deployment` in `default` if they exist (check with `kubectl get svc,deploy -n default`). |

---

## Optional: break-glass

- `kubectl -n argocd port-forward svc/argocd-server 8080:443` to reach Argo CD when ingress is not configured.
- Never rely on this for routine operations if you want a strict control-plane-only workflow.

---

## References

- [Spice Helm — Kubernetes](https://spiceai.org/docs/deployment/kubernetes)
- [Argo CD ApplicationSet](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/)
- [External Secrets — Vault](https://external-secrets.io/latest/provider/hashicorp-vault/)
