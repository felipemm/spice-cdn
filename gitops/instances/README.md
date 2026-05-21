# Instance folders

Each subdirectory `instances/<name>/` contains at least:

- `values.yaml` — Helm values for the wrapper chart [`charts/spice-instance`](../../charts/spice-instance) (including `spiceai.*` and `ingress.host`).

Optional:

- Enable `externalSecret` in `values.yaml` to render an `ExternalSecret` that syncs Vault KV into a Kubernetes `Secret` referenced by `spiceai.additionalEnv`.

The Argo CD `ApplicationSet` in [`gitops/apps/applicationset-spice-instances.yaml`](../apps/applicationset-spice-instances.yaml) discovers every `instances/*` path and deploys one Helm release per folder.

Replace `CHANGE_ME_ORG/CHANGE_ME_REPO` in GitOps manifests before syncing.
