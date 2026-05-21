# GitOps bootstrap (Kind)

This directory holds **reference Helm values** and manifests used during **day‑0** bootstrap.

Operational changes after bootstrap are driven from the **control plane webapp** (GitHub + Vault + Argo `Application` objects), not by editing these files routinely.

## Order (recommended)

1. **ingress-nginx** — exposes HTTP/HTTPS on Kind `extraPortMappings` (see `hack/kind-config.yaml`).
2. **HashiCorp Vault** — lab-friendly `values-vault.yaml` enables dev-style settings; **not** production-hardened.
3. **external-secrets** — install operator, then apply `manifests/cluster-secret-store.yaml` after Vault token/bootstrap (see tutorial).
4. **argo-cd** — install with `values-argocd.yaml`; configure GitHub repo credentials as a Secret in `argocd` namespace.

See [docs/tutorial.md](../docs/tutorial.md) for exact commands.

## Files

| File | Purpose |
|------|---------|
| `values-ingress-nginx.yaml` | `ingress-nginx` controller tuned for Kind (`NodePort` / hostPort pattern). |
| `values-vault.yaml` | Single-replica Vault for local labs (explicit security caveats in comments). |
| `values-external-secrets.yaml` | External Secrets Operator defaults. |
| `values-argocd.yaml` | Argo CD server settings; optional UI exposure (prefer control plane `/admin`). |
| `manifests/github-repo-secret.example.yaml` | Template for Argo’s `repo` Secret (HTTPS + PAT / token). |

Replace placeholders such as `CHANGE_ME` before applying.
