# Docs site (Astro + Starlight)

## Local dev

```bash
cd website
npm install
PUBLIC_ASTRO_SITE=http://localhost:4321 PUBLIC_ASTRO_BASE=/ npm run dev
```

## Build

`npm run build` runs `prebuild`, which copies [`../scripts/install.sh`](../scripts/install.sh) into `public/install.sh` so static hosting can serve **`/install.sh`**.

## GitHub Pages

Enable **Pages → GitHub Actions** in the repository settings.

The workflow [`.github/workflows/pages.yml`](../.github/workflows/pages.yml) defaults to:

- `PUBLIC_ASTRO_SITE=https://<owner>.github.io/<repo>/`
- `PUBLIC_ASTRO_BASE=/<repo>/`

Override with repository **Variables** `PUBLIC_ASTRO_SITE` and `PUBLIC_ASTRO_BASE` if you use a custom domain or user/org site at `/`.
