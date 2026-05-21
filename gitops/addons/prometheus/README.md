# Prometheus for Kind (OpenCost prerequisite)

[OpenCost](https://www.opencost.io/) expects an in-cluster Prometheus by default at:

- **Namespace:** `prometheus-system`
- **Service:** `prometheus-server`
- **Port:** `80` → Prometheus UI/target port `9090`

The [`prometheus-community/prometheus`](https://github.com/prometheus-community/helm-charts) chart normally creates a Service named `<release>-prometheus-server`. This file sets **`server.fullnameOverride: prometheus-server`** so the DNS name matches OpenCost’s defaults (`opencost.prometheus.internal` in chart 1.33.1).

## Install (before or alongside OpenCost)

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm upgrade --install prometheus prometheus-community/prometheus \
  -n prometheus-system --create-namespace \
  -f gitops/addons/prometheus/values-kind.yaml
```

Wait until the server workload is Ready:

```bash
kubectl -n prometheus-system rollout status deploy/prometheus-server --timeout=300s
```

Then **restart OpenCost** (or wait for its next scrape) so allocation queries succeed:

```bash
kubectl -n opencost rollout restart deploy/opencost
```

## Kind notes

- **Persistence** is disabled (`emptyDir`) so you do not need a default `StorageClass`.
- **Alertmanager** and **pushgateway** are off to keep the footprint small.
- **kube-state-metrics** stays on (OpenCost uses metrics such as `kube_pod_container_resource_requests`).

## Verify

```bash
kubectl -n prometheus-system get svc prometheus-server
curl -sf "http://prometheus-server.prometheus-system.svc.cluster.local:80/-/healthy" \
  --connect-timeout 2 || true   # from a debug pod; from laptop use port-forward if needed
```
