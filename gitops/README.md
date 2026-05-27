# GitOps layout moved

Runtime GitOps for your cluster lives in a **separate repository** that you own. This product repository ships **templates** only — not the Argo CD source of truth.

## Where things live

| What | Location |
|------|----------|
| **Templates (canonical)** | [`templates/gitops/`](../templates/gitops/) — Argo manifests, bootstrap Helm values, addon references |
| **Examples** | [`examples/instances/`](../examples/instances/) — sample `values.yaml` + `vault-seed.json` validated in CI |
| **Installer** | [`scripts/install.sh`](../scripts/install.sh) — downloads a **pinned GitHub Release** tarball, materializes the template tree, bootstraps Kind |
| **Release history** | [`CHANGELOG.md`](../CHANGELOG.md) |

After `install.sh` runs, your **GitOps repo** (GitHub HTTPS or in-cluster Gitea for the local lab) contains:

- `apps/` — `AppProject`, `ApplicationSet`, control-plane `Application`, and copied addon apps
- `bootstrap/` — ingress, Vault, ESO, Argo, root `Application` manifests
- `charts/spice-instance/`, `deploy/helm/control-plane/` — chart sources Argo reads from the same repo
- `instances/*` — per-environment Spice values
- `platform-version.yaml` — pinned product release marker

See [`templates/gitops/README.md`](../templates/gitops/README.md) for placeholder tokens (`__GITOPS_REPO_HTTPS_URL__`, etc.) and HTTP/Gitea notes.

## Quick paths

- **GitHub GitOps (production-style):** create an empty repo → `install.sh --gitops-repo https://github.com/org/repo.git --gitops-pat "$TOKEN"` → push materialized tree → sync Argo `platform-gitops`.
- **Local lab (no GitHub repo):** run `install.sh` with no `--gitops-repo` — Gitea + Valkey + optional Gitea Actions inside Kind; credentials under `~/.spice-platform/`. Re-push with `make gitops-push-gitea`.

Full walkthrough: [docs/USER_GUIDE.md](../docs/USER_GUIDE.md) and the [documentation site](https://felipemm.github.io/spice-cdn/) (Guides → User guide / Install).

## Migration from monorepo

If you previously used `gitops/apps` **in this product repository** as Argo’s source:

1. Create an empty **GitOps** repository (GitHub, Gitea, or other Git host).
2. Run `scripts/install.sh` (see [README](../README.md)) with your GitOps URL, or copy [`templates/gitops/`](../templates/gitops/) + charts from a [release tarball](https://github.com/felipemm/spice-cdn/releases).
3. Migrate existing `instances/*` folders into the new repo.
4. Point Argo’s root `Application` at the new repo (`templates/gitops/bootstrap/manifests/application-root.yaml` after placeholder substitution).
5. Configure the control plane: `GITOPS_REPO_OWNER`, `GITOPS_REPO_NAME`, `GITOPS_REPO_BRANCH`, `GITOPS_TOKEN` (Helm: `env.gitopsRepo*` + `secrets.gitopsTokenSecretKey`). For the Kind + Gitea lab, set `GITOPS_BACKEND=gitea` and `GITOPS_GITEA_API_BASE_URL`.

Details: [docs/migration-two-repos.md](../docs/migration-two-repos.md).
