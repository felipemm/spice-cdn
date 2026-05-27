# GitOps templates (product repo)

This directory is **not** the Argo CD source of truth. It is a **template tree** copied into your operator-owned **GitOps repository** by `scripts/install.sh` (from a [GitHub Release](https://github.com/) tarball).

Placeholders (replaced at install time):

| Token | Meaning |
|--------|---------|
| `__GITOPS_REPO_HTTPS_URL__` | Git clone URL written into Argo sources (HTTPS for GitHub remotes; `http://…` for the local Kind + Gitea lab) |
| `__GITOPS_TARGET_REVISION__` | Argo `targetRevision` (e.g. `main`, `HEAD`, or a tag) |
| `__PLATFORM_RELEASE__` | Pinned product release tag (e.g. `v0.1.0`) |

**HTTP / plain Git (Kind + Gitea):** Argo CD no longer accepts `insecure` on `Application.spec.source` or on ApplicationSet generator `source` fields (strict API decoding). Use a `repository` Secret with `insecure: "true"` for the repo URL — `scripts/install.sh` already does this when the GitOps URL is `http://…`.

Layout after materialization at the **root of your GitOps repo**:

- `apps/` — Argo `AppProject`, `ApplicationSet`, `Application` for the control plane (install also copies `addons/**/application-*.yaml` here so the root `platform-gitops` app, which only watches `apps/*.yaml`, deploys kube-prometheus-stack, OpenCost, and Superset)
- `bootstrap/` — Helm values + one-shot manifests (Vault, ESO, ingress, root `Application`)
- `charts/spice-instance/`, `deploy/helm/control-plane/` — copied from the release tarball (control-plane `env.gitopsBackend` / `env.gitopsGiteaApiBaseUrl`: GitHub API by default; local Kind + Gitea installs set `gitea` + in-cluster `/api/v1` URL so instance CRUD uses Gitea REST instead of `api.github.com`)
- `instances/` — your environment-specific values
- `platform-version.yaml` — tracks the installed platform release
