# Apache Superset (optional)

[Apache Superset](https://superset.apache.org/) is an open-source BI and data exploration UI.

This addon uses the official **[Helm chart](https://github.com/apache/superset/tree/master/helm/superset)** (`https://apache.github.io/superset`, chart **superset**). It deploys Superset with **bundled PostgreSQL and Redis** (Bitnami subcharts), which suits the Kind lab; for production, point `supersetNode.connections` at managed databases and set `postgresql.enabled` / `redis.enabled` to `false`.

## Kind: UI on port 80 (ingress-nginx)

1. Ensure **ingress-nginx** is installed (same as the rest of the platform bootstrap).
2. Install or upgrade with [`values-kind.yaml`](./values-kind.yaml) (ingress host **`superset.127.0.0.1.nip.io`**, bundled PostgreSQL with an **8Gi PVC** for metadata).
3. After the **init** Job completes, open **`http://superset.127.0.0.1.nip.io/`**.
4. Admin credentials: **`scripts/install.sh`** patches the Argo Application with **`init.adminUser`** and writes **`~/.spice-platform/grafana-superset-credentials.txt`** (random password for user **`admin`**). Manual Helm with only [`values-kind.yaml`](./values-kind.yaml) follows the chart default (**`admin` / `admin`**) until you override **`init.adminUser`**.

### Metadata persistence (Kind lab)

SQL Lab databases, dashboards, charts, and other Superset settings live in the **bundled PostgreSQL** subchart. [`values-kind.yaml`](./values-kind.yaml) enables **`postgresql.primary.persistence`** (8Gi PVC, cluster default `StorageClass`, usually **`standard`** on Kind) so metadata survives pod restarts and routine Argo syncs while the PVC remains.

- **First upgrade from an older lab without a PVC:** Kubernetes cannot add `volumeClaimTemplates` to an existing `superset-postgresql` StatefulSet. Argo sync will fail with *Forbidden: updates to statefulset spec … are forbidden* until you delete the old StatefulSet once (data on ephemeral storage is already lost):

  ```bash
  kubectl -n superset delete statefulset superset-postgresql --wait=true
  kubectl -n argocd annotate application superset argocd.argoproj.io/refresh=hard --overwrite
  # Or: argocd app sync superset
  kubectl -n superset get pvc   # expect data-superset-postgresql-0 Bound
  ```

  Helm/Argo then recreates Postgres with an **8Gi** PVC (empty DB). Re-run Superset **init** if needed and use **Create Superset connection** on instance pages for Spice SQL Lab DBs. After that, settings persist across pod recreates.
- **`SUPERSET_SECRET_KEY`:** must stay stable once data exists. The Kind Argo template uses a placeholder; **`install.sh`** replaces it with a random hex value in **`~/.spice-platform/superset-lab.secret-key`** and patches the materialized app. Do not change this key after the database has data (encrypted connection fields become unreadable). **Replace with your own secret management in production.**
- **Argo CD `prune: true`:** deleting the entire **`superset`** Application can remove Helm-managed PVCs. Avoid pruning the app if you need to retain data, or back up PostgreSQL first.
- **`kind delete cluster`:** destroys node disks; PVC data is lost (expected for local labs).
- **Redis** (bundled, no PVC): Celery/cache only; metadata is in Postgres.

## Spice + Flight SQL driver

The chart **`bootstrapScript`** installs into **`/app/.venv/lib/python3.10/site-packages`** using **`/usr/local/bin/pip install --target`**. The lean Superset 5 image has **no `pip` module inside the venv** (`python -m pip` fails). Plain **`pip`** without `--target` installs elsewhere, so Gunicorn still crashes with `No module named 'psycopg2'`.

1. **`psycopg2-binary`** — metadata PostgreSQL (required; bootstrap exits if import fails).
2. **`flightsql-dbapi==0.2.2`** with **`--no-deps`** — avoids pulling **SQLAlchemy 1.4**, which breaks Superset 5. Do not pin `flightsql-dbapi>=0.4.x` (those releases are not on PyPI).

After changing the script, **restart** Superset pods so bootstrap runs again (marker file is `/tmp/.spice_superset_lab_pip_deps_v6` per container; bootstrap re-runs if `flightsql.sqlalchemy` is not importable). `flightsql-dbapi` is installed with `--no-deps`; the bootstrap also installs **`protobuf`** and **`google-auth`** (protobuf alone can break Superset’s `google.auth` imports) plus `sitecustomize.py` so Gunicorn workers register the `datafusion+flightsql` dialect for API connection tests.

## Control plane: auto-create a Superset “database” per instance

When the control plane **`POST /api/instances`** creates a new instance, it can register a matching Superset connection (same Flight SQL URI the UI would use manually).

1. Deploy Superset (this addon) in-cluster.
2. **Recommended (Vault + ESO):** seed KV at **`spice/control-plane`** with keys **`SUPERSET_URL`**, **`SUPERSET_USERNAME`**, **`SUPERSET_PASSWORD`** (see `deploy/helm/control-plane/vault-seed.example.json`). Enable in Helm:
   - **`externalSecret.enabled: true`**
   - **`externalSecret.syncSuperset: true`**
   - **`externalSecret.vaultPath: spice/control-plane`**
   - **`externalSecret.targetSecretName: control-plane-env`**

   **`scripts/install.sh`** seeds this path and patches the materialized chart for the Kind lab.

3. **Alternative (plain Kubernetes Secret):** set **`env.supersetUrl`**, **`env.supersetUsername`**, and **`secrets.supersetPasswordSecretName`** on the control-plane Deployment.

4. **`SPICE_NAMESPACE`** must match where instance releases run (default **`spice-instances`**).

The SQL Lab database display name is **`Spice (<instance>)`**, with URI **`datafusion+flightsql://<instance>-spiceai.<namespace>.svc.cluster.local:50051?insecure=true`**.

Deleting an instance via **`DELETE /api/instances/:name`** removes that Superset database when the same env/secret are configured.

## Optional Argo CD Application

[`application-superset.yaml`](./application-superset.yaml) is copied into the materialized GitOps repo as `apps/application-superset.yaml` so the root `platform-gitops` Application deploys it. Edit the ingress host or chart `targetRevision` as needed.
