# Spice CDN platform — user guide

This project is the **product repository**: the Next.js **control plane**, Helm charts, GitOps **templates**, CI, and the **Kind + GitOps installer**. What Argo CD reconciles in the cluster lives in a **separate GitOps repository** that you own.

For architecture diagrams and the split between product and GitOps, see [README.md](../README.md) and, on the documentation site, **Guides → Product vs GitOps**.

---

## Prerequisites

| Tool | Purpose |
|------|---------|
| [Docker](https://docs.docker.com/get-docker/) | Kind nodes |
| [Kind](https://kind.sigs.k8s.io/docs/user/quick-start/) | Local Kubernetes |
| `kubectl` | Cluster access |
| [Helm 3](https://helm.sh/docs/intro/install/) | Used by the installer for bootstrap charts |
| `curl` | Download release bundle / `install.sh` |
| `openssl` | Random `admin_api_key` during bootstrap |

**GitHub:** an **empty** GitOps repository (HTTPS URL ending in `.git`) and a **personal access token** with **`repo`** scope on that repository (Argo reads the repo; the control plane uses the GitHub Contents API to commit instance YAML).

---

## Quick start — run the platform in a few steps

These steps assume you use the **published installer** from GitHub Pages (after you enable Pages on your fork) or from a **GitHub Release** checkout.

### 1. Create the GitOps repository

1. On GitHub, create a new **empty** repository (no README required), e.g. `my-org/spice-gitops`.
2. Create a **fine-grained** or **classic** PAT with **`repo`** (or at minimum **contents: read/write** on that repo). Store it securely.

### 2. Run the installer (one command)

From the docs site (replace placeholders with your GitHub Pages URL or raw `install.sh` URL):

```bash
curl -fsSL "https://<owner>.github.io/<repo>/install.sh" | bash
```

The script will prompt for:

- **GitOps repo URL** — must be HTTPS and end with `.git`, e.g. `https://github.com/my-org/spice-gitops.git`
- **Git PAT** — same token Argo and the control plane use (`GITOPS_PAT` or `GITHUB_TOKEN` can be pre-set)

**Non-interactive** (CI or “no prompts”):

```bash
export GITOPS_REPO_URL='https://github.com/my-org/spice-gitops.git'
export GITOPS_PAT='ghp_...'        # or: export GITHUB_TOKEN='...'
export YES=1
curl -fsSL "https://<owner>.github.io/<repo>/install.sh" | bash
```

### 3. What you get immediately

The installer:

1. Resolves a **pinned product version** (embedded in the packaged `install.sh` from releases, or [latest release](https://github.com/felipemm/spice-cdn/releases/latest) when piping generic `install.sh` without an embedded tag — override with `SPICE_RELEASE`).
2. **Materializes** a full GitOps tree under `SPICE_GITOPS_DIR` (default: `./spice-gitops-work`).
3. Creates a Kind cluster **`spice-gitops`** (override with `CLUSTER_NAME`) using the bundle’s `hack/kind-config.yaml` (ingress host ports 80/443).
4. Installs **ingress-nginx**, **Vault** (dev mode), **External Secrets Operator**, **Argo CD**, wires **Vault → ESO**, applies the **root Argo Application**, and creates **`control-plane-secrets`** (`gitops_token`, `vault_token`, `admin_api_key`).

### 4. Push GitOps and sync

```bash
cd spice-gitops-work   # or your SPICE_GITOPS_DIR
git init -b main
git remote add origin https://github.com/my-org/spice-gitops.git
git add -A
git commit -m "Bootstrap Spice platform GitOps"
git push -u origin main
```

In Argo CD (or CLI), ensure application **`platform-gitops`** syncs; child apps deploy **control-plane** and **Spice instances** from the same repo.

### 5. Open the UIs

| What | How |
|------|-----|
| **Argo CD** | Default ingress host in bootstrap values, e.g. `http://argocd.127.0.0.1.nip.io/` — password: `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' \| base64 -d` |
| **Control plane** | Default `http://control-plane.127.0.0.1.nip.io/` (see `deploy/helm/control-plane/values.yaml` `ingress.host`) |
| **Admin API key** | Printed into cluster Secret at install; retrieve: `kubectl -n control-plane get secret control-plane-secrets -o jsonpath='{.data.admin_api_key}' \| base64 -d` |

Health check:

```bash
curl -sf "http://control-plane.127.0.0.1.nip.io/api/health"
```

---

## Optional configurations

### Installer: CLI flags

| Flag | Meaning |
|------|---------|
| `--gitops-repo URL` | HTTPS GitOps URL (`.git`) |
| `--revision BRANCH` | Argo `targetRevision` (default: `main`) |
| `--release VERSION` | Product tarball version, e.g. `v0.2.0` |
| `--materialize DIR` | Only render GitOps tree to `DIR`; no cluster |
| `--upgrade` | Compare `~/.spice-platform/install.env` to latest GitHub release and re-materialize (remote GitOps only) |
| `--uninstall --all` | Delete Kind cluster `CLUSTER_NAME` |
| `--yes` | Skip confirmations |

Run `./scripts/install.sh --help` for the full usage text.

### Installer: environment variables

| Variable | Purpose |
|----------|---------|
| `SPICE_RELEASE` | Same as `--release`; overrides embedded packaged version |
| `SPICE_PRODUCT_REPO` | `owner/repo` for GitHub downloads (default: `felipemm/spice-cdn`) |
| `SPICE_GITOPS_DIR` | Output directory for materialized GitOps (default: `./spice-gitops-work`) |
| `GITOPS_REPO_URL` | GitOps HTTPS URL; required for non-interactive install |
| `GITOPS_PAT` / `GITHUB_TOKEN` | PAT for Argo repo secret + control plane |
| `GITOPS_TARGET_REVISION` | Branch/tag Argo tracks (default `main`) |
| `CLUSTER_NAME` | Kind cluster name (default `spice-gitops`) |
| `STATE_DIR` | Installer state (default `~/.spice-platform`) |
| `YES=1` | Non-interactive confirmations |
| `GITHUB_TOKEN` | Optional: private releases, upgrade API |

**Developers** — use the git tree instead of downloading a tarball:

```bash
export SPICE_RELEASE=0.0.0-dev
./scripts/install.sh --gitops-repo https://github.com/org/spice-gitops.git
```

**Materialize only** (generate files for a pipeline or manual review):

```bash
./scripts/install.sh --materialize ./out --gitops-repo https://github.com/org/spice-gitops.git
```

**Upgrade** materialized tree to latest product release:

```bash
export GITOPS_REPO_URL=https://github.com/org/spice-gitops.git
./scripts/install.sh --upgrade
```

### Control plane Helm (`deploy/helm/control-plane/values.yaml`)

After materialization, these keys live in your GitOps repo under `deploy/helm/control-plane/`. Common customizations:

| Area | Keys / notes |
|------|----------------|
| **Image** | `image.repository`, `image.tag` (CI publishes to GHCR; Kind pulls over the network) |
| **Pull secrets** | `imagePullSecrets` for private GHCR |
| **Ingress** | `ingress.host`, `ingress.className`, `ingress.annotations` |
| **GitOps API** | `env.gitopsRepoOwner`, `env.gitopsRepoName`, `env.gitopsRepoBranch` (installer substitutes from `--gitops-repo`) |
| **Vault** | `env.vaultAddr` — use Service DNS, e.g. `http://vault.vault.svc.cluster.local:8200` |
| **Secrets** | `secrets.*` — Kubernetes Secret name/keys for `gitops_token`, `vault_token`, `admin_api_key` |
| **Cost / OpenCost** | `cost.opencostBaseUrl`, `cost.awsCostExplorerEnabled`, `cost.nodeInstanceType`, `cost.pricingJson` |
| **Budgets** | `budgets.enabled`, `budgets.definition` |
| **MCP sidecar** | `mcp.enabled`, `mcp.image`, `mcp.auth.*` |

Pod env for the app is documented in the repo README (**`GITOPS_REPO_*`** / **`GITOPS_TOKEN`** mapping).

### Spice instance chart (`charts/spice-instance/values.yaml`)

Per-instance files live under `instances/<name>/values.yaml` in GitOps:

| Key | Purpose |
|-----|---------|
| `ownerLayerSlug` | Required; must match `spiceai.additionalLabels["owner-layer-slug"]` for cost attribution |
| `ingress.host` | Public hostname for this Spice HTTP API |
| `externalSecret.*` | Vault path → Kubernetes Secret for Spice env |
| `spiceai.*` | Upstream Spice Helm values ([Spice on Kubernetes](https://spiceai.org/docs/deployment/kubernetes)) |

Validated examples: [`examples/instances/`](../examples/instances/).

### Makefile (local development)

| Target | Action |
|--------|--------|
| `make kind-create` | Create Kind cluster from `hack/kind-config.yaml` |
| `make kind-delete` | Delete cluster `spice-gitops` |
| `make image-build` | Build `spice-control-plane:latest` from `apps/control-plane` |
| `make image-load-local` | Load image into Kind (when overriding chart away from GHCR) |
| `make install-help` | `scripts/install.sh --help` |

---

## Step-by-step guide (detailed)

### Phase A — Before you install

1. **Decide repositories:** product repo (this project) vs **your** GitOps repo.
2. **Create** the empty GitOps repo and a PAT with **`repo`** on it.
3. **Install tools:** Docker, Kind, kubectl, Helm 3, curl.

### Phase B — Run `install.sh`

1. Obtain `install.sh` from **GitHub Pages** or clone this repo and run `./scripts/install.sh`.
2. Provide **GitOps URL** and **PAT** (or export env vars + `YES=1` for CI).
3. Wait for **Bootstrap complete**; note paths printed for materialized GitOps and Argo admin password command.

### Phase C — Publish GitOps

1. `cd` into `SPICE_GITOPS_DIR`.
2. Initialize git, add remote, commit all files, **push to `main`** (or the branch you passed as `--revision`).
3. Confirm `platform-version.yaml` and `instances/` exist.

### Phase D — Argo CD reconciliation

1. Open Argo UI; log in as `admin`.
2. Locate **`platform-gitops`**; **Refresh** / **Sync** until **Healthy**.
3. Watch child applications (**control-plane**, **spice-*** instances). First sync can take several minutes.
4. If Git auth fails, verify namespace `argocd` has the repository Secret created by the installer (`github-gitops`).

### Phase E — Control plane and instances

1. Open the control plane URL (default `control-plane.127.0.0.1.nip.io`).
2. Use **Instances** to add Spice deployments (writes to GitOps `instances/`).
3. Use **Vault** panel for instance secrets (KV under `spice/instances/<name>`); chart `ExternalSecret` syncs into the cluster.
4. **`/admin`:** paste `ADMIN_API_KEY` for stack summary, cost views, and Argo actions.

### Phase F — Optional hardening and observability

- **Prometheus + Grafana + OpenCost:** follow [`templates/gitops/addons/kube-prometheus-stack/README.md`](../templates/gitops/addons/kube-prometheus-stack/README.md) and [`templates/gitops/addons/opencost/README.md`](../templates/gitops/addons/opencost/README.md), then set `cost.opencostBaseUrl` on the control-plane chart.
- **Kyverno:** apply [`templates/gitops/bootstrap/manifests/kyverno-require-owner-layer-slug.yaml`](../templates/gitops/bootstrap/manifests/kyverno-require-owner-layer-slug.yaml) after Kyverno is installed.
- **AWS Cost Explorer (EKS):** IRSA + `docs/iam-control-plane-cost-explorer.json` — see [tutorial.md](tutorial.md) Part D.

### Manual bootstrap (without the all-in-one installer)

If you prefer to run each Helm install yourself (or debug), follow **[docs/tutorial.md](tutorial.md)** — Part A walks through Kind, ingress-nginx, Vault, ESO, Argo, placeholders, and the root Application with validation commands after each step.

---

## Uninstall

```bash
./scripts/install.sh --uninstall --all
```

For non-interactive:

```bash
YES=1 ./scripts/install.sh --uninstall --all
```

This deletes the Kind cluster named `CLUSTER_NAME` (default `spice-gitops`). It does **not** delete your GitHub GitOps repository.

---

## Troubleshooting

See the large **Troubleshooting** table in **[docs/tutorial.md](tutorial.md)** (symptoms: OpenCost, GitHub 403, Argo `Unknown`, Vault/ESO, ingress port 80, `ImagePullBackOff`, multi-arch, etc.).

---

## Related documents

| Document | Content |
|----------|---------|
| [README.md](../README.md) | Product vs GitOps, CI, releases |
| [docs/tutorial.md](tutorial.md) | Manual Kind + GitOps day-0 with validations |
| [docs/migration-two-repos.md](migration-two-repos.md) | Moving from monorepo layout |
| [docs/github-pages-environment.md](github-pages-environment.md) | Pages / Astro env vars |
| [templates/gitops/bootstrap/README.md](../templates/gitops/bootstrap/README.md) | Bootstrap layout notes |
