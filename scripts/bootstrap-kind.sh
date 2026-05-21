#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "See docs/tutorial.md for full bootstrap. This script only recreates Kind (control-plane image is pulled from GHCR via Argo)."
make kind-delete || true
make kind-create
echo "Done. Next: ensure the GHCR workflow has run (docs/tutorial.md Part B), then follow Part A steps 2+ (Helm installs)."
