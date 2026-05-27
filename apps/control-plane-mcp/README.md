# Control plane MCP (FastMCP, remote HTTP)

This directory builds a **[FastMCP](https://github.com/jlowin/fastmcp)** server that exposes the Next.js **control plane REST API** as MCP tools over **Streamable HTTP** (default FastMCP path: **`/mcp`**).

It is intended to run **inside the cluster** as a **sidecar** in the `control-plane` Helm chart: same pod network namespace as the web app, calling `CONTROL_PLANE_URL=http://127.0.0.1:3000`.

## Tools

| Tool | Upstream |
|------|----------|
| `control_plane_health` | `GET /api/health` |
| `list_spice_instances` | `GET /api/instances` |
| `deploy_spice_instance` | `POST /api/instances` |
| `get_spice_instance` | `GET /api/instances/:name` |
| `delete_spice_instance` | `DELETE /api/instances/:name` |
| `get_spice_instance_argo` | `GET /api/instances/:name/argo` |
| `get_spice_instance_superset_status` | `GET /api/instances/:name/superset` |
| `register_spice_instance_superset` | `POST /api/instances/:name/superset` |

## Environment

| Variable | Default | Description |
|----------|---------|-------------|
| `HOST` | `0.0.0.0` | Bind address |
| `PORT` | `8000` | Listen port |
| `CONTROL_PLANE_URL` | `http://127.0.0.1:3000` | Next.js base URL (loopback sidecar). |
| `CONTROL_PLANE_API_KEY` / `ADMIN_API_KEY` | (empty) | Optional `x-admin-key` to the Next app (admin routes / future use). |
| `MCP_SERVER_API_KEY` | (empty) | If set, clients must send `Authorization: Bearer <value>` to reach MCP. |
| `FASTMCP_SHOW_BANNER` | `false` | Set `true` for local dev logging banner. |

## Local run (dev)

From **`apps/control-plane-mcp/`**:

```bash
cd apps/control-plane-mcp
python3 -m venv .venv && source .venv/bin/activate
pip install -e .
export CONTROL_PLANE_URL=http://127.0.0.1:3000
python -m spice_control_plane_mcp
```

MCP endpoint: `http://127.0.0.1:8000/mcp` (Streamable HTTP).

## Kubernetes (Helm)

In `deploy/helm/control-plane/values.yaml`:

1. Ensure the **MCP image** exists in GHCR (push to `main` touching this folder runs [`.github/workflows/control-plane-mcp-image.yml`](../../.github/workflows/control-plane-mcp-image.yml), which bumps `mcp.image.repository` / `mcp.image.tag`). The chart defaults **`mcp.enabled: true`**; set **`mcp.enabled: false`** to disable the sidecar.
2. Optional: set **`mcp.auth.serverApiKeySecretName`** / **`serverApiKeySecretKey`** so the sidecar receives **`MCP_SERVER_API_KEY`** (clients then use the same value as `Authorization: Bearer …`).

With ingress host `control.example.com`, the remote MCP URL is:

`https://control.example.com/mcp`

### Ingress / proxy notes

Streamable HTTP may use long-lived streams. For **nginx** ingress, consider annotations such as longer read timeouts and (if you see stalled streams) disabling buffering for this location. Example (tune for your environment):

```yaml
ingress:
  annotations:
    nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
```

## Cursor / Claude Desktop (remote)

Point the client at the **HTTPS URL** of the MCP endpoint, for example:

```json
{
  "mcpServers": {
    "spice-control-plane": {
      "url": "https://control-plane.127.0.0.1.nip.io/mcp",
      "headers": {
        "Authorization": "Bearer YOUR_MCP_SERVER_API_KEY"
      }
    }
  }
}
```

Omit `headers` if `MCP_SERVER_API_KEY` is not configured on the server.

Exact client schema depends on the product version; some UIs use `type: "http"` plus `url`.

## Docker

From the **repository root**:

```bash
docker build -t control-plane-mcp:dev -f apps/control-plane-mcp/Dockerfile apps/control-plane-mcp
docker run --rm -p 8000:8000 -e CONTROL_PLANE_URL=http://host.docker.internal:3000 control-plane-mcp:dev
```
