---
title: Product vs GitOps
description: Two-repository model and what lives where.
---

## Repositories

| | **Product repo** | **GitOps repo** |
|---|------------------|-----------------|
| **Purpose** | Application source, Helm charts, `install.sh`, CI, docs site | What Argo CD reconciles (`instances/*`, materialized `apps/`, charts copy) |
| **Argo `repoURL`** | Not used for sync | Your Git HTTPS URL (GitHub) or in-cluster Gitea HTTP URL (local lab) |

The installer downloads a **GitHub Release** tarball of the product, substitutes `__GITOPS_*__` placeholders, and writes a self-contained tree you commit to the GitOps repo (or push to in-cluster Gitea when no remote URL is given).

The old `gitops/` directory at the product repo root is only a **pointer** — see [gitops/README](https://github.com/felipemm/spice-cdn/blob/main/gitops/README.md).

## Files in the materialized tree

- `apps/` — `AppProject`, `ApplicationSet`, `Application` for the control plane (addon `application-*.yaml` files are copied here so root `platform-gitops` deploys observability apps)
- `bootstrap/` — Helm values for ingress, Valkey, Gitea (local lab), Vault, ESO, Argo, one-shot manifests
- `charts/spice-instance/`, `deploy/helm/control-plane/` — chart sources Argo reads from the **same** GitOps repo
- `instances/*` — per-environment Spice values
- `platform-version.yaml` — pinned product release marker

## Control plane API

The Next.js app reads and writes `instances/*` in the **GitOps** repository:

| Backend | When | Configure |
|---------|------|-----------|
| **GitHub** (default) | Remote GitHub GitOps repo | `GITOPS_BACKEND=github` (default), `GITOPS_REPO_OWNER`, `GITOPS_REPO_NAME`, `GITOPS_REPO_BRANCH`, `GITOPS_TOKEN` |
| **Gitea** | Local Kind lab (installer omits `--gitops-repo`) | `GITOPS_BACKEND=gitea`, `GITOPS_GITEA_API_BASE_URL` (e.g. `http://gitea-http.gitea.svc.cluster.local:3000/api/v1`), same owner/repo/branch/token as the Gitea admin |

Legacy `GITHUB_*` environment variables are still accepted.

Optional **Superset** SQL Lab databases are created per instance when Vault/ESO supplies `SUPERSET_*` credentials and Argo reports **Synced** + **Healthy**.

## Release notes

See [Changelog](../reference/changelog) or [CHANGELOG.md on GitHub](https://github.com/felipemm/spice-cdn/blob/main/CHANGELOG.md).
