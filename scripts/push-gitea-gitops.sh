#!/usr/bin/env bash
# Re-materialize the product repo into a local GitOps workdir and push to in-cluster Gitea (Kind lab).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

STATE_DIR="${STATE_DIR:-"$HOME/.spice-platform"}"
GITOPS_WORKDIR="${GITOPS_WORKDIR:-"${REPO_ROOT}/gitea/gitops"}"
CLUSTER_NAME="${CLUSTER_NAME:-spice-gitops}"
SPICE_GITEA_NAMESPACE="${SPICE_GITEA_NAMESPACE:-gitea}"
SPICE_GITEA_RELEASE="${SPICE_GITEA_RELEASE:-gitea}"
SPICE_GITEA_REPO_NAME="${SPICE_GITEA_REPO_NAME:-gitops}"
SPICE_GITEA_ADMIN_USER="${SPICE_GITEA_ADMIN_USER:-spice-admin}"
SPICE_GITEA_PF_PORT="${SPICE_GITEA_PF_PORT:-3333}"
GITOPS_TARGET_REVISION="${GITOPS_TARGET_REVISION:-main}"
GITOPS_PUSH_FORCE="${GITOPS_PUSH_FORCE:-0}"
DRY_RUN=0

die() {
  echo "error: $*" >&2
  exit 1
}

usage() {
  cat <<'USAGE'
Usage: push-gitea-gitops.sh [options]

Re-materialize templates from this product repo into GITOPS_WORKDIR and push to the
local Gitea GitOps repository (Kind + Gitea lab from scripts/install.sh).

Options:
  --workdir PATH   GitOps working tree (default: REPO_ROOT/gitea/gitops)
  --dry-run        Materialize and show diff; do not commit or push
  --help           Show this help

Environment:
  GITOPS_WORKDIR, STATE_DIR, CLUSTER_NAME
  SPICE_GITEA_NAMESPACE, SPICE_GITEA_RELEASE, SPICE_GITEA_REPO_NAME, SPICE_GITEA_ADMIN_USER
  SPICE_GITEA_PF_PORT, GITOPS_TARGET_REVISION, GITOPS_COMMIT_MSG, GITOPS_PUSH_FORCE
  GITOPS_PAT or GITEA_PASSWORD (else read from STATE_DIR/gitea-local-credentials.txt)
  SPICE_RELEASE (default 0.0.0-dev when dev tree present)

After push, refresh/sync Argo application platform-gitops. Control-plane image changes
require: make image-build && make image-load-local (materialize only updates Helm refs).
USAGE
}

gitea_internal_http_clone_url() {
  printf 'http://%s-http.%s.svc.cluster.local:3000/%s/%s.git' \
    "${SPICE_GITEA_RELEASE}" "${SPICE_GITEA_NAMESPACE}" \
    "${SPICE_GITEA_ADMIN_USER}" "${SPICE_GITEA_REPO_NAME}"
}

gitea_host_push_url() {
  local password="$1"
  local port="$2"
  printf 'http://%s:%s@127.0.0.1:%s/%s/%s.git' \
    "${SPICE_GITEA_ADMIN_USER}" "${password}" "${port}" \
    "${SPICE_GITEA_ADMIN_USER}" "${SPICE_GITEA_REPO_NAME}"
}

gitea_wait_api() {
  local port="$1"
  local i
  for i in $(seq 1 60); do
    if curl -sf "http://127.0.0.1:${port}/api/v1/version" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  die "Gitea API did not become ready on port ${port} (is the Kind cluster running?)"
}

load_in_cluster_repo_url() {
  local envf="${STATE_DIR}/install.env"
  if [[ -f "${envf}" ]]; then
    # shellcheck disable=SC1090
    local url=""
    url="$(grep -E '^IN_CLUSTER_REPO_URL=' "${envf}" 2>/dev/null | head -1 | cut -d= -f2- || true)"
    if [[ -n "${url}" ]]; then
      printf '%s' "${url}"
      return
    fi
  fi
  gitea_internal_http_clone_url
}

