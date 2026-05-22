---
title: Product vs GitOps
description: Two-repository model and what lives where.
---

## Repositories

| | **Product repo** | **GitOps repo** |
|---|------------------|-----------------|
| **Purpose** | Application source, Helm charts, `install.sh`, CI, docs site | What Argo CD reconciles (`instances/*`, materialized `apps/`, charts copy) |
| **Argo `repoURL`** | Not used for sync | Your HTTPS Git URL only |

The installer downloads a **GitHub Release** tarball of the product, substitutes `__GITOPS_*__` placeholders, and writes a self-contained tree you commit to the GitOps repo.

## Files in the materialized tree

- `apps/` — `AppProject`, `ApplicationSet`, `Application` for the control plane
- `bootstrap/` — Helm values for ingress, Vault, ESO, Argo, one-shot manifests
- `charts/spice-instance/`, `deploy/helm/control-plane/` — chart sources Argo reads from the **same** GitOps repo
- `instances/*` — per-environment Spice values
- `platform-version.yaml` — pinned product release marker

## Control plane API

The Next.js app uses **GitHub Contents API** (Octokit) against the **GitOps** repository. Configure:

- `GITOPS_REPO_OWNER`, `GITOPS_REPO_NAME`, `GITOPS_REPO_BRANCH`
- `GITOPS_TOKEN` (legacy `GITHUB_*` still accepted)
