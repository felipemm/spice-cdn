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

## Build the control plane image

```bash
make image-build
```

For Kind:

```bash
make kind-create
make image-load
```

Full bootstrap and configuration variables are documented in **[`docs/tutorial.md`](docs/tutorial.md)**.