load_gitea_password() {
  if [[ -n "${GITOPS_PAT:-}" ]]; then
    printf '%s' "${GITOPS_PAT}"
    return
  fi
  if [[ -n "${GITEA_PASSWORD:-}" ]]; then
    printf '%s' "${GITEA_PASSWORD}"
    return
  fi
  local credf="${STATE_DIR}/gitea-local-credentials.txt"
  if [[ -f "${credf}" ]]; then
    local pw=""
    pw="$(grep -E '^GITEA_PASSWORD=' "${credf}" 2>/dev/null | head -1 | cut -d= -f2- || true)"
    if [[ -n "${pw}" ]]; then
      printf '%s' "${pw}"
      return
    fi
  fi
  die "Gitea password not found. Set GITOPS_PAT or run scripts/install.sh for a local Kind lab first."
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workdir)
      GITOPS_WORKDIR="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --help | -h)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1 (try --help)"
      ;;
  esac
done

command -v git >/dev/null 2>&1 || die "git is required"
command -v kubectl >/dev/null 2>&1 || die "kubectl is required"
command -v curl >/dev/null 2>&1 || die "curl is required"

[[ -d "${REPO_ROOT}/templates/gitops/apps" ]] || die "missing templates/gitops/apps (run from product repo checkout)"

if command -v kind >/dev/null 2>&1; then
  if ! kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    die "Kind cluster '${CLUSTER_NAME}' not found (create with: make kind-create && scripts/install.sh)"
  fi
fi

GITEA_PASSWORD="$(load_gitea_password)"
IN_CLUSTER_REPO_URL="$(load_in_cluster_repo_url)"
mkdir -p "${GITOPS_WORKDIR}"
GITOPS_WORKDIR="$(cd "${GITOPS_WORKDIR}" && pwd)"

git_backup=""
GITEA_PF_PID=""
stop_port_forward() {
  if [[ -n "${GITEA_PF_PID}" ]]; then
    kill "${GITEA_PF_PID}" 2>/dev/null || true
    wait "${GITEA_PF_PID}" 2>/dev/null || true
    GITEA_PF_PID=""
  fi
}
cleanup_all() {
  stop_port_forward
  [[ -n "${git_backup}" && -d "${git_backup}" ]] && rm -rf "${git_backup}"
}
trap cleanup_all EXIT INT TERM

if [[ -d "${GITOPS_WORKDIR}/.git" ]]; then
  git_backup="$(mktemp -d)"
  cp -a "${GITOPS_WORKDIR}/.git" "${git_backup}/"
fi

echo "Materializing product repo into ${GITOPS_WORKDIR} (Gitea lab backend)…" >&2
SPICE_MATERIALIZE_GITEA=1 GITOPS_REPO_URL="${IN_CLUSTER_REPO_URL}" GITOPS_TARGET_REVISION="${GITOPS_TARGET_REVISION}" \
  "${SCRIPT_DIR}/install.sh" --materialize "${GITOPS_WORKDIR}"

if [[ -n "${git_backup}" ]]; then
  rm -rf "${GITOPS_WORKDIR}/.git"
  cp -a "${git_backup}/.git" "${GITOPS_WORKDIR}/"
  rm -rf "${git_backup}"
  git_backup=""
fi

ensure_git_identity() {
  git -C "${GITOPS_WORKDIR}" config user.email "spice-local@invalid" 2>/dev/null || true
  git -C "${GITOPS_WORKDIR}" config user.name "spice-local" 2>/dev/null || true
}

