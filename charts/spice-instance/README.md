# `spice-instance` wrapper chart

This chart vendors the upstream **Spice.ai OSS** chart as a Helm dependency and adds:

- **Ingress** for HTTP access to Spice (`ingress.host`, `ingress.className`).
- Optional **`ExternalSecret`** (External Secrets Operator + Vault KV v2).

## Upstream Spice chart

- Repository: `https://helm.spiceai.org`
- Chart: `spiceai`
- Pinned version: see [`Chart.yaml`](./Chart.yaml) / [`Chart.lock`](./Chart.lock).

Common values are passed under the `spiceai:` key (subchart values), for example:

- `spiceai.spicepod` — Spicepod manifest ([docs](https://spiceai.org/docs/deployment/kubernetes))
- `spiceai.additionalEnv` — environment variables, including `valueFrom.secretKeyRef` for Kubernetes Secrets ([docs](https://spiceai.org/docs/deployment/kubernetes))
- `spiceai.service`, `spiceai.resources`, `spiceai.stateful`, `spiceai.image`, etc.

## Ingress

Set `ingress.enabled: true` and **`ingress.host`** to a hostname that resolves to your ingress controller (for Kind + `nip.io`, e.g. `spice-demo.127.0.0.1.nip.io`).

## External Secrets + Vault

When `externalSecret.enabled: true`, this chart renders an `ExternalSecret` that uses the cluster `ClusterSecretStore` named `externalSecret.clusterSecretStoreName` (default `vault-backend`) and syncs Vault path `externalSecret.vaultPath` into `externalSecret.targetSecretName`.

Regenerate vendored dependency (if you bump the version in `Chart.yaml`):

```bash
helm dependency update
```

(Helm CLI required.)
