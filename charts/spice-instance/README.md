# `spice-instance` wrapper chart

This chart vendors the upstream **Spice.ai OSS** chart as a Helm dependency and adds:

- **Ingress** for HTTP access to Spice (`ingress.host`, `ingress.className`).
- Optional **`ExternalSecret`** (External Secrets Operator + Vault KV v2).

## Upstream Spice chart

- Repository: `https://helm.spiceai.org`
- Chart: `spiceai`
- Pinned version: see [`Chart.yaml`](./Chart.yaml) / [`Chart.lock`](./Chart.lock).

Common values are passed under the `spiceai:` key (subchart values), for example:

- **`ownerLayerSlug`** (parent chart) — **required**; must match **`spiceai.additionalLabels["owner-layer-slug"]`** so Pods get the label. Upstream **spiceai 1.11.6** merges `spiceai.additionalLabels` into workload metadata via the `spiceai.labels` helper (see vendored chart `templates/deployment.yaml`).
- `spiceai.spicepod` — Spicepod manifest ([docs](https://spiceai.org/docs/deployment/kubernetes))
- `spiceai.additionalEnv` — environment variables, including `valueFrom.secretKeyRef` for Kubernetes Secrets ([docs](https://spiceai.org/docs/deployment/kubernetes))
- `spiceai.service`, `spiceai.resources`, `spiceai.stateful`, `spiceai.image`, etc.

## Cost attribution (`owner-layer-slug`)

Every release must set **`ownerLayerSlug`** (DNS-like lowercase label). The chart:

- Renders a small **`ConfigMap`** carrying the slug (so Helm fails if it is missing).
- Adds **`owner-layer-slug`** to **Ingress** and **ExternalSecret** metadata.
- Expects **`spiceai.additionalLabels.owner-layer-slug`** to match for Pod labels (set by the control-plane instance template).

Optional cluster policy: apply [`gitops/bootstrap/manifests/kyverno-require-owner-layer-slug.yaml`](../../gitops/bootstrap/manifests/kyverno-require-owner-layer-slug.yaml) after Kyverno is installed.

## Ingress

Set `ingress.enabled: true` and **`ingress.host`** to a hostname that resolves to your ingress controller (for Kind + `nip.io`, e.g. `spice-demo.127.0.0.1.nip.io`).

## External Secrets + Vault

When `externalSecret.enabled: true`, this chart renders an `ExternalSecret` that uses the cluster `ClusterSecretStore` named `externalSecret.clusterSecretStoreName` (default `vault-backend`) and syncs Vault path `externalSecret.vaultPath` into `externalSecret.targetSecretName`.

**Prerequisite:** that `ClusterSecretStore` must exist on the cluster (for this repo, apply [`gitops/bootstrap/manifests/cluster-secret-store.yaml`](../../gitops/bootstrap/manifests/cluster-secret-store.yaml) during bootstrap; see `docs/tutorial.md`). If the store is missing, `ExternalSecret` stays **Degraded** with `ClusterSecretStore ... not found`.

Regenerate vendored dependency (if you bump the version in `Chart.yaml`):

```bash
helm dependency update
```

(Helm CLI required.)
