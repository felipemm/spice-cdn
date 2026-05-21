# OpenCost (optional)

[OpenCost](https://www.opencost.io/) provides cluster cost allocation APIs. When deployed, set on the control-plane Deployment:

- `OPENCOST_BASE_URL` — e.g. `http://opencost.opencost.svc.cluster.local:9003`

The admin **Costs** panel calls OpenCost allocation endpoints (best-effort; API shape varies by version).

## Install (Helm)

```bash
helm repo add opencost https://opencost.github.io/opencost-helm-chart
helm repo update
helm upgrade --install opencost opencost/opencost -n opencost --create-namespace
```

On EKS, follow OpenCost docs to attach a `ServiceAccount` with `AWS_*` permissions for CUR-backed pricing.

## Optional Argo CD Application

See [`application-opencost.yaml`](./application-opencost.yaml) (disabled by default: set `spec.syncPolicy` or apply manually when the cluster should run OpenCost).
