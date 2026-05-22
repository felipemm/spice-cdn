# OpenCost (optional)

[OpenCost](https://www.opencost.io/) provides cluster cost allocation APIs. When deployed, set on the control-plane Deployment:

- **`OPENCOST_BASE_URL`** — in-cluster API (port **9003**), e.g. `http://opencost.opencost.svc.cluster.local:9003` when the Helm release name is `opencost`.

The admin **Costs** panel calls OpenCost allocation endpoints (best-effort; API shape varies by version).

## Prometheus is required (default in-cluster URL)

With **`opencost.prometheus.internal.enabled: true`** (see [`values-kind.yaml`](./values-kind.yaml)), OpenCost queries **kube-prometheus-stack** Prometheus:

`http://kps-kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090`

If that Service does not exist, logs show **`no such host`** / **`Prometheus communication error`** and allocation data will be empty or degraded.

**Fix on Kind:** install **[kube-prometheus-stack](../kube-prometheus-stack/README.md)** **first** (Helm release name **`kps`**, namespace **`monitoring`** — matches `serviceName` / `namespaceName` / `port` in `values-kind.yaml`). Then restart OpenCost:

```bash
kubectl -n opencost rollout restart deploy/opencost
```

Some queries reference **Kubecost-specific** metrics (for example `kubecost_pod_network_egress_bytes_total`); without Kubecost exporters those series may be missing and you can see additional warnings. Core allocation still works once Prometheus serves standard kubelet / cAdvisor / kube-state-metrics scrapes.

## Kind: expose the UI without port-forward

The OpenCost **UI** listens on **9090** inside the pod; outside the cluster use **ingress-nginx** (same as the tutorial) so you reach it on **port 80**:

1. Ensure ingress-nginx is installed with host port 80 (see `docs/tutorial.md`).
2. Install or upgrade OpenCost with [`values-kind.yaml`](./values-kind.yaml) (enables `opencost.ui.ingress` with `ingressClassName: nginx` and `opencost.127.0.0.1.nip.io`):

```bash
helm repo add opencost https://opencost.github.io/opencost-helm-chart
helm repo update
helm upgrade --install opencost opencost/opencost -n opencost --create-namespace \
  --version 1.33.1 -f gitops/addons/opencost/values-kind.yaml
```

3. Open **`http://opencost.127.0.0.1.nip.io/`** in your browser (Host header resolves to Kind’s ingress on `127.0.0.1:80`).
4. Change the hostname in `values-kind.yaml` if it collides with another ingress.

**Note:** Chart **1.33.1** ships an ingress only for the **UI** (`opencost.ui.ingress`). The **allocation API** (9003) stays on the cluster `Service` for the control plane to call; you do not need to expose 9003 on the ingress for normal operation.

## EKS / other clusters

- Set `opencost.ui.ingress.hosts[0].host` to your real DNS name and TLS as needed (`opencost.ui.ingress.tls`).
- On EKS, follow OpenCost docs to attach a `ServiceAccount` with `AWS_*` permissions for CUR-backed pricing.

## Optional Argo CD Application

See [`application-opencost.yaml`](./application-opencost.yaml) (sync to create namespace `opencost` and the Ingress). Edit the host in `spec.source.helm.values` to match your environment.
