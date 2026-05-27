# Control plane Helm chart

## Superset integration (Vault)

1. Enable KV v2 and ClusterSecretStore `vault-backend` (platform bootstrap).
2. Seed Vault:

```bash
kubectl -n vault exec vault-0 -- vault kv put secret/spice/control-plane \
  SUPERSET_URL="http://superset.superset.svc.cluster.local:8088" \
  SUPERSET_USERNAME="admin" \
  SUPERSET_PASSWORD="<superset-admin-password>"
```

See [`vault-seed.example.json`](vault-seed.example.json) for the expected keys.

3. In `values.yaml`:

```yaml
externalSecret:
  enabled: true
  syncSuperset: true
  vaultPath: spice/control-plane
  targetSecretName: control-plane-env
```

4. Sync the Argo CD application; confirm `ExternalSecret/control-plane-vault` is **Ready** and Secret `control-plane-env` exists in the `control-plane` namespace.

The Kind installer (`scripts/install.sh`) performs steps 2–3 automatically when the Superset addon is materialized.
