# kube-prometheus-stack (optional — Kind + Grafana)

This addon installs **[kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)** (Prometheus Operator, Prometheus, **Grafana** with default Kubernetes dashboards, kube-state-metrics, node-exporter). It supersedes the repo’s earlier standalone **prometheus-community/prometheus** addon (same OpenCost integration, different Service DNS).

## Layout

- **Namespace:** `monitoring`
- **Helm release name:** `kps` (fixed — OpenCost values assume this name)
- **Prometheus Service (in-cluster):** `kps-kube-prometheus-stack-prometheus` on port **9090**
- **Grafana:** Ingress host **`grafana.127.0.0.1.nip.io`** (same ingress-nginx + Kind port **80** pattern as the tutorial). **`scripts/install.sh`** materializes Argo with a random **`admin`** password and writes it under **`~/.spice-platform/`** (see `grafana-superset-credentials.txt`). Manual Helm using only `values-kind.yaml` still uses **`admin` / `admin`** (lab only).

## Install (before or alongside OpenCost)

OpenCost is configured to query this Prometheus URL (see [`../opencost/values-kind.yaml`](../opencost/values-kind.yaml)):

`http://kps-kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090`

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm upgrade --install kps prometheus-community/kube-prometheus-stack \
  --version 85.2.2 \
  -n monitoring --create-namespace \
  -f gitops/addons/kube-prometheus-stack/values-kind.yaml
kubectl -n monitoring rollout status deploy/kps-kube-prometheus-stack-operator --timeout=300s
kubectl -n monitoring rollout status statefulset/prometheus-kps-kube-prometheus-stack-prometheus --timeout=300s
kubectl -n monitoring rollout status deploy/kps-grafana --timeout=300s
```

Then **restart OpenCost** so allocation queries use the new Prometheus:

```bash
kubectl -n opencost rollout restart deploy/opencost
```

## Verify

```bash
kubectl -n monitoring get svc,pods
curl -sf "http://kps-kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090/-/healthy" \
  --connect-timeout 2 || true   # from a debug pod on the cluster
```

Open Grafana in a browser: **`http://grafana.127.0.0.1.nip.io/`** (Host header to Kind ingress on `127.0.0.1:80`).

## Optional Argo CD Application

See [`application-kube-prometheus-stack.yaml`](./application-kube-prometheus-stack.yaml). Edit `grafana.ingress.hosts` in `spec.source.helm.values` (and mirror in `values-kind.yaml`) if the hostname collides.

The Application sets **`ServerSideApply=true`** so large monitoring CRDs sync without hitting Kubernetes’s **262144-byte** cap on `metadata.annotations` (client-side `kubectl apply` stores the full object in `kubectl.kubernetes.io/last-applied-configuration`, which breaks kube-prometheus-stack CRDs and leaves **`Prometheus`** kinds missing — OpenCost then gets **connection refused** on the Prometheus Service). Requires **Argo CD ≥ 2.5**. If a previous sync left invalid or partial CRDs, delete the affected `CustomResourceDefinition` objects (or the whole `kube-prometheus-stack` Application and related resources in `monitoring`), commit the manifest with SSA, then sync again; after Prometheus is healthy, **`kubectl -n opencost rollout restart deploy/opencost`**.

## Notes

- **Migrating from the old `prometheus-community/prometheus` addon:** `helm uninstall prometheus -n prometheus-system` (and remove its Argo `Application` if you used one) before or after installing **`kps`**, so you do not run two Prometheus servers scraping the same cluster.
- **Persistence:** Prometheus uses `emptyDir` TSDB storage (data is lost when the Prometheus pod is rescheduled). Enable a PVC + `StorageClass` for production.
- **Alertmanager** is disabled in Kind values to save resources; enable in `values-kind.yaml` if you want routing.
- **Control-plane metrics** (scheduler, controller-manager, etcd) are disabled for Kind where those endpoints are not exposed like on managed Kubernetes.
