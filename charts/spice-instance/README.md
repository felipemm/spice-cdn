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

## Arrow Flight SQL (gRPC via Ingress)

The upstream chart listens for Arrow Flight SQL on **`0.0.0.0:50051`** on the workload `Service` (`<helm-release>-spiceai`). With **`ingress.flightSQL.enabled: true`** (default), this chart renders a second Ingress (`*-flight`) with `nginx.ingress.kubernetes.io/backend-protocol: GRPC`.

**Do not reuse `ingress.host` for Flight and HTTP:** both Ingresses would use **`path: /`**; nginx-ingress merges them and gRPC calls can be sent to the **HTTP** backend on port **8090**, which returns **404**.

Instead, Flight SQL uses a **dedicated hostname**:

- If **`ingress.flightSQL.host`** is set, that value is used.
- If empty, it defaults to **`<first-label>-flight.<rest>`** derived from **`ingress.host`**.  
  Example: `spice-demo.127.0.0.1.nip.io` → **`spice-demo-flight.127.0.0.1.nip.io`** (still resolves to the same IP in nip.io).

**In-cluster:** `grpc://<release>-spiceai.<namespace>.svc.cluster.local:50051` (or `datafusion+flightsql://…?insecure=true` in Superset).

**Through ingress (Kind lab),** for HTTP host `spice-demo.127.0.0.1.nip.io`:

- HTTP API: `http://spice-demo.127.0.0.1.nip.io/` → port **8090**
- Flight SQL: `grpc://spice-demo-flight.127.0.0.1.nip.io` (port **80** implied; use **`grpcs://`** when **`ingress.tls`** is enabled)

### DuckDB and Flight SQL

**Do not use the DuckDB `airport` community extension** (`TYPE AIRPORT`) against Spice. Airport speaks the [Airport catalog protocol](https://airport.query.farm/server_actions.html) (custom Flight `DoAction` types such as `create_transaction`, `list_schemas`, `endpoints`). Spice exposes **standard Apache Arrow Flight SQL** only, so those actions are unknown and you get errors like **`Unknown action type`**.

Use the **[`adbc_scanner`](https://github.com/Query-farm/adbc_scanner)** community extension with the **`flightsql`** ADBC driver instead (same wire protocol Spice implements):

```sql
INSTALL adbc_scanner FROM community;
LOAD adbc_scanner;

ATTACH 'grpc://spice-demo-flight.127.0.0.1.nip.io:80' AS spice (
  TYPE adbc,
  driver 'flightsql'
);
-- Then query remote catalogs/tables per adbc_scanner docs (read-only attach in many setups).
```

**macOS: `driver 'flightsql'` needs a real ADBC driver on disk.** `adbc_scanner` resolves that short name via [driver manifests](https://arrow.apache.org/adbc/20/format/driver_manifests.html) in a few search paths (e.g. `~/Library/Application Support/ADBC/Drivers`). If nothing is installed, you get **`Could not load flightsql`** / **`dlopen` failed**.

1. **Recommended:** install [Columnar `dbc`](https://columnar.tech/dbc/) and the Flight SQL driver (creates `flightsql.toml` + `libadbc_driver_flightsql*.dylib` under `~/Library/Application Support/ADBC/Drivers`):

   ```bash
   curl -LsSf https://dbc.columnar.tech/install.sh | sh
   dbc install flightsql
   ```

   Then **fully quit and reopen** the DuckDB app (or terminal session) so the driver directory is visible, and run `LOAD adbc_scanner` + `ATTACH` again.

2. **Optional:** point the manager at a folder explicitly:

   ```bash
   export ADBC_DRIVER_PATH="$HOME/Library/Application Support/ADBC/Drivers"
   ```

   (Use a **colon-separated** list if you pass multiple directories.)

3. **Without `dbc`:** download **`libadbc_driver_flightsql`** for your CPU from [Apache Arrow ADBC releases](https://github.com/apache/arrow-adbc/releases), put it in a directory, and either add that directory to **`ADBC_DRIVER_PATH`** or pass the **absolute path** to the `.dylib` in `driver` instead of `'flightsql'`:

   ```sql
   ATTACH 'grpc://spice-demo-flight.127.0.0.1.nip.io:80' AS spice (
     TYPE adbc,
     driver '/full/path/to/libadbc_driver_flightsql.dylib'
   );
   ```

Other stacks: **ADBC Flight SQL** (Python/Java/Go), **`flightsql-dbapi`** / JDBC Flight SQL, **Apache Arrow** Flight SQL clients, or in-cluster **Superset** with `datafusion+flightsql://…` (see repo docs).

Disable external Flight SQL with **`ingress.flightSQL.enabled: false`**.

## Local access without Ingress (port-forward)

The upstream chart exposes **8090** (HTTP), **9090** (metrics), and **50051** (Arrow Flight) on the workload `Service` (`<helm-release>-spiceai`). HTTP is also available via Ingress (above). To reach **8090** or **50051** from your laptop without ingress, use `kubectl port-forward` against that Service:

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
