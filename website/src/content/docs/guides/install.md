---
title: Install
description: Pin installs to GitHub Releases and bootstrap Kind + Argo.
---

## Requirements

- Docker, [Kind](https://kind.sigs.k8s.io/), `kubectl`, Helm 3, and **`git`** (for local-only mode). The installer checks these up front and can install missing CLIs after you confirm (or automatically with **`--yes`** / piped `curl | bash`).
- **Optional addons** (Prometheus/Grafana, OpenCost, Superset, Gitea Actions in local lab): interactive multi-select during install; default is all on. Use **`--without-features opencost,superset`** or **`--features prometheus,superset`** for non-interactive runs. Selection is stored as **`SPICE_FEATURES`** in **`~/.spice-platform/install.env`**.
- **Remote GitOps:** pass **`--gitops-repo https://github.com/org/repo.git`** and **`--gitops-pat`** (or rely on `GITHUB_TOKEN` where your environment already provides it). The GitOps repo should be empty to start; the PAT needs access to push instance manifests.
- **Local-only lab:** omit **`--gitops-repo`**. The installer creates a Kind cluster, installs **Gitea** (with ingress at `http://gitea.127.0.0.1.nip.io/` by default), materializes the GitOps tree, pushes it to Gitea once, and points Argo at an in-cluster **HTTP** clone URL. A random admin password is generated (same value Argo uses as the repository credential) unless you pass **`--gitops-pat`** yourself. The password is written to **`~/.spice-platform/gitea-local-credentials.txt`** (mode `600`). **Grafana** and **Superset** (optional Argo apps) get random secrets too; see **`~/.spice-platform/grafana-superset-credentials.txt`** plus `grafana-lab.password`, `superset-lab.password`, and `superset-lab.secret-key` in the same directory (also referenced from **`~/.spice-platform/install.env`**).

## One-liner

From this site (set `site` / `base` in `astro.config.mjs` for GitHub Pages project pages):

```bash
curl -fsSL https://<your-site>/install.sh | bash
```

Same command with **no** `--gitops-repo` runs **local-only** (piped installs also default confirmations to “yes” for bootstrap; use **`--yes`** explicitly for `--uninstall` when piping).

The served `install.sh` embeds a default **packaged release** tag. Override with **`--release`** or a prefix env for one shot:

```bash
./scripts/install.sh --release v0.1.0
```

## Local materialize only

From a git checkout of the **product** repository:

```bash
./scripts/install.sh --materialize ./out --gitops-repo https://github.com/org/my-gitops.git
```

To generate a tree **without** a real remote (placeholder `github.com/local/...` in manifests for you to find/replace or push later):

```bash
./scripts/install.sh --materialize ./out
```

## Upgrade

Uses `~/.spice-platform/install.env` (remote installs only):

```bash
./scripts/install.sh --upgrade
```

Compares your last install to `releases/latest` on the product repo, then re-downloads and re-materializes.

## Remote install from curl

```bash
curl -fsSL https://<your-site>/install.sh | bash -s -- --gitops-repo https://github.com/org/gitops.git --gitops-pat "$TOKEN"
```

## Optional features (non-interactive)

```bash
# Skip OpenCost and Superset (Prometheus/Grafana still installed)
./scripts/install.sh --without-features opencost,superset --yes

# Monitoring + Superset only
./scripts/install.sh --features prometheus,superset --yes
```

## Uninstall

```bash
./scripts/install.sh --uninstall --all --yes
```

Deletes the Kind cluster named `spice-gitops` (override with `CLUSTER_NAME`).

## Related

- [User guide](./user-guide) — full walkthrough including local Gitea lab credentials
- [Changelog](../reference/changelog) — release history
