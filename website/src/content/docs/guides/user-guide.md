---
title: User guide
description: Quick start, optional install settings, and a full walkthrough of the Spice CDN platform.
---

See the canonical **[User guide (full)](https://github.com/felipemm/spice-cdn/blob/main/docs/USER_GUIDE.md)** in the repository for the complete document (single source on GitHub).

Below is the same content for offline reading in Starlight.

---

<!-- Keep aligned with docs/USER_GUIDE.md in the repository root. -->

:::note
If you maintain this site in a **fork**, update the GitHub links on this page to your `owner/repo`.
:::

## Introduction

This project is the **product repository**: the Next.js **control plane**, Helm charts, GitOps **templates**, CI, and the **Kind + GitOps installer**. What Argo CD reconciles in the cluster lives in a **separate GitOps repository** that you own.

For architecture diagrams and the split between product and GitOps, see the repository [README](https://github.com/felipemm/spice-cdn#readme) and [Product vs GitOps](./architecture).

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

**GitHub (remote GitOps):** an **empty** GitOps repository (HTTPS URL ending in `.git`) and a **personal access token** with **`repo`** scope on that repository.

**Local lab:** omit `--gitops-repo` to use in-cluster Gitea — see [Install](./install#requirements).

---

## Quick start

### 1. Create the GitOps repository

1. On GitHub, create a new **empty** repository, e.g. `my-org/spice-gitops`.
2. Create a PAT with **`repo`** (or **contents: read/write** on that repo).

### 2. Run the installer

From this site (adjust the URL for your deployment):

```bash
curl -fsSL "https://<owner>.github.io/<repo>/install.sh" | bash
```

The script prompts for **GitOps repo URL** (HTTPS, ends with `.git`) and **Git PAT** (`GITOPS_PAT` or `GITHUB_TOKEN` can be pre-set).

**Non-interactive:**

```bash
export GITOPS_REPO_URL='https://github.com/my-org/spice-gitops.git'
export GITOPS_PAT='ghp_...'
export YES=1
curl -fsSL "https://<owner>.github.io/<repo>/install.sh" | bash
```

### 3. What the installer does

1. Resolves a **pinned product version** (release embed, or latest on GitHub — override with `SPICE_RELEASE`).
2. **Materializes** GitOps under `SPICE_GITOPS_DIR` (default `./spice-gitops-work`).
3. Creates Kind **`spice-gitops`** (`CLUSTER_NAME` overrides).
4. Installs **ingress-nginx**, **Vault** (dev), **ESO**, **Argo CD**, **ClusterSecretStore**, root **Application**, and **`control-plane-secrets`**.

### 4. Push GitOps

```bash
cd spice-gitops-work
git init -b main
git remote add origin https://github.com/my-org/spice-gitops.git
git add -A && git commit -m "Bootstrap Spice platform GitOps" && git push -u origin main
```

Sync **`platform-gitops`** in Argo.

### 5. Open the UIs

| What | How |
|------|-----|
| **Argo CD** | e.g. `http://argocd.127.0.0.1.nip.io/` — password from `argocd-initial-admin-secret` |
| **Control plane** | e.g. `http://control-plane.127.0.0.1.nip.io/` |
| **Admin key** | `kubectl -n control-plane get secret control-plane-secrets -o jsonpath='{.data.admin_api_key}' \| base64 -d` |

```bash
curl -sf "http://control-plane.127.0.0.1.nip.io/api/health"
```

---

## Optional configurations

### Installer flags

`--gitops-repo`, `--revision`, `--release`, `--materialize DIR`, `--upgrade`, `--uninstall --all`, `--yes` — see `./scripts/install.sh --help`.

### Installer environment

`SPICE_RELEASE`, `SPICE_PRODUCT_REPO`, `SPICE_GITOPS_DIR`, `GITOPS_REPO_URL`, `GITOPS_PAT`, `GITHUB_TOKEN`, `GITOPS_TARGET_REVISION`, `CLUSTER_NAME`, `STATE_DIR`, `YES`.

**Dev tree:** `export SPICE_RELEASE=0.0.0-dev` and run `./scripts/install.sh` from a clone.

**Materialize only:** `./scripts/install.sh --materialize ./out --gitops-repo https://github.com/org/spice-gitops.git`

**Upgrade:** `GITOPS_REPO_URL=... ./scripts/install.sh --upgrade`

### Helm

- **Control plane:** `deploy/helm/control-plane/values.yaml` — ingress, GHCR image, GitOps env, Vault addr, cost/OpenCost, MCP, budgets.
- **Instances:** `charts/spice-instance` — `ownerLayerSlug`, ingress, `externalSecret`, `spiceai` keys.

### Makefile

`make kind-create`, `make kind-delete`, `make image-build`, `make image-load-local`, `make install-help`, `make gitops-push-gitea` (re-push lab GitOps to Gitea).

---

## Step-by-step guide

1. **Prepare:** empty GitOps repo + PAT; install Docker, Kind, kubectl, Helm, curl.
2. **Install:** run `install.sh` with URL + PAT (or env + `YES=1`).
3. **Publish:** push materialized tree to GitHub `main` (or your `--revision` branch).
4. **Sync Argo:** `platform-gitops` → Healthy; child apps deploy control plane and instances.
5. **Operate:** control plane UI for instances/secrets; `/admin` with API key; optional Prometheus/OpenCost/Kyverno per repo `templates/gitops/addons/` and [tutorial](https://github.com/felipemm/spice-cdn/blob/main/docs/tutorial.md) Part D.

**Manual bootstrap** (step-by-step with validations after each Helm install): [docs/tutorial.md](https://github.com/felipemm/spice-cdn/blob/main/docs/tutorial.md).

---

## Uninstall

```bash
YES=1 ./scripts/install.sh --uninstall --all
```

---

## More links

- [Install](./install) — short install reference
- [Product vs GitOps](./architecture) — two-repo model and GitOps backends
- [Changelog](../reference/changelog) — release notes
- [Tutorial](https://github.com/felipemm/spice-cdn/blob/main/docs/tutorial.md) — troubleshooting table
- [Migration](https://github.com/felipemm/spice-cdn/blob/main/docs/migration-two-repos.md)
