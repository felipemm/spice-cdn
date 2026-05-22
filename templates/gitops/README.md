# GitOps templates (product repo)

This directory is **not** the Argo CD source of truth. It is a **template tree** copied into your operator-owned **GitOps repository** by `scripts/install.sh` (from a [GitHub Release](https://github.com/) tarball).

Placeholders (replaced at install time):

| Token | Meaning |
|--------|---------|
| `__GITOPS_REPO_HTTPS_URL__` | Git clone URL written into Argo sources (HTTPS for GitHub remotes; `http://…` for the local Kind + Gitea lab) |
| `__GITOPS_TARGET_REVISION__` | Argo `targetRevision` (e.g. `main`, `HEAD`, or a tag) |
| `__PLATFORM_RELEASE__` | Pinned product release tag (e.g. `v0.1.0`) |
| `__GITOPS_APP_INSECURE__` | When the URL is plain HTTP, set to `insecure: true` under `Application` sources (otherwise empty) |
| `__GITOPS_APPSET_GIT_INSECURE__` | Same for the ApplicationSet `git` generator |
| `__GITOPS_APPSET_SRC_INSECURE__` | Same for the ApplicationSet template `source` |

Layout after materialization at the **root of your GitOps repo**:

- `apps/` — Argo `AppProject`, `ApplicationSet`, `Application` for the control plane
- `bootstrap/` — Helm values + one-shot manifests (Vault, ESO, ingress, root `Application`)
- `charts/spice-instance/`, `deploy/helm/control-plane/` — copied from the release tarball
- `instances/` — your environment-specific values
- `platform-version.yaml` — tracks the installed platform release
