# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.2] - 2026-05-28

### Added

- **Installer optional features:** interactive menu (bash / gum / dialog) and CLI flags `--features` / `--without-features` for Prometheus + Grafana, OpenCost, Superset, and Gitea Actions; selection persisted as `SPICE_FEATURES` in `install.env`.
- **Host dependency bootstrap:** installer reports missing host tools and offers to install curl, tar, openssl, git, Docker, kubectl, Helm, and Kind (`--yes` and piped installs proceed without prompts).
- **OpenCost (Kind):** custom AWS pricing model (m5.xlarge, us-east-1) via `opencost.customPricing` in addon values and the Argo Application.

### Changed

- **Materialization:** copy only enabled addon Argo Applications; lab credential patches and Vault Superset seed respect feature selection (`gitops-lab-patches.sh`, `install.sh`).
- **Upgrade:** restore `SPICE_FEATURES` from `install.env` when re-materializing.
- **Docs:** user guide and install guide cover the feature menu and dependency checks; Superset README documents StatefulSet delete + hard refresh when adding the Postgres PVC.

### Fixed

- **Docs site:** home page install command block no longer clips long `curl` lines (CSS `fit-content` / `pre-wrap`).

## [0.2.1] - 2026-05-27

### Changed

- **Argo CD (Kind bootstrap):** raise `application-controller` and `repoServer` memory limits in `templates/gitops/bootstrap/values-argocd.yaml` so large Helm apps (e.g. kube-prometheus-stack) sync without OOMing mid-operation.
- **Superset (Kind addon):** enable bundled PostgreSQL **8Gi** PVC in `values-kind.yaml` / `application-superset.yaml` so SQL Lab metadata survives pod restarts; document upgrade, `SUPERSET_SECRET_KEY` stability, and Argo prune behavior in the addon README.

### Fixed

- **Argo CD:** controller stuck in **Syncing** (`operationState.phase=Running`) when memory limit was too low during prometheus-stack manifest generation.

## [0.2.0] - 2026-05-27

### Added

- **Local Kind lab without GitHub:** omit `--gitops-repo` (or `curl … | bash` with no args) to bootstrap Gitea in-cluster, push the materialized GitOps tree over HTTP, and wire Argo with an `insecure` repository Secret (Argo CD no longer allows `insecure` on `Application.spec.source`).
- **Valkey** standalone chart for Gitea session/cache/queue (`templates/gitops/bootstrap/values-valkey.yaml`); password files under `STATE_DIR` (`~/.spice-platform` by default).
- **Gitea Actions** act_runner via `gitea-charts/actions` for CI parity with GitHub (`.gitea/workflows/` copied into release bundles); skip with `SPICE_SKIP_GITEA_ACTIONS_RUNNER=1`.
- **Control plane GitOps backends:** `GITOPS_BACKEND=github` (Octokit / GitHub Contents API, default) or `GITOPS_BACKEND=gitea` with `GITOPS_GITEA_API_BASE_URL` (`apps/control-plane/src/lib/gitea-gitops.ts`).
- **Superset integration:** optional SQL Lab database per instance after Argo **Synced** + **Healthy** (`superset-service.ts`, `POST /api/instances/[name]/superset`); Vault/ESO path via `externalSecret.syncSuperset` and `vault-seed.example.json`.
- **Instance deploy readiness:** poll Argo CD until `spice-<name>` is Synced + Healthy before Superset registration (`instance-readiness.ts`).
- **Cluster access URLs** page (`/cluster-urls`) for Kind lab ingress links and per-instance Spice hosts.
- **ExternalSecret** template for control-plane Vault KV sync (`deploy/helm/control-plane/templates/external-secret.yaml`).
- **Examples:** `examples/instances/databricks/` with `vault-seed.json`.
- **Makefile** target `gitops-push-gitea` and script `scripts/push-gitea-gitops.sh` for re-pushing the lab GitOps tree to in-cluster Gitea.
- **Documentation:** expanded [docs/USER_GUIDE.md](docs/USER_GUIDE.md) (optional install settings, Superset, observability); [CHANGELOG.md](CHANGELOG.md) and site **Reference → Changelog**.

