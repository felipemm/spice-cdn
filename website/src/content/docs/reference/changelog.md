---
title: Changelog
description: Release history for the Spice CDN platform (Keep a Changelog).
---

The canonical file is [`CHANGELOG.md`](https://github.com/felipemm/spice-cdn/blob/main/CHANGELOG.md) in the product repository. Below is the same content for offline reading on this site.

---

# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Local Kind lab without GitHub:** omit `--gitops-repo` to bootstrap Gitea in-cluster, push the materialized GitOps tree over HTTP, and wire Argo with an `insecure` repository Secret.
- **Valkey** for Gitea session/cache/queue; **Gitea Actions** act_runner for `.gitea/workflows` CI parity.
- **Control plane GitOps backends:** `GITOPS_BACKEND=github` (default) or `gitea` with `GITOPS_GITEA_API_BASE_URL`.
- **Superset integration:** optional SQL Lab database per instance after Argo Synced + Healthy.
- **Instance deploy readiness** polling and **Cluster access URLs** page (`/cluster-urls`).
- **ExternalSecret** for control-plane Vault KV; **databricks** example instance; `make gitops-push-gitea`.

### Changed

- Prefer `GITOPS_*` env vars over legacy `GITHUB_*`; expanded user guide and installer local-lab behavior.

### Fixed

- Installer robustness for `curl … | bash`, token normalization, and non-interactive bootstrap defaults.

## [0.1.1] - 2026-05-22

### Added

- Pages workflow embeds packaged release tag into served `install.sh`.

### Fixed

- Installer reliability for curl-piped and GitHub Pages installs.

## [0.1.0] - 2026-05-22

First public release: control plane, spice-instance chart, GitOps templates, Kind installer, cost monitoring, ingress, MCP sidecar, docs site, and release tarball CI.

### Added

- Control plane UI + GitHub Contents API for `instances/*`; admin API; OpenCost/cost Explorer hooks.
- `scripts/install.sh` + `spice-platform-v*.tar.gz` releases; Astro/Starlight documentation site.
- CI for images, instance YAML validation, GitHub Pages, and tagged releases.

### Changed

- Runtime GitOps moved out of this repo; use `templates/gitops/` and an operator-owned GitOps repository.

[unreleased]: https://github.com/felipemm/spice-cdn/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/felipemm/spice-cdn/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/felipemm/spice-cdn/releases/tag/v0.1.0
