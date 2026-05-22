# GitHub Pages environment and protected deployments

The [Pages workflow](../.github/workflows/pages.yml) uses `actions/deploy-pages`, which targets the **`github-pages`** deployment environment. If that environment has **deployment branch rules** (for example, only `main`), workflows that run on a **tag ref** (such as `refs/tags/v0.1.1`) are rejected with an error like:

> Tag "v0.1.1" is not allowed to deploy to github-pages due to environment protection rules.

## Option A — Allow tag deploys (repo settings)

1. Open **Settings → Environments → `github-pages`**.
2. Under **Deployment branches and tags**, add a rule that includes your release tags (for example **Selected tags** with pattern `v*`), or use a rule that matches how you ship releases.

After that, you can run the Pages workflow from tag refs if you add a `release` or `push: tags` trigger again.

## Option B — Keep “main only” and dispatch from the release workflow (default in this repo)

The [Release workflow](../.github/workflows/release.yml) runs on tag push, publishes the bundle, then **dispatches** the Pages workflow with `ref: main` and workflow input `spice_release` set to the tag. The Pages job still deploys from the `github-pages` environment as a **main** run, while `public/install.sh` is built with the correct release tag embedded.

No environment rule change is required for that path.