# Align local branch with remote history while keeping the materialized working tree.
sync_git_branch_with_remote() {
  local push_url="$1"
  git -C "${GITOPS_WORKDIR}" remote remove origin 2>/dev/null || true
  git -C "${GITOPS_WORKDIR}" remote add origin "${push_url}"
  if git -C "${GITOPS_WORKDIR}" fetch -q origin "${GITOPS_TARGET_REVISION}" 2>/dev/null \
    && git -C "${GITOPS_WORKDIR}" rev-parse "refs/remotes/origin/${GITOPS_TARGET_REVISION}" >/dev/null 2>&1; then
    git -C "${GITOPS_WORKDIR}" checkout -B "${GITOPS_TARGET_REVISION}"
    git -C "${GITOPS_WORKDIR}" reset "origin/${GITOPS_TARGET_REVISION}"
    echo "Synced ${GITOPS_TARGET_REVISION} to origin/${GITOPS_TARGET_REVISION} (materialized tree kept)." >&2
  else
    git -C "${GITOPS_WORKDIR}" checkout -B "${GITOPS_TARGET_REVISION}" 2>/dev/null || true
  fi
}

if [[ ! -d "${GITOPS_WORKDIR}/.git" ]]; then
  git -C "${GITOPS_WORKDIR}" init -b "${GITOPS_TARGET_REVISION}"
  ensure_git_identity
fi

if [[ "${DRY_RUN}" -eq 1 ]]; then
  echo "Dry run: materialized at ${GITOPS_WORKDIR}" >&2
  git -C "${GITOPS_WORKDIR}" status -sb || true
  git -C "${GITOPS_WORKDIR}" diff --stat || true
  exit 0
fi

kubectl -n "${SPICE_GITEA_NAMESPACE}" port-forward "svc/${SPICE_GITEA_RELEASE}-http" "${SPICE_GITEA_PF_PORT}:3000" >/dev/null 2>&1 &
GITEA_PF_PID=$!
gitea_wait_api "${SPICE_GITEA_PF_PORT}"

push_url="$(gitea_host_push_url "${GITEA_PASSWORD}" "${SPICE_GITEA_PF_PORT}")"
ensure_git_identity
sync_git_branch_with_remote "${push_url}"

# git reset restores tracked Helm values from remote; re-apply Kind lab credential patches.
STATE_DIR="${STATE_DIR:-"$HOME/.spice-platform"}"
# shellcheck source=gitops-lab-patches.sh
. "${SCRIPT_DIR}/gitops-lab-patches.sh"
patch_materialized_addon_credentials "${GITOPS_WORKDIR}"

git -C "${GITOPS_WORKDIR}" add -A
if git -C "${GITOPS_WORKDIR}" diff --staged --quiet; then
  echo "Nothing to commit in ${GITOPS_WORKDIR}; Gitea is already up to date." >&2
  exit 0
fi

product_sha="$(git -C "${REPO_ROOT}" rev-parse --short HEAD 2>/dev/null || echo unknown)"
commit_msg="${GITOPS_COMMIT_MSG:-sync: product repo @ ${product_sha}}"
git -C "${GITOPS_WORKDIR}" commit -m "${commit_msg}"

push_args=(origin "${GITOPS_TARGET_REVISION}")
if [[ "${GITOPS_PUSH_FORCE}" == "1" ]]; then
  push_args+=(--force)
fi
if ! git -C "${GITOPS_WORKDIR}" push "${push_args[@]}"; then
  if [[ "${GITOPS_PUSH_FORCE}" == "1" ]]; then
    die "git push failed (force was already requested)"
  fi
  echo "Push rejected; retrying with --force-with-lease (set GITOPS_PUSH_FORCE=1 to skip lease check)…" >&2
  git -C "${GITOPS_WORKDIR}" push --force-with-lease origin "${GITOPS_TARGET_REVISION}"
fi

stop_port_forward
trap - EXIT INT TERM

echo "Pushed to Gitea (${SPICE_GITEA_ADMIN_USER}/${SPICE_GITEA_REPO_NAME}@${GITOPS_TARGET_REVISION})." >&2
echo "Next: refresh/sync Argo application platform-gitops." >&2
echo "Control-plane image changes: make image-build && make image-load-local" >&2
exit 0
