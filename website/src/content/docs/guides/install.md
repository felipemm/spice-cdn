---
title: Install
description: Pin installs to GitHub Releases and bootstrap Kind + Argo.
---

## Requirements

- Docker, [Kind](https://kind.sigs.k8s.io/), `kubectl`, Helm 3
- Empty **GitOps** repository (GitHub HTTPS URL ending in `.git`)
- Personal access token with **`repo`** scope on that GitOps repository

## One-liner

From this site (set `site` / `base` in `astro.config.mjs` for GitHub Pages project pages):

```bash
curl -fsSL https://<your-site>/install.sh | bash
```

The served `install.sh` embeds a default **packaged release** tag. Override with:

```bash
SPICE_RELEASE=v0.1.0 bash ./install.sh
```

## Local materialize only

From a git checkout of the **product** repository:

```bash
./scripts/install.sh --materialize ./out --gitops-repo https://github.com/org/my-gitops.git
```

## Upgrade

```bash
GITOPS_REPO_URL=https://github.com/org/my-gitops.git ./scripts/install.sh --upgrade
```

Compares your last install (`~/.spice-platform/install.env`) to `releases/latest` on the product repo, then re-downloads and re-materializes.

## Uninstall

```bash
./scripts/install.sh --uninstall --all --yes
```

Deletes the Kind cluster named `spice-gitops` (override with `CLUSTER_NAME`).
