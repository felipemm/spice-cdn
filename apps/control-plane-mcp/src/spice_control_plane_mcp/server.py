"""FastMCP Streamable HTTP server — proxies the in-cluster Next.js control plane API."""

from __future__ import annotations

import json
import os
from typing import Any
from urllib.parse import quote

import httpx
from fastmcp import FastMCP
from starlette.middleware import Middleware
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import JSONResponse, Response

mcp = FastMCP(
    "Spice Control Plane",
    instructions=(
        "Manage Spice.ai GitOps instances through the Next.js control plane: list, create, "
        "read values.yaml, delete, inspect Argo CD Application status, and register Superset "
        "SQL Lab databases (Flight SQL) after deploy is ready. Creating an instance commits to "
        "Git; Argo CD reconciles the cluster."
    ),
)


def _base_url() -> str:
    return os.environ.get("CONTROL_PLANE_URL", "http://127.0.0.1:3000").rstrip("/")


def _upstream_headers() -> dict[str, str]:
    headers: dict[str, str] = {}
    key = (
        os.environ.get("CONTROL_PLANE_API_KEY")
        or os.environ.get("CONTROL_PLANE_ADMIN_KEY")
        or os.environ.get("ADMIN_API_KEY")
    )
    if key:
        headers["x-admin-key"] = key.strip()
    return headers


def _fetch(method: str, path: str, json_body: Any | None = None) -> dict[str, Any]:
    url = f"{_base_url()}{path if path.startswith('/') else '/' + path}"
    with httpx.Client(timeout=120.0) as client:
        r = client.request(method, url, headers=_upstream_headers(), json=json_body)
        text = r.text
        try:
            body: Any = json.loads(text) if text else None
        except json.JSONDecodeError:
            body = {"raw": text}
        return {"status_code": r.status_code, "body": body}


def _json_tool(data: dict[str, Any]) -> str:
    return json.dumps(data, indent=2)


@mcp.custom_route("/healthz", methods=["GET"])
async def healthz(_request: Request) -> Response:
    return JSONResponse({"ok": True})


class _OptionalBearerAuth(BaseHTTPMiddleware):
    """If MCP_SERVER_API_KEY is set, require Authorization: Bearer <key> (except /healthz)."""

    async def dispatch(self, request: Request, call_next):  # type: ignore[no-untyped-def]
        path = request.url.path
        if path == "/healthz" or path == "/favicon.ico":
            return await call_next(request)
        expected = os.environ.get("MCP_SERVER_API_KEY", "").strip()
        if not expected:
            return await call_next(request)
        auth = (request.headers.get("authorization") or "").strip()
        if auth != f"Bearer {expected}":
            return JSONResponse({"detail": "Unauthorized"}, status_code=401)
        return await call_next(request)


@mcp.tool()
def control_plane_health() -> str:
    """GET /api/health — verify the Next.js control plane is reachable from this pod."""
    return _json_tool(_fetch("GET", "/api/health"))


@mcp.tool()
def list_spice_instances() -> str:
    """List Spice instances (name + public URL when ingress.host is set). GET /api/instances."""
    return _json_tool(_fetch("GET", "/api/instances"))


@mcp.tool()
def deploy_spice_instance(name: str, owner_layer_slug: str) -> str:
    """
    Create a Spice instance: POST /api/instances (Git commit; Argo CD deploys).

    Args:
        name: Instance name (lowercase DNS label). Argo app name is spice-<name>.
        owner_layer_slug: Cost / ownership slug (validated by the control plane).
    """
    body = {
        "name": name.strip(),
        "ownerLayerSlug": owner_layer_slug.strip(),
    }
    return _json_tool(_fetch("POST", "/api/instances", body))


@mcp.tool()
def get_spice_instance(name: str) -> str:
    """GET /api/instances/<name> — values.yaml content and Git sha."""
    seg = quote(name.strip(), safe="")
    return _json_tool(_fetch("GET", f"/api/instances/{seg}"))


@mcp.tool()
def delete_spice_instance(name: str) -> str:
    """DELETE /api/instances/<name> — remove instance from Git (destructive)."""
    seg = quote(name.strip(), safe="")
    return _json_tool(_fetch("DELETE", f"/api/instances/{seg}"))


@mcp.tool()
def get_spice_instance_argo(name: str) -> str:
    """GET /api/instances/<name>/argo — Argo CD Application for spice-<name>."""
    seg = quote(name.strip(), safe="")
    return _json_tool(_fetch("GET", f"/api/instances/{seg}/argo"))


@mcp.tool()
def get_spice_instance_superset_status(name: str) -> str:
    """GET /api/instances/<name>/superset — Argo readiness + Superset database registration status."""
    seg = quote(name.strip(), safe="")
    return _json_tool(_fetch("GET", f"/api/instances/{seg}/superset"))


@mcp.tool()
def register_spice_instance_superset(name: str, wait_for_ready: bool = True) -> str:
    """
    POST /api/instances/<name>/superset — create Superset SQL Lab database for this instance.

    Args:
        name: Instance name.
        wait_for_ready: When true (default), wait for Argo Synced+Healthy before registering.
    """
    seg = quote(name.strip(), safe="")
    return _json_tool(
        _fetch("POST", f"/api/instances/{seg}/superset", {"waitForReady": wait_for_ready}),
    )


def main() -> None:
    port = int(os.environ.get("PORT", "8000"))
    host = os.environ.get("HOST", "0.0.0.0")
    middleware: list[Middleware] = [Middleware(_OptionalBearerAuth)]
    mcp.run(
        transport="http",
        host=host,
        port=port,
        middleware=middleware,
        show_banner=os.environ.get("FASTMCP_SHOW_BANNER", "false").lower() in ("1", "true", "yes"),
    )


if __name__ == "__main__":
    main()
