#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "See docs/tutorial.md for full bootstrap. This script only recreates Kind + builds/loads the control-plane image."
make kind-delete || true
make kind-create
make image-load
echo "Done. Next: follow docs/tutorial.md Part A steps 2+ (Helm installs)."
