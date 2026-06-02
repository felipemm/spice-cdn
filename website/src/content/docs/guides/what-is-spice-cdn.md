---
title: What is Spice? Database CDN explained
description: Plain-language overview of Spice.ai, the database CDN concept, and what you build with this platform.
---

This guide explains **three ideas** that are easy to mix up: **Spice.ai** (the data runtime), **database CDN** (what Spice does with your data), and **Spice CDN** (this Kubernetes/GitOps platform).

## 1. What is Spice.ai?

[Spice.ai](https://spiceai.org) is an open-source **data and AI runtime**. It sits between your applications and your databases, lakes, and APIs — not as a replacement for PostgreSQL or Snowflake, but as a **fast, unified query layer** on top of them.

You configure it in a file called **`spicepod.yaml`**:

| Capability | In plain terms |
|------------|----------------|
| **Federated SQL** | Ask questions across many sources (Postgres, S3, Databricks, Kafka, …) with one SQL engine |
| **Data acceleration** | Keep a **local copy** of “hot” tables so reads are fast and cheap |
| **Search** | Vector and keyword search over your data |
| **AI** | Models, embeddings, and text-to-SQL for assistants and apps |

Typical local workflow:

```bash
spice init my_app
spice run
spice sql
```

Apps and BI tools connect to Spice over **HTTP/SQL** (often port `8090`). Spice handles talking to upstream systems and keeping local data fresh.

## 2. What is a “database CDN”?

A **traditional CDN** (Cloudflare, Akamai) puts **static files** (images, JS, CSS) **close to users** so pages load faster.

A **database CDN** is Spice’s name for doing something similar with **live business data**:

> Put a **fresh, local copy of the tables your app cares about** next to the app (or next to the query path), and serve reads from that copy instead of hitting the remote database on every request.

```text
Without database CDN          With Spice (database CDN)
────────────────────          ─────────────────────────
App ──every click──► Remote   App ──fast read──► Spice ──refresh──► Remote
     database                      (local copy)
```

### How acceleration works

In `spicepod.yaml` you declare a dataset and turn on **acceleration**:

```yaml
datasets:
  - from: postgres:crm_db.user_sessions
    name: user_sessions
    acceleration:
      enabled: true
      engine: duckdb
      mode: file
      refresh_mode: changes
      refresh_check_interval: 1m
```

Spice will:

1. **Connect** to the source (connector).
2. **Copy** the dataset into a local engine (DuckDB, Arrow, Cayenne, SQLite, …).
3. **Refresh** it on a schedule or via change capture (CDC).
4. **Answer queries** from the local copy — milliseconds instead of cross-network round trips.

This is **not** “cache this one SQL result in Redis.” It is **materializing whole datasets** (or views) with defined refresh rules — closer to a **smart replica** than a generic cache.

### Why teams use it

| Benefit | What it means for you |
|---------|------------------------|
| **Speed** | Dashboards and APIs feel snappy; less load on the source DB |
| **Resilience** | If the cloud DB blips, local data can still serve reads |
| **Scale** | Many concurrent readers hit Spice locally instead of one shared remote DB |
| **Federation** | Join accelerated tables with live federated sources in one SQL query |

Good fits: CRM sessions, product catalogs, operational metrics, BI (Superset, Tableau) over a materialized layer, AI apps that need fast SQL over fresh data.

Learn more in Spice’s docs: [Database CDN use case](https://spiceai.org/docs/use-cases/data/database-cdn) and [Data acceleration](https://spiceai.org/docs/features/data-acceleration).

## 3. What is “Spice CDN” (this project)?

**Important:** the name overloads “CDN.”

| Term | Meaning |
|------|---------|
| **Database CDN** | Spice.ai **product concept** — accelerate database data near apps |
| **Spice CDN** (this repo) | **Platform packaging** — install, version, and operate Spice on Kubernetes with GitOps |

**Spice CDN is not** a network CDN and **not** the same thing as “database CDN” alone. It is a **GitOps distribution platform** for running Spice.ai on Kubernetes:

- **`install.sh`** and release tarballs bootstrap a lab or production-shaped cluster
- A **control plane UI** creates Spice instances by writing `instances/*/values.yaml` in **your** GitOps repo
- **Argo CD** deploys each instance from that repo (Helm chart wrapping upstream `spiceai`)
- **Vault + External Secrets** keep credentials out of Git

### What you are actually creating

When you use this project end to end, you end up with:

1. **A GitOps repository** (yours) — the source of truth Argo CD syncs
2. **A Kubernetes cluster** with ingress, secrets, and Argo CD
3. **One or more Spice runtimes** — each instance is a deployed Spice.ai with its own `spicepod`, connectors, and acceleration config
4. **Optional ops add-ons** — Prometheus/Grafana, OpenCost, Superset SQL Lab hooks

Your **applications** talk to each Spice instance’s API. Each instance can act as a **database CDN** for the datasets you configure — while **this platform** handles how that runtime is **installed, upgraded, and governed**.

```text
You operate (Spice CDN platform)          Your apps consume (Spice.ai)
────────────────────────────────          ────────────────────────────
install.sh → GitOps repo → Argo CD   →    SQL / HTTP / search / AI
         → control plane UI               over accelerated + federated data
         → Vault secrets
```

## 4. How the pieces fit together

| Layer | Role | Analogy |
|-------|------|---------|
| **Source systems** | Postgres, S3, Databricks, … | The “origin server” |
| **Spice.ai runtime** | Federate + accelerate data; serve queries | A **database CDN** — copies hot data nearby |
| **Spice CDN platform** | K8s + GitOps + installer + control plane | The **shipping & ops** layer — like a product CDN delivers static bits, this delivers repeatable Spice deployments |

## 5. Two repositories (reminder)

| Repository | You store here |
|------------|----------------|
| **Product** (`spice-cdn` on GitHub) | Charts, installer, control plane source, docs — upgraded via releases |
| **GitOps** (your repo) | `instances/*`, Argo apps, pinned chart copies — **your** instance config and policies |

Argo CD never syncs directly from the product repo for runtime config. You **materialize** a tree from a release, **push** to GitOps, and **manage instances** from the control plane.

## Architecture diagram

A visual overview (technical layers + plain-English callouts) lives in the repo:

[`docs/diagrams/spice-cdn-architecture.excalidraw`](https://github.com/felipemm/spice-cdn/blob/main/docs/diagrams/spice-cdn-architecture.excalidraw) — open in [Excalidraw](https://excalidraw.com) or the VS Code Excalidraw extension.

Regenerate after edits: `node scripts/generate-architecture-diagram.mjs`

## Next steps

- [User guide](./user-guide) — install and day-2 operations
- [Product vs GitOps](./architecture) — file layout and APIs
- [Install reference](./install) — flags and environment variables
