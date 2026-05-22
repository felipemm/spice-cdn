# GitOps layout moved

Runtime GitOps for your cluster now lives in a **separate repository** that you own. This product repository ships **templates** only.

- **Templates (canonical):** [`templates/gitops/`](../templates/gitops/) — Argo manifests, bootstrap Helm values, addons references.
- **Examples:** [`examples/instances/`](../examples/instances/) — instance `values.yaml` samples validated in CI.
- **Installer:** [`scripts/install.sh`](../scripts/install.sh) — downloads a **pinned GitHub Release** tarball, materializes the template tree into your GitOps repo, and bootstraps Kind.

### Migration from monorepo

If you previously used `gitops/apps` in this repo as Argo’s source:

1. Create an empty **GitOps** repository (any host).
2. Run `scripts/install.sh` (see project README) with your GitOps URL, or copy [`templates/gitops/`](../templates/gitops/) + charts from a release tarball manually.
3. Point Argo’s root `Application` at the new repo (see `templates/gitops/bootstrap/manifests/application-root.yaml`).
4. Set the control plane deployment env to your GitOps repo (`GITOPS_REPO_OWNER`, `GITOPS_REPO_NAME`, …).
