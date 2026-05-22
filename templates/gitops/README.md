# GitOps templates (product repo)

This directory is **not** the Argo CD source of truth. It is a **template tree** copied into your operator-owned **GitOps repository** by `scripts/install.sh` (from a [GitHub Release](https://github.com/) tarball).

Placeholders (replaced at install time):

| Token | Meaning |
|--------|---------|
| `__GITOPS_REPO_HTTPS_URL__` | HTTPS clone URL of your GitOps repo (with `.git` suffix) |
| `__GITOPS_TARGET_REVISION__` | Argo `targetRevision` (e.g. `main`, `HEAD`, or a tag) |
| `__PLATFORM_RELEASE__` | Pinned product release tag (e.g. `v0.1.0`) |

Layout after materialization at the **root of your GitOps repo**:

- `apps/` — Argo `AppProject`, `ApplicationSet`, `Application` for the control plane
- `bootstrap/` — Helm values + one-shot manifests (Vault, ESO, ingress, root `Application`)
- `charts/spice-instance/`, `deploy/helm/control-plane/` — copied from the release tarball
- `instances/` — your environment-specific values
- `platform-version.yaml` — tracks the installed platform release
