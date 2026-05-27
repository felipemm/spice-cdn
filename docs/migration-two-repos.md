# Migrating from a single repo to product + GitOps

If you previously kept `gitops/apps` and `instances/*` **in this product repository** as Argo’s source of truth:

1. Create a new **GitOps** repository (empty `main` branch).
2. Run `./scripts/install.sh --materialize /tmp/gitops-export --gitops-repo https://github.com/YOU/NEW-GITOPS.git` (from a tagged **release** tarball or `SPICE_RELEASE=0.0.0-dev` inside a checkout).
3. Copy your existing `instances/*` folders into `/tmp/gitops-export/instances/`, commit, and push to the new repo.
4. Update Argo’s repository Secret (`argocd` namespace) to point at the new URL and PAT.
5. Re-apply the root `Application` manifest from `templates/gitops/bootstrap/manifests/application-root.yaml` (after placeholder substitution) so `repoURL` matches the new GitOps repo.
6. Set the control-plane workload env to the same org/repo (`GITOPS_REPO_*`) and mount a PAT with **contents:write** on the GitOps repo (`gitops_token` key by default).

CI in this product repo now validates only `examples/instances/*/values.yaml`.

For release history after the split, see [CHANGELOG.md](../CHANGELOG.md).