### Changed

- **GitOps env naming:** prefer `GITOPS_REPO_OWNER`, `GITOPS_REPO_NAME`, `GITOPS_REPO_BRANCH`, `GITOPS_TOKEN`; legacy `GITHUB_*` variables still accepted.
- **Installer:** local lab builds/pushes control-plane images into Kind when `SPICE_LOCAL_CLUSTER_MODE=1`; seeds Vault for all `instances/*/vault-seed.json` and control-plane Superset keys; writes `grafana-superset-credentials.txt` for addon apps.
- **Materialized tree:** `templates/gitops/README.md` documents placeholder tokens, HTTP/Gitea Argo repo secrets, and addon apps copied under `apps/` for root `platform-gitops` sync.
- **Release workflow:** tarball may include `.gitea/`; tag push dispatches Pages workflow so `public/install.sh` embeds the release tag.

### Fixed

- **Installer:** robust handling when run as `curl … | bash` (`BASH_SOURCE` unset under `set -u`); token normalization (CRLF, stray commas); piped installs default confirmations to `--yes` for bootstrap steps.

## [0.1.1] - 2026-05-22

### Added

- **Pages workflow:** embed packaged release tag into `website/public/install.sh` via `website/scripts/embed-install-release.mjs` on release tags.

### Fixed

- **Installer:** reliability fixes for curl-piped installs and GitHub Pages–served `install.sh`.

## [0.1.0] - 2026-05-22

First public platform release: product repository + operator-owned GitOps repository.

### Added

- **Control plane** Next.js app: list/create/delete Spice instances by committing `instances/<name>/values.yaml` to the GitOps repo (GitHub Contents API).
- **Admin API** (`ADMIN_API_KEY`): stack summary, cost views, Argo actions.
- **Cost monitoring:** OpenCost integration, owner-layer budgets, AWS Cost Explorer hooks (`cost.*` Helm values).
- **Helm charts:** `charts/spice-instance` (Spice.ai runtime wrapper), `deploy/helm/control-plane`.
- **GitOps templates** under `templates/gitops/`: Argo `AppProject`, root `Application`, `ApplicationSet` for instances, bootstrap values (ingress-nginx, Vault dev, ESO, Argo CD).
- **Installer** `scripts/install.sh`: download pinned **GitHub Release** tarball (`spice-platform-v*.tar.gz`), substitute `__GITOPS_*__` placeholders, materialize tree, bootstrap Kind + platform stack.
- **Ingress** per instance and control plane (nip.io defaults on Kind).
- **MCP sidecar** `apps/control-plane-mcp` (FastMCP) with optional auth in Helm values.
- **Observability addons** references: kube-prometheus-stack, OpenCost, Grafana (under `templates/gitops/addons/`).
- **CI:** control-plane and MCP image builds; `validate-instances` on `examples/instances/**`; **release** workflow publishing platform tarball + SHA256; **Pages** workflow for Astro/Starlight docs site.
- **Documentation site** (`website/`): Install, Product vs GitOps, user guide mirror; `install.sh` copied to `public/` at build time.
- **Docs:** [docs/USER_GUIDE.md](docs/USER_GUIDE.md), [docs/tutorial.md](docs/tutorial.md), [docs/migration-two-repos.md](docs/migration-two-repos.md).
- **Examples** `examples/instances/example/` validated in CI.
- **Makefile** `kind-create` / `kind-delete` using `hack/kind-config.yaml` (host ports 80/443).

### Changed

- **Repository layout:** runtime GitOps is no longer the source of truth in this repo; `gitops/` at repo root is a pointer — templates live in `templates/gitops/`.

[unreleased]: https://github.com/felipemm/spice-cdn/compare/v0.2.2...HEAD
[0.2.2]: https://github.com/felipemm/spice-cdn/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/felipemm/spice-cdn/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/felipemm/spice-cdn/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/felipemm/spice-cdn/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/felipemm/spice-cdn/releases/tag/v0.1.0
