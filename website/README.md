# Docs site (Astro + Starlight)

## Local dev

```bash
cd website
npm install
PUBLIC_ASTRO_SITE=http://localhost:4321 PUBLIC_ASTRO_BASE=/ npm run dev
```

## Build

`npm run build` runs `prebuild` → [`scripts/embed-install-release.mjs`](scripts/embed-install-release.mjs), which copies [`../scripts/install.sh`](../scripts/install.sh) to `public/install.sh`. If **`PUBLIC_SPICE_PACKAGED_RELEASE`** is set (e.g. `v0.1.0`), that line is embedded so `curl …/install.sh | bash` defaults to that release without passing `SPICE_RELEASE`.

```bash
PUBLIC_SPICE_PACKAGED_RELEASE=v0.1.0 npm run build
```

## GitHub Pages

Enable **Pages → GitHub Actions** in the repository settings.

The workflow [`.github/workflows/pages.yml`](../.github/workflows/pages.yml):

- After a **tag release**, [`.github/workflows/release.yml`](../.github/workflows/release.yml) dispatches Pages on **`main`** with input **`spice_release`** set to the tag, so **`public/install.sh`** embeds that version without needing the `github-pages` environment to allow tag refs (see [GitHub Pages environment](../docs/github-pages-environment.md)).
- Runs on **`push` to `main`** when `website/`, `scripts/install.sh`, or the workflow changes; on those pushes it queries **`releases/latest`** and embeds that tag (needs at least one published release).
- **`workflow_dispatch`** accepts optional input **spice_release** to force a tag without publishing a release.

Defaults:

- `PUBLIC_ASTRO_SITE=https://<owner>.github.io/<repo>/`
- `PUBLIC_ASTRO_BASE=/<repo>/`

Override with repository **Variables** `PUBLIC_ASTRO_SITE` and `PUBLIC_ASTRO_BASE` if you use a custom domain or user/org site at `/`.
