# Example Spice instances

These folders are **validated in CI** (`helm template` per `examples/instances/*/values.yaml`).

Your **live** instance values live in your **GitOps repository** under `instances/*` (same layout), not in this product repository.

## Vault + External Secrets

If `externalSecret.enabled` is true, put at least one string key at the KV path in `values.yaml` (`vaultPath`, e.g. `spice/instances/<name>` on mount `secret`). An empty or missing path often leaves the `ExternalSecret` **Degraded**.

- **Sample payloads (same shape the control plane saves):** [`example/vault-seed.json`](example/vault-seed.json), [`databricks/vault-seed.json`](databricks/vault-seed.json)
- **CLI (Kind / dev Vault):** `kubectl -n vault exec vault-0 -- vault kv put secret/spice/instances/<name> KEY=VALUE ...`
- **Bootstrap:** `scripts/install.sh` seeds every `instances/<name>/vault-seed.json` in the materialized GitOps tree after Vault KV is enabled.
