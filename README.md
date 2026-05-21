# Spice GitOps control plane (Kind + GitHub + Vault + Argo CD)

This repository implements a **Next.js control plane** that manages **Spice.ai** Helm deployments through **GitOps** (GitHub as source of truth, **Argo CD** as reconciler), with **HashiCorp Vault** + **External Secrets Operator** for secret material, and a **Kind**-first local path.

## What lives here

| Path | Purpose |
|------|---------|
| [`apps/control-plane`](apps/control-plane) | Next.js app: instances CRUD via GitHub Contents API, Vault KV editor, Argo sync/refresh + **admin** stack dashboard + **cost / budgets** (optional OpenCost + AWS Cost Explorer). |
| [`charts/spice-instance`](charts/spice-instance) | Wrapper Helm chart around upstream `spiceai` + Ingress + optional `ExternalSecret`; requires **`ownerLayerSlug`** / **`owner-layer-slug`** labels. |
| [`gitops/apps`](gitops/apps) | Argo CD `AppProject`, `ApplicationSet` (`instances/*`), `Application` for the control plane. |
| [`gitops/bootstrap`](gitops/bootstrap) | Reference Helm values + one-shot manifests (ingress, Vault, ESO, Argo, root `Application`, optional **Kyverno** policy for `owner-layer-slug`). |
| [`gitops/instances`](gitops/instances) | Per-instance `values.yaml` folders discovered by the `ApplicationSet`. |
| [`gitops/cost`](gitops/cost) | Budget defaults (mirror of Helm `budgets.default.yaml`; tune per-slug caps). |
| [`gitops/addons/opencost`](gitops/addons/opencost) | Optional OpenCost UI/API + Kind ingress notes. |
| [`gitops/addons/prometheus`](gitops/addons/prometheus) | **Optional** Prometheus for Kind — required for OpenCost’s default in-cluster queries (`prometheus-server.prometheus-system`). |
| [`hack/kind-config.yaml`](hack/kind-config.yaml) | Kind cluster with ingress-ready node + host port mappings. |
| [`docs/tutorial.md`](docs/tutorial.md) | **Step-by-step** Kind tutorial (day‑0 bootstrap vs day‑2 webapp-only operations). |

## Quick links

- [Spice Helm on Kubernetes](https://spiceai.org/docs/deployment/kubernetes)
- [External Secrets — Vault provider](https://external-secrets.io/latest/provider/hashicorp-vault/)

## Control plane image

**GitHub Actions + Kind:** On push to `main` (when `apps/control-plane` changes), [`.github/workflows/control-plane-image.yml`](.github/workflows/control-plane-image.yml) builds a **multi-arch** image (`linux/amd64` + `linux/arm64` for Kind on Apple Silicon), pushes **`ghcr.io/<owner>/<repo>/control-plane`**, and commits **`image.tag`** into [`deploy/helm/control-plane/values.yaml`](deploy/helm/control-plane/values.yaml). Argo CD applies that chart and kubelet **pulls from GHCR** (no `kind load`). Use **Actions → Control plane image → Run workflow** to bootstrap or refresh after workflow changes.

**Optional — local image into Kind** (air-gapped or fast iteration): `make image-build` then `make image-load-local`, and override Helm `image.repository` / `image.tag` on the Argo `Application` (see [tutorial](docs/tutorial.md) Part B).

Full bootstrap and configuration variables are documented in **[`docs/tutorial.md`](docs/tutorial.md)**.
