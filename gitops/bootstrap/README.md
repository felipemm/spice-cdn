# GitOps bootstrap (Kind)

This directory holds **reference Helm values** and manifests used during **day‑0** bootstrap.

Operational changes after bootstrap are driven from the **control plane webapp** (GitHub + Vault + Argo `Application` objects), not by editing these files routinely.

## Order (recommended)

1. **ingress-nginx** — exposes HTTP/HTTPS on Kind `extraPortMappings` (see `hack/kind-config.yaml`).
2. **HashiCorp Vault** — lab-friendly `values-vault.yaml` enables dev-style settings; **not** production-hardened.
3. **external-secrets** — install operator, then create `vault-eso-token`, enable Vault KV v2 at `secret`, and apply `manifests/cluster-secret-store.yaml` (see tutorial order).
4. **argo-cd** — install with `values-argocd.yaml`; configure GitHub repo credentials as a Secret in `argocd` namespace.

See [docs/tutorial.md](../docs/tutorial.md) for exact commands.

## Files

| File | Purpose |
|------|---------|
| `values-ingress-nginx.yaml` | `ingress-nginx` controller for Kind: `NodePort` Service plus **hostPort** 80/443 so host port mappings reach nginx. |
| `values-vault.yaml` | Single-replica Vault for local labs (explicit security caveats in comments). |
| `values-external-secrets.yaml` | External Secrets Operator defaults. |
| `values-argocd.yaml` | Argo CD server settings; UI on **`http://argocd.127.0.0.1.nip.io/`** via nginx Ingress (lab `insecure` mode; prefer control plane `/admin` for day‑2). |
| `manifests/cluster-secret-store.yaml` | Cluster-scoped Vault backend for ESO (`vault-backend`); apply after `vault-eso-token` exists. |
| `manifests/github-repo-secret.example.yaml` | Template for Argo’s `repo` Secret (HTTPS + PAT / token). |

Replace placeholders such as `CHANGE_ME` before applying.
