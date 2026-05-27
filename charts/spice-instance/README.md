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

Optional cluster policy: apply [`templates/gitops/bootstrap/manifests/kyverno-require-owner-layer-slug.yaml`](../../templates/gitops/bootstrap/manifests/kyverno-require-owner-layer-slug.yaml) after Kyverno is installed.

## Ingress

Set `ingress.enabled: true` and **`ingress.host`** to a hostname that resolves to your ingress controller (for Kind + `nip.io`, e.g. `spice-demo.127.0.0.1.nip.io`).

**Port 80 (and 443 with TLS):** Kubernetes Ingress always attaches rules to the controller’s **standard HTTP(S) ports**. You open **`http://<ingress.host>/`** (no `:8090` in the URL). The controller **proxies** that traffic to the Spice `Service` port **`ingress.httpBackendPort`** (default **8090**), which is where `spiced` listens. Override **`ingress.httpBackendPort`** only if you change the Spice HTTP listen port in the upstream chart.

## Local access without Ingress (port-forward)

The upstream chart exposes **8090** (HTTP), **9090** (metrics), and **50051** (Arrow Flight) on the workload `Service` (`<helm-release>-spiceai`). Ingress in this chart only fronts **8090**. To reach **8090** or **50051** from your laptop without going through nginx, use `kubectl port-forward` against that Service (same pattern for both ports):

```bash
# HTTP API (optional if you already use the Ingress host)
kubectl -n spice-instances port-forward svc/<helm-release>-spiceai 8090:8090

# Arrow Flight
kubectl -n spice-instances port-forward svc/<helm-release>-spiceai 50051:50051
```

Replace **`<helm-release>`** with the instance release name (for example **`example`** → Service **`example-spiceai`**).

## External Secrets + Vault

When `externalSecret.enabled: true`, this chart renders an `ExternalSecret` that uses the cluster `ClusterSecretStore` named `externalSecret.clusterSecretStoreName` (default `vault-backend`) and syncs Vault path `externalSecret.vaultPath` into `externalSecret.targetSecretName`.

**Prerequisite:** that `ClusterSecretStore` must exist on the cluster (for this repo, apply [`templates/gitops/bootstrap/manifests/cluster-secret-store.yaml`](../../templates/gitops/bootstrap/manifests/cluster-secret-store.yaml) during bootstrap; see `docs/tutorial.md`). If the store is missing, `ExternalSecret` stays **Degraded** with `ClusterSecretStore ... not found`.

The Vault KV path must contain **at least one key** (the chart uses `dataFrom.extract`). An empty or missing path can leave the `ExternalSecret` **Degraded** until you write data (see [`examples/instances/example/vault-seed.json`](../../examples/instances/example/vault-seed.json)).

Regenerate vendored dependency (if you bump the version in `Chart.yaml`):

```bash
helm dependency update
```

(Helm CLI required.)
