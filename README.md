# Spice GitOps control plane (Kind + GitHub + Vault + Argo CD)

This repository implements a **Next.js control plane** that manages **Spice.ai** Helm deployments through **GitOps** (GitHub as source of truth, **Argo CD** as reconciler), with **HashiCorp Vault** + **External Secrets Operator** for secret material, and a **Kind**-first local path.

## What lives here

| Path | Purpose |
|------|---------|
| [`apps/control-plane`](apps/control-plane) | Next.js app: instances CRUD via GitHub Contents API, Vault KV editor, Argo sync/refresh + **admin** stack dashboard. |
| [`charts/spice-instance`](charts/spice-instance) | Wrapper Helm chart around upstream `spiceai` + Ingress + optional `ExternalSecret`. |
| [`gitops/apps`](gitops/apps) | Argo CD `AppProject`, `ApplicationSet` (`instances/*`), `Application` for the control plane. |
| [`gitops/bootstrap`](gitops/bootstrap) | Reference Helm values + one-shot manifests (ingress, Vault, ESO, Argo, root `Application`). |
| [`gitops/instances`](gitops/instances) | Per-instance `values.yaml` folders discovered by the `ApplicationSet`. |
| [`hack/kind-config.yaml`](hack/kind-config.yaml) | Kind cluster with ingress-ready node + host port mappings. |
| [`docs/tutorial.md`](docs/tutorial.md) | **Step-by-step** Kind tutorial (day‑0 bootstrap vs day‑2 webapp-only operations). |

## Quick links

- [Spice Helm on Kubernetes](https://spiceai.org/docs/deployment/kubernetes)
- [External Secrets — Vault provider](https://external-secrets.io/latest/provider/hashicorp-vault/)

## Control plane image

**GitOps / cluster:** On push to `main` (when `apps/control-plane` changes), [`.github/workflows/control-plane-image.yml`](.github/workflows/control-plane-image.yml) builds the app, pushes **`ghcr.io/<owner>/<repo>/control-plane`** with tags **`latest`** and **`<git-sha>`**, and commits the new **`image.tag`** into [`deploy/helm/control-plane/values.yaml`](deploy/helm/control-plane/values.yaml) so Argo CD rolls out the new image. Use **Actions → Control plane image → Run workflow** to bootstrap the first image after enabling Actions.

**Local Kind (no registry):**

```bash
make image-build
make kind-create
make image-load
```

Override the Argo Helm values to use `spice-control-plane:latest` if the cluster should use the image loaded into Kind instead of GHCR (see [tutorial](docs/tutorial.md) GHCR section).

Full bootstrap and configuration variables are documented in **[`docs/tutorial.md`](docs/tutorial.md)**.
