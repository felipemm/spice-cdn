# Gitea Actions

Workflows in this directory mirror [`.github/workflows/`](../.github/workflows/) for the same repo. On the **local Kind + Gitea** install path, `scripts/install.sh` also deploys the **`gitea-charts/actions`** chart (act_runner + DinD) using [`templates/gitops/bootstrap/values-gitea-actions.yaml`](../templates/gitops/bootstrap/values-gitea-actions.yaml) so jobs with `runs-on: ubuntu-latest` can execute without manual runner registration.

| Workflow | Purpose |
|----------|---------|
| `control-plane-image.yml` | Build `apps/control-plane`, push to **this Gitea host’s container registry**, bump `.image` in `deploy/helm/control-plane/values.yaml`. |
| `control-plane-mcp-image.yml` | Build `apps/control-plane-mcp`, push to the same registry, bump `.mcp.image`. |
| `validate-instances.yml` | `helm template` over `examples/instances/*/values.yaml`. |
| `release.yml` | On `v*` tags, build the platform tarball and create a Gitea release with attachments. |
| `pages.yml` | Build the Starlight site; uploads `website/dist` as a workflow artifact (no GitHub Pages deploy). |

For the Kind lab, Actions/packages are enabled in Helm and an act runner is installed by `scripts/install.sh` unless you set **`SPICE_SKIP_GITEA_ACTIONS_RUNNER=1`**. On other Gitea hosts, enable Actions in admin settings, register a runner (or deploy `gitea-charts/actions`), and match each job’s **`runs-on`** label (default **`ubuntu-latest`**). See [templates/gitops/bootstrap/README.md](../templates/gitops/bootstrap/README.md).
