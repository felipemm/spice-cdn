# GitOps bootstrap (Kind)

This directory holds **reference Helm values** and manifests used during **day‑0** bootstrap.

Operational changes after bootstrap are driven from the **control plane webapp** (GitHub + Vault + Argo `Application` objects), not by editing these files routinely.

## Order (recommended)

1. **ingress-nginx** — exposes HTTP/HTTPS on Kind `extraPortMappings` (see `hack/kind-config.yaml`).
2. **Valkey** — standalone in-cluster cache (Redis protocol); `scripts/install.sh` installs it right after ingress. Gitea uses it for session/cache/queue; other apps can use `valkey-primary.valkey.svc.cluster.local:6379` (password under `STATE_DIR` on the host).
3. **HashiCorp Vault** — lab-friendly `values-vault.yaml` enables dev-style settings; **not** production-hardened.
4. **external-secrets** — install operator, then create `vault-eso-token`, enable Vault KV v2 at `secret`, and apply `manifests/cluster-secret-store.yaml` (see tutorial order).
5. **argo-cd** — install with `values-argocd.yaml`; configure GitHub repo credentials as a Secret in `argocd` namespace.

See [docs/tutorial.md](../docs/tutorial.md) for exact commands.

## Files

| File | Purpose |
|------|---------|
| `values-gitea.yaml` | Gitea for the local-only lab (SQLite + Redis/Valkey; **Actions** + **packages** enabled so `.gitea/workflows` and the container registry match GitHub CI). |
| `values-gitea-actions.yaml` | [helm-actions](https://gitea.com/gitea/helm-actions): in-cluster **act_runner** + Docker-in-Docker; installed by `scripts/install.sh` after Gitea (namespace `gitea-actions` by default). |
| `values-valkey.yaml` | Standalone Bitnami Valkey (no persistence) for Kind; password file created by `scripts/install.sh`. |
| `values-ingress-nginx.yaml` | `ingress-nginx` controller for Kind: `NodePort` Service plus **hostPort** 80/443 so host port mappings reach nginx. |
| `values-vault.yaml` | Single-replica Vault for local labs (explicit security caveats in comments). |
| `values-external-secrets.yaml` | External Secrets Operator defaults. |
| `values-argocd.yaml` | Argo CD server settings; UI on **`http://argocd.127.0.0.1.nip.io/`** via nginx Ingress (lab `insecure` mode; prefer control plane `/admin` for day‑2). |
| `manifests/cluster-secret-store.yaml` | Cluster-scoped Vault backend for ESO (`vault-backend`); apply after `vault-eso-token` exists. |
| `manifests/github-repo-secret.example.yaml` | Template for Argo’s `repo` Secret (HTTPS + PAT / token). |

Replace placeholders such as `CHANGE_ME` before applying.

## Gitea Actions (self-hosted forge)

1. **Chart defaults** — `values-gitea.yaml` sets `gitea.config.actions.ENABLED` and `packages.ENABLED`.
2. **Runner** — For the Kind lab, `scripts/install.sh` installs the official **`gitea-charts/actions`** chart (see `values-gitea-actions.yaml`), creates the registration token via the admin API, and waits for StatefulSet **`${SPICE_GITEA_ACTIONS_RELEASE:-gitea-actions}-runner`**. Set **`SPICE_SKIP_GITEA_ACTIONS_RUNNER=1`** to skip. For a standalone Gitea host, register runners manually or reuse the same Helm values with your own Secret.
3. **Workflows** — CI definitions live in [`.gitea/workflows/`](../../.gitea/workflows/) at the repo root; `scripts/install.sh` also copies that tree into the materialized GitOps bundle so the in-cluster Gitea lab gets the same pipelines after the first push.

GitHub equivalents remain under [`.github/workflows/`](../../.github/workflows/).
