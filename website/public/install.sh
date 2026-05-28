#!/usr/bin/env bash
# Spice platform local installer (Kind + GitOps bootstrap).
# Pinned installs use a GitHub Release tarball; dev mode uses this git checkout when SPICE_RELEASE=0.0.0-dev.
set -euo pipefail

# When run as `curl … | bash`, the script has no file path; BASH_SOURCE[0] is unset and `set -u` errors.
set +u
__install_src="${BASH_SOURCE[0]-}"
set -u
SCRIPT_DIR=""
REPO_ROOT=""
if [[ -n "${__install_src}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${__install_src}")" && pwd)"
  REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
  INSTALL_FROM_PIPE=0
else
  REPO_ROOT="$(pwd)"
  INSTALL_FROM_PIPE=1
fi
unset __install_src

# Trim whitespace/CR and stray commas (bad CI embeds, CSV copy-paste, fragile JSON parsing).
normalize_shell_token() {
  local s="${1-}"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  s="${s//$'\r'/}"
  while [[ "${s}" == ,* ]]; do s="${s#,}"; done
  while [[ "${s}" == *, ]]; do s="${s%,}"; done
  printf '%s' "${s}"
}

# Injected when copied into a release tarball (see .github/workflows/release.yml).
SPICE_PACKAGED_RELEASE=""

SPICE_PRODUCT_REPO="${SPICE_PRODUCT_REPO:-felipemm/spice-cdn}"
SPICE_PRODUCT_REPO="$(normalize_shell_token "${SPICE_PRODUCT_REPO}")"
SPICE_GITOPS_DIR="${SPICE_GITOPS_DIR:-}"
CLUSTER_NAME="${CLUSTER_NAME:-spice-gitops}"
STATE_DIR="${STATE_DIR:-"$HOME/.spice-platform"}"
# Local lab (no --gitops-repo): Helm Gitea in-cluster + ingress UI; Argo clones over HTTP inside the cluster.
SPICE_GITEA_NAMESPACE="${SPICE_GITEA_NAMESPACE:-gitea}"
SPICE_GITEA_RELEASE="${SPICE_GITEA_RELEASE:-gitea}"
SPICE_GITEA_REPO_NAME="${SPICE_GITEA_REPO_NAME:-gitops}"
SPICE_GITEA_ADMIN_USER="${SPICE_GITEA_ADMIN_USER:-spice-admin}"
SPICE_GITEA_INGRESS_HOST="${SPICE_GITEA_INGRESS_HOST:-gitea.127.0.0.1.nip.io}"
# Gitea Actions act_runner (helm chart gitea-charts/actions); local lab only unless SPICE_SKIP_GITEA_ACTIONS_RUNNER=1.
SPICE_GITEA_ACTIONS_NAMESPACE="${SPICE_GITEA_ACTIONS_NAMESPACE:-gitea-actions}"
SPICE_GITEA_ACTIONS_RELEASE="${SPICE_GITEA_ACTIONS_RELEASE:-gitea-actions}"
SPICE_SKIP_GITEA_ACTIONS_RUNNER="${SPICE_SKIP_GITEA_ACTIONS_RUNNER:-0}"
# Standalone Bitnami Valkey (shared). Service DNS: ${SPICE_VALKEY_PRIMARY_SVC}.${SPICE_VALKEY_NAMESPACE}.svc.cluster.local
SPICE_VALKEY_NAMESPACE="${SPICE_VALKEY_NAMESPACE:-valkey}"
SPICE_VALKEY_RELEASE="${SPICE_VALKEY_RELEASE:-valkey}"
SPICE_VALKEY_PRIMARY_SVC="${SPICE_VALKEY_PRIMARY_SVC:-${SPICE_VALKEY_RELEASE}-primary}"

valkey_primary_tcp_addr() {
  printf '%s.%s.svc.cluster.local:6379' "${SPICE_VALKEY_PRIMARY_SVC}" "${SPICE_VALKEY_NAMESPACE}"
}

write_gitea_valkey_overrides_file() {
  local pw="$1"
  local addr
  addr="$(valkey_primary_tcp_addr)"
  local out="${STATE_DIR}/gitea-valkey-overrides.yaml"
  umask 077
  cat >"${out}" <<EOF
gitea:
  config:
    session:
      PROVIDER: redis
      PROVIDER_CONFIG: "network=tcp,addr=${addr},password=${pw},db=0,pool_size=100"
    cache:
      ADAPTER: redis
      HOST: "network=tcp,addr=${addr},password=${pw},db=1,pool_size=100"
    queue:
      TYPE: redis
      CONN_STR: "redis://:${pw}@${addr}/2"
EOF
  chmod 600 "${out}"
}

install_valkey_standalone() {
  local bootstrap_dir="$1"
  local vf="${bootstrap_dir}/values-valkey.yaml"
  [[ -f "${vf}" ]] || die "missing ${vf} (add templates/gitops/bootstrap/values-valkey.yaml to the release bundle / repo)"
  helm repo add bitnami https://charts.bitnami.com/bitnami 2>/dev/null || true
  helm repo update bitnami
  umask 077
  local pwfile="${STATE_DIR}/valkey-lab.password"
  if [[ ! -s "${pwfile}" ]]; then
    openssl rand -hex 16 >"${pwfile}"
    chmod 600 "${pwfile}"
  fi
  local pw
  pw="$(tr -d '\n\r' <"${pwfile}")"
  local authf="${STATE_DIR}/valkey-auth-values.yaml"
  cat >"${authf}" <<EOF
auth:
  password: ${pw}
EOF
  chmod 600 "${authf}"
  local chart_ver="${VALKEY_CHART_VERSION:-6.0.2}"
  helm upgrade --install "${SPICE_VALKEY_RELEASE}" bitnami/valkey \
    -n "${SPICE_VALKEY_NAMESPACE}" --create-namespace \
    --version "${chart_ver}" \
    -f "${vf}" -f "${authf}"
  kubectl -n "${SPICE_VALKEY_NAMESPACE}" rollout status "statefulset/${SPICE_VALKEY_PRIMARY_SVC}" --timeout=300s
}

# curl | bash has no BASH_SOURCE path; lab patches ship next to install.sh in the release tarball.
spice_source_gitops_lab_patches() {
  local bundle_root="${1:-}"
  if [[ -n "${_GITOPS_LAB_PATCHES_LOADED:-}" ]]; then
    return 0
  fi
  local f="" candidate
  for candidate in \
    "${SCRIPT_DIR}/gitops-lab-patches.sh" \
    "${REPO_ROOT}/scripts/gitops-lab-patches.sh" \
    "${bundle_root}/gitops-lab-patches.sh" \
    "${bundle_root}/scripts/gitops-lab-patches.sh"; do
    if [[ -n "${candidate}" && -f "${candidate}" ]]; then
      f="${candidate}"
      break
    fi
  done
  [[ -n "${f}" ]] || die "missing gitops-lab-patches.sh (use a published release or clone the product repo)"
  # shellcheck source=gitops-lab-patches.sh
  . "${f}"
  _GITOPS_LAB_PATCHES_LOADED=1
}

gitea_internal_http_clone_url() {
  printf 'http://%s-http.%s.svc.cluster.local:3000/%s/%s.git' \
    "${SPICE_GITEA_RELEASE}" "${SPICE_GITEA_NAMESPACE}" \
    "${SPICE_GITEA_ADMIN_USER}" "${SPICE_GITEA_REPO_NAME}"
}

gitea_web_url() {
  printf 'http://%s/' "${SPICE_GITEA_INGRESS_HOST}"
}

install_gitea_chart() {
  local bundle_root="$1"
  local admin_pass="$2"
  local vf=""
  if [[ -f "${bundle_root}/templates/gitops/bootstrap/values-gitea.yaml" ]]; then
    vf="${bundle_root}/templates/gitops/bootstrap/values-gitea.yaml"
  elif [[ -f "${bundle_root}/bootstrap/values-gitea.yaml" ]]; then
    vf="${bundle_root}/bootstrap/values-gitea.yaml"
  elif [[ -f "${REPO_ROOT}/templates/gitops/bootstrap/values-gitea.yaml" ]]; then
    vf="${REPO_ROOT}/templates/gitops/bootstrap/values-gitea.yaml"
  fi
  [[ -f "${vf}" ]] || die "missing templates/gitops/bootstrap/values-gitea.yaml"
  helm repo add gitea-charts https://dl.gitea.com/charts/ 2>/dev/null || true
  helm repo update gitea-charts
  umask 077
  local secretf="${STATE_DIR}/gitea-admin-secret-values.yaml"
  cat >"${secretf}" <<EOF
gitea:
  admin:
    username: ${SPICE_GITEA_ADMIN_USER}
    password: ${admin_pass}
EOF
  local pwfile="${STATE_DIR}/valkey-lab.password"
  [[ -s "${pwfile}" ]] || die "missing ${pwfile} (install Valkey via helm_bootstrap before Gitea)"
  local vk_pw
  vk_pw="$(tr -d '\n\r' <"${pwfile}")"
  write_gitea_valkey_overrides_file "${vk_pw}"
  local vkof="${STATE_DIR}/gitea-valkey-overrides.yaml"
  # Do not use "${optional[@]}" with an empty array under `set -u` (unbound variable on many Bash builds).
  if [[ -n "${GITEA_CHART_VERSION:-}" ]]; then
    helm upgrade --install "${SPICE_GITEA_RELEASE}" gitea-charts/gitea \
      -n "${SPICE_GITEA_NAMESPACE}" --create-namespace \
      --version "${GITEA_CHART_VERSION}" \
      -f "${vf}" -f "${secretf}" -f "${vkof}"
  else
    helm upgrade --install "${SPICE_GITEA_RELEASE}" gitea-charts/gitea \
      -n "${SPICE_GITEA_NAMESPACE}" --create-namespace \
      -f "${vf}" -f "${secretf}" -f "${vkof}"
  fi
  kubectl -n "${SPICE_GITEA_NAMESPACE}" rollout status "deploy/${SPICE_GITEA_RELEASE}" --timeout=600s
}

# Parse {"token":"..."} from first argument (registration token). Prefers python3, else sed.
gitea_parse_registration_token() {
  local raw="${1-}"
  [[ -n "${raw}" ]] || return 1
  if command -v python3 >/dev/null 2>&1; then
    printf '%s' "${raw}" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("token") or "")' 2>/dev/null
    return 0
  fi
  printf '%s' "${raw}" | sed -n 's/.*"token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1
}

install_gitea_actions_runner() {
  local bundle_root="$1"
  local admin_pass="$2"
  local api_port="$3"
  if [[ "${SPICE_SKIP_GITEA_ACTIONS_RUNNER:-0}" == "1" ]] || ! spice_feature_enabled gitea_actions; then
    echo "Skipping Gitea Actions runner (disabled in feature selection or SPICE_SKIP_GITEA_ACTIONS_RUNNER=1)." >&2
    return 0
  fi
  local vf=""
  if [[ -f "${bundle_root}/templates/gitops/bootstrap/values-gitea-actions.yaml" ]]; then
    vf="${bundle_root}/templates/gitops/bootstrap/values-gitea-actions.yaml"
  elif [[ -f "${bundle_root}/bootstrap/values-gitea-actions.yaml" ]]; then
    vf="${bundle_root}/bootstrap/values-gitea-actions.yaml"
  elif [[ -f "${REPO_ROOT}/templates/gitops/bootstrap/values-gitea-actions.yaml" ]]; then
    vf="${REPO_ROOT}/templates/gitops/bootstrap/values-gitea-actions.yaml"
  fi
  [[ -f "${vf}" ]] || {
    echo "warning: missing values-gitea-actions.yaml; skip Gitea Actions runner install." >&2
    return 0
  }

  local raw="" tok=""
  raw="$(curl -fsS -u "${SPICE_GITEA_ADMIN_USER}:${admin_pass}" -X POST \
    "http://127.0.0.1:${api_port}/api/v1/admin/actions/runners/registration-token" 2>/dev/null || true)"
  tok="$(gitea_parse_registration_token "${raw}")"
  tok="$(printf '%s' "${tok}" | tr -d '\r\n')"
  if [[ -z "${tok}" ]]; then
    echo "warning: could not obtain Actions runner registration token (upgrade Gitea or enable Actions). Skip act_runner Helm install." >&2
    return 0
  fi

  helm repo add gitea-charts https://dl.gitea.com/charts/ 2>/dev/null || true
  helm repo update gitea-charts

  kubectl create namespace "${SPICE_GITEA_ACTIONS_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
  kubectl -n "${SPICE_GITEA_ACTIONS_NAMESPACE}" delete secret gitea-actions-runner-secret --ignore-not-found
  kubectl -n "${SPICE_GITEA_ACTIONS_NAMESPACE}" create secret generic gitea-actions-runner-secret \
    --from-literal=runner-token="${tok}"

  local ver="${ACTIONS_CHART_VERSION:-0.1.1}"
  helm upgrade --install "${SPICE_GITEA_ACTIONS_RELEASE}" gitea-charts/actions \
    -n "${SPICE_GITEA_ACTIONS_NAMESPACE}" \
    --version "${ver}" \
    -f "${vf}"
  kubectl -n "${SPICE_GITEA_ACTIONS_NAMESPACE}" rollout status "statefulset/${SPICE_GITEA_ACTIONS_RELEASE}-runner" --timeout=600s || true
  echo "Gitea Actions runner installed in namespace ${SPICE_GITEA_ACTIONS_NAMESPACE} (release ${SPICE_GITEA_ACTIONS_RELEASE})." >&2
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
  die "Gitea API did not become ready on port ${port}"
}

gitea_create_empty_repo() {
  local admin_pass="$1"
  local port="$2"
  curl -sS -u "${SPICE_GITEA_ADMIN_USER}:${admin_pass}" \
    -H "Content-Type: application/json" \
    -X POST "http://127.0.0.1:${port}/api/v1/user/repos" \
    -d "{\"name\":\"${SPICE_GITEA_REPO_NAME}\",\"private\":false,\"auto_init\":false,\"default_branch\":\"main\"}" \
    >/dev/null || true
}

build_kind_lab_control_plane_images() {
  local bundle_root="$1"
  local cluster_name="$2"
  local cp_ctx="${bundle_root}/apps/control-plane"
  local mcp_ctx="${bundle_root}/apps/control-plane-mcp"
  [[ -f "${cp_ctx}/Dockerfile" ]] || die "missing ${cp_ctx}/Dockerfile (upgrade to a release that bundles apps/ or use SPICE_RELEASE=0.0.0-dev from a git clone)"
  [[ -f "${mcp_ctx}/Dockerfile" ]] || die "missing ${mcp_ctx}/Dockerfile (upgrade to a release that bundles apps/ or use SPICE_RELEASE=0.0.0-dev from a git clone)"
  echo "Building control-plane + MCP images and loading into Kind (avoids ghcr.io)…" >&2
  docker build -t spice-cp-local:lab -f "${cp_ctx}/Dockerfile" "${cp_ctx}"
  docker build -t spice-cp-mcp-local:lab -f "${mcp_ctx}/Dockerfile" "${mcp_ctx}"
  kind load docker-image spice-cp-local:lab --name "${cluster_name}"
  kind load docker-image spice-cp-mcp-local:lab --name "${cluster_name}"
}

gitea_push_materialized_workdir() {
  local work="$1"
  local admin_pass="$2"
  local port="$3"
  rm -rf "${work}/.git"
  git -C "${work}" init -b main
  git -C "${work}" config user.email "spice-local@invalid"
  git -C "${work}" config user.name "spice-local"
  git -C "${work}" add -A
  git -C "${work}" commit -m "bootstrap" || true
  git -C "${work}" remote remove origin 2>/dev/null || true
  git -C "${work}" remote add origin "http://${SPICE_GITEA_ADMIN_USER}:${admin_pass}@127.0.0.1:${port}/${SPICE_GITEA_ADMIN_USER}/${SPICE_GITEA_REPO_NAME}.git"
  git -C "${work}" push -u origin main --force
}

fetch_latest_github_release_tag() {
  command -v curl >/dev/null 2>&1 || return 1
  curl -fsSL ${GITHUB_TOKEN:+-H "Authorization: Bearer ${GITHUB_TOKEN}"} \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${SPICE_PRODUCT_REPO}/releases/latest" 2>/dev/null \
    | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1
}

usage() {
  cat <<'USAGE'
Usage:
  install.sh [options]

Options:
  --gitops-repo URL     Remote GitOps repo (HTTPS, must end with .git). Omit for a local-only Kind lab.
  --gitops-pat TOKEN    PAT for Argo + control plane (remote repos; use for private GitHub repos).
  --revision BRANCH     Argo targetRevision (default: main)
  --release VERSION     Platform version tag (default: packaged release or latest from API)
  --materialize DIR     Only render templates into DIR and exit (no cluster)
  --upgrade             Re-materialize from latest product release (remote GitOps only; see state file)
  --uninstall --all     Delete the Kind cluster (CLUSTER_NAME)
  --yes                 Answer yes to confirmation prompts; install missing host tools; enable all optional features
  --features LIST       Comma-separated optional features to enable (disables others): prometheus, opencost, superset, gitea_actions
  --without-features LIST  Comma-separated features to disable (default is all on): prometheus, opencost, superset, gitea_actions

Defaults:
  Unset GITOPS_REPO_URL → local Kind lab: Gitea in-cluster (HTTP for Argo), ingress UI at
  http://gitea.127.0.0.1.nip.io/ ; materialized tree is pushed once to Gitea (admin password = Argo repo secret).
  A standalone Valkey (namespace valkey) is installed for Gitea session/cache/queue and for other workloads.
  Grafana + Superset addon secrets (random) are written under STATE_DIR (see grafana-superset-credentials.txt) and patched into the materialized Argo apps.
  Piped installs (no TTY) default --yes for bootstrap steps so you are not asked to type confirmations.

Optional overrides (environment):
  SPICE_RELEASE, SPICE_GITOPS_DIR, SPICE_PRODUCT_REPO, CLUSTER_NAME, STATE_DIR
  GITOPS_REPO_URL, GITOPS_PAT, GITOPS_TARGET_REVISION, GITHUB_TOKEN
  SPICE_GITEA_NAMESPACE, SPICE_GITEA_RELEASE, SPICE_GITEA_REPO_NAME, SPICE_GITEA_ADMIN_USER, SPICE_GITEA_INGRESS_HOST
  SPICE_GITEA_ACTIONS_NAMESPACE, SPICE_GITEA_ACTIONS_RELEASE, SPICE_SKIP_GITEA_ACTIONS_RUNNER (set to 1 to skip act_runner), ACTIONS_CHART_VERSION (default 0.1.1)
  SPICE_VALKEY_NAMESPACE, SPICE_VALKEY_RELEASE, SPICE_VALKEY_PRIMARY_SVC, VALKEY_CHART_VERSION (default 6.0.2)
  SPICE_DISABLE_LOCAL_GITOPS=1  Require --gitops-repo (fail if URL empty)
  SPICE_FEATURES=prometheus,superset  Optional components (saved to install.env after install)

Examples:
  install.sh
  install.sh --gitops-repo https://github.com/org/spice-gitops.git --gitops-pat "$TOKEN"
  curl -fsSL …/install.sh | bash -s -- --gitops-repo https://github.com/org/gitops.git --gitops-pat "$TOKEN"
USAGE
}

die() {
  echo "error: $*" >&2
  exit 1
}

# --- Host dependency bootstrap (install missing CLIs; binaries go to STATE_DIR/bin, prepended to PATH) ---

spice_prepend_installer_bin_path() {
  mkdir -p "${STATE_DIR}/bin"
  case ":${PATH}:" in
    *":${STATE_DIR}/bin:"*) ;;
    *) export PATH="${STATE_DIR}/bin:${PATH}" ;;
  esac
}

spice_try_pkg_install() {
  [[ $# -ge 1 ]] || return 1
  if command -v brew >/dev/null 2>&1; then
    HOMEBREW_NO_AUTO_UPDATE=1 brew install -q "$@" >/dev/null 2>&1 && return 0
    HOMEBREW_NO_AUTO_UPDATE=1 brew install "$@" >/dev/null 2>&1 && return 0
    return 1
  fi
  local sudocmd=()
  command -v sudo >/dev/null 2>&1 && sudocmd=(sudo -E)
  if command -v apt-get >/dev/null 2>&1; then
    DEBIAN_FRONTEND=noninteractive "${sudocmd[@]}" apt-get update -qq >/dev/null 2>&1
    DEBIAN_FRONTEND=noninteractive "${sudocmd[@]}" apt-get install -y -qq "$@" >/dev/null 2>&1 && return 0
  fi
  if command -v dnf >/dev/null 2>&1; then
    "${sudocmd[@]}" dnf install -y "$@" >/dev/null 2>&1 && return 0
  fi
  if command -v yum >/dev/null 2>&1; then
    "${sudocmd[@]}" yum install -y "$@" >/dev/null 2>&1 && return 0
  fi
  if command -v apk >/dev/null 2>&1; then
    "${sudocmd[@]}" apk add --no-cache "$@" >/dev/null 2>&1 && return 0
  fi
  if command -v pacman >/dev/null 2>&1; then
    "${sudocmd[@]}" pacman -Sy --noconfirm "$@" >/dev/null 2>&1 && return 0
  fi
  if command -v zypper >/dev/null 2>&1; then
    "${sudocmd[@]}" zypper install -y "$@" >/dev/null 2>&1 && return 0
  fi
  return 1
}

spice_dep_present() {
  local dep="$1"
  case "${dep}" in
    docker)
      command -v docker >/dev/null 2>&1 || return 1
      docker info >/dev/null 2>&1
      ;;
    *)
      command -v "${dep}" >/dev/null 2>&1
      ;;
  esac
}

spice_dep_install_hint() {
  local dep="$1"
  case "${dep}" in
    curl) printf '%s' "package manager (e.g. brew install curl, apt install curl)" ;;
    tar) printf '%s' "package manager (e.g. brew install gnu-tar, apt install tar)" ;;
    openssl) printf '%s' "package manager (e.g. brew install openssl, apt install openssl)" ;;
    git) printf '%s' "package manager (e.g. brew install git, apt install git)" ;;
    docker)
      if [[ "$(uname -s)" == Darwin* ]] && command -v brew >/dev/null 2>&1; then
        printf '%s' "Homebrew: brew install --cask docker (then start Docker Desktop)"
      else
        printf '%s' "package manager (e.g. apt install docker.io) or https://docs.docker.com/get-docker/"
      fi
      ;;
    kubectl|helm|kind)
      printf '%s' "download to ${STATE_DIR}/bin (installer)" ;;
    *) printf '%s' "your OS package manager or vendor docs" ;;
  esac
}

spice_deps_refuse_install() {
  [[ "${YES:-0}" == "1" ]] && return 1
  [[ "${NONINTERACTIVE:-0}" == "1" ]] || [[ "${CI:-}" == "1" ]] || [[ "${CI:-}" == "true" ]]
}

spice_confirm_install_dep() {
  local dep="$1" hint
  hint="$(spice_dep_install_hint "${dep}")"
  if [[ "${YES:-0}" == "1" ]]; then
    return 0
  fi
  if spice_deps_refuse_install; then
    return 1
  fi
  confirm "Install ${dep}? (${hint})"
}

spice_ensure_docker_daemon() {
  spice_dep_present docker && return 0
  if command -v docker >/dev/null 2>&1; then
    echo "error: docker is installed but the daemon is not running." >&2
    if [[ "$(uname -s)" == Darwin* ]]; then
      echo "  Start Docker Desktop, then re-run install.sh." >&2
    else
      echo "  Start the Docker service (e.g. sudo systemctl start docker), then re-run install.sh." >&2
    fi
    exit 1
  fi
  return 1
}

spice_install_docker() {
  if [[ "$(uname -s)" == Darwin* ]] && command -v brew >/dev/null 2>&1; then
    HOMEBREW_NO_AUTO_UPDATE=1 brew install --cask docker >/dev/null 2>&1 \
      || HOMEBREW_NO_AUTO_UPDATE=1 brew install --cask docker
    return 0
  fi
  spice_try_pkg_install docker.io \
    || spice_try_pkg_install docker \
    || spice_try_pkg_install moby-engine \
    || return 1
}

spice_install_dep() {
  local dep="$1"
  case "${dep}" in
    curl)
      spice_try_pkg_install ca-certificates curl || spice_try_pkg_install curl || return 1
      ;;
    tar)
      spice_try_pkg_install tar || return 1
      ;;
    openssl)
      spice_try_pkg_install openssl || return 1
      ;;
    git)
      spice_try_pkg_install git || return 1
      ;;
    docker)
      spice_install_docker || return 1
      spice_ensure_docker_daemon || true
      ;;
    kubectl)
      spice_install_kubectl_bindir || return 1
      ;;
    helm)
      spice_install_helm_bindir || return 1
      ;;
    kind)
      spice_install_kind_bindir || return 1
      ;;
    *) die "internal: unknown dependency ${dep}" ;;
  esac
}

spice_ensure_dep() {
  local dep="$1"
  if spice_dep_present "${dep}"; then
    return 0
  fi
  if ! spice_confirm_install_dep "${dep}"; then
    echo "error: ${dep} is required. Install manually: $(spice_dep_install_hint "${dep}")" >&2
    return 1
  fi
  echo "Installing ${dep}…" >&2
  spice_install_dep "${dep}" || {
    echo "error: could not install ${dep}. Install manually: $(spice_dep_install_hint "${dep}")" >&2
    return 1
  }
  if [[ "${dep}" == docker ]]; then
    spice_ensure_docker_daemon || return 1
  fi
  spice_dep_present "${dep}" || {
    echo "error: ${dep} still not available after install attempt." >&2
    return 1
  }
}

spice_report_deps() {
  local dep status hint
  echo "Checking host dependencies…" >&2
  for dep in "$@"; do
    if spice_dep_present "${dep}"; then
      status="ok"
    else
      status="missing"
    fi
    hint="$(spice_dep_install_hint "${dep}")"
    printf '  %-10s %s' "${dep}" "${status}" >&2
    [[ "${status}" == missing ]] && printf ' — %s' "${hint}" >&2
    echo "" >&2
  done
}

spice_ensure_deps_list() {
  local dep
  spice_report_deps "$@"
  for dep in "$@"; do
    spice_ensure_dep "${dep}" || return 1
  done
}

spice_ensure_curl() {
  spice_prepend_installer_bin_path
  if spice_dep_present curl; then
    return 0
  fi
  if [[ "${YES:-0}" == "1" ]]; then
    spice_install_dep curl || die "could not install curl"
    return 0
  fi
  if spice_deps_refuse_install; then
    die "curl is required. Install curl, or re-run with YES=1 to allow automatic install."
  fi
  if confirm "Install curl? ($(spice_dep_install_hint curl))"; then
    spice_install_dep curl || die "could not install curl"
    return 0
  fi
  die "curl is required to continue."
}

spice_ensure_tar() {
  spice_ensure_dep tar
}

spice_host_k8s_os_arch() {
  local os arch
  case "$(uname -s)" in
    Linux*) os=linux ;;
    Darwin*) os=darwin ;;
    *) die "unsupported OS for bundled CLI install: $(uname -s)" ;;
  esac
  arch="$(uname -m)"
  case "${arch}" in
    x86_64|amd64) arch=amd64 ;;
    aarch64|arm64) arch=arm64 ;;
    *) die "unsupported CPU for bundled CLI install: ${arch}" ;;
  esac
  printf '%s %s' "${os}" "${arch}"
}

spice_install_kind_bindir() {
  spice_ensure_curl
  local os arch ver dest="${STATE_DIR}/bin" url
  mkdir -p "${dest}"
  read -r os arch <<<"$(spice_host_k8s_os_arch)"
  ver="${KIND_VERSION:-v0.27.0}"
  url="https://github.com/kubernetes-sigs/kind/releases/download/${ver}/kind-${os}-${arch}"
  curl -fsSL -o "${dest}/kind.new" "${url}"
  chmod +x "${dest}/kind.new"
  mv -f "${dest}/kind.new" "${dest}/kind"
}

spice_install_kubectl_bindir() {
  spice_ensure_curl
  local os arch kv dest="${STATE_DIR}/bin" url
  mkdir -p "${dest}"
  read -r os arch <<<"$(spice_host_k8s_os_arch)"
  kv="${KUBECTL_VERSION:-}"
  if [[ -z "${kv}" ]]; then
    kv="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
    kv="${kv//$'\r'/}"
  fi
  url="https://dl.k8s.io/release/${kv}/bin/${os}/${arch}/kubectl"
  curl -fsSL -o "${dest}/kubectl.new" "${url}"
  chmod +x "${dest}/kubectl.new"
  mv -f "${dest}/kubectl.new" "${dest}/kubectl"
}

spice_install_helm_bindir() {
  spice_ensure_curl
  spice_ensure_tar
  local os arch ver tb dest="${STATE_DIR}/bin"
  mkdir -p "${dest}"
  read -r os arch <<<"$(spice_host_k8s_os_arch)"
  ver="${HELM_VERSION:-v3.16.3}"
  tb="helm-${ver}-${os}-${arch}.tar.gz"
  curl -fsSL "https://get.helm.sh/${tb}" | tar -xzO "${os}-${arch}/helm" >"${dest}/helm.new"
  chmod +x "${dest}/helm.new"
  mv -f "${dest}/helm.new" "${dest}/helm"
}

# profile: uninstall | upgrade | materialize | full
# optional second arg for full: 1 = ensure git (local Gitea lab)
ensure_spice_host_dependencies() {
  local profile="$1"
  local need_git="${2:-0}"
  local -a deps=()

  spice_prepend_installer_bin_path
  spice_ensure_curl

  case "${profile}" in
    uninstall)
      deps=(kind)
      ;;
    upgrade|materialize)
      deps=(tar)
      ;;
    full)
      deps=(tar openssl kubectl helm kind docker)
      [[ "${need_git}" == "1" ]] && deps+=(git)
      ;;
    *)
      die "internal: unknown dependency profile: ${profile}"
      ;;
  esac
  spice_ensure_deps_list "${deps[@]}"
}

spice_resolve_default_release_tag_if_piped() {
  if [[ "${INSTALL_FROM_PIPE}" -ne 1 ]] || [[ -n "${SPICE_PACKAGED_RELEASE}" ]] || [[ -n "${SPICE_RELEASE:-}" ]]; then
    return 0
  fi
  local _rel=""
  _rel="$(fetch_latest_github_release_tag)" || true
  if [[ -n "${_rel}" ]]; then
    SPICE_PACKAGED_RELEASE="$(normalize_shell_token "${_rel}")"
  fi
}

confirm() {
  [[ "${YES:-0}" == "1" ]] && return 0
  if [[ ! -t 0 ]] || [[ "${NONINTERACTIVE:-0}" == "1" ]] || [[ "${CI:-}" == "1" ]] || [[ "${CI:-}" == "true" ]]; then
    return 1
  fi
  local ans
  read -r -p "$* [y/N] " ans || true
  [[ "${ans}" == "y" || "${ans}" == "Y" ]]
}

# --- Optional platform features (Argo addons + local Gitea Actions) ---
# id|label|default|local_only|requires_csv
SPICE_FEATURE_DEFS=(
  "prometheus|Prometheus + Grafana (monitoring)|1|0|"
  "opencost|OpenCost (cost allocation UI)|1|0|prometheus"
  "superset|Apache Superset (BI / SQL Lab)|1|0|"
  "gitea_actions|Gitea Actions runner (CI jobs)|1|1|"
)

SPICE_FEATURES_ENABLED=""
SPICE_FEATURES_CLI_CONFIGURED=0

spice_feature_enabled() {
  local id="$1"
  case " ${SPICE_FEATURES_ENABLED} " in
    *" ${id} "*) return 0 ;;
    *) return 1 ;;
  esac
}

spice_feature_enable() {
  local id="$1"
  spice_feature_enabled "${id}" && return 0
  SPICE_FEATURES_ENABLED="${SPICE_FEATURES_ENABLED:+$SPICE_FEATURES_ENABLED }${id}"
}

spice_feature_disable() {
  local id="$1" out="" f
  for f in ${SPICE_FEATURES_ENABLED}; do
    [[ "${f}" == "${id}" ]] && continue
    out="${out:+$out }${f}"
  done
  SPICE_FEATURES_ENABLED="${out}"
}

spice_feature_label() {
  local id="$1" def id2 _lbl _def _loc _req
  for def in "${SPICE_FEATURE_DEFS[@]}"; do
    IFS='|' read -r id2 _lbl _def _loc _req <<<"${def}"
    [[ "${id2}" == "${id}" ]] && printf '%s' "${_lbl}" && return 0
  done
  printf '%s' "${id}"
}

spice_feature_init_defaults() {
  local local_lab="${1:-0}" def id _lbl _def _loc _req
  SPICE_FEATURES_ENABLED=""
  for def in "${SPICE_FEATURE_DEFS[@]}"; do
    IFS='|' read -r id _lbl _def _loc _req <<<"${def}"
    [[ "${_def}" == "1" ]] || continue
    [[ "${_loc}" == "1" && "${local_lab}" != "1" ]] && continue
    spice_feature_enable "${id}"
  done
}

spice_features_from_csv() {
  local csv="$1" id
  csv="${csv//,/ }"
  for id in ${csv}; do
    id="$(normalize_shell_token "${id}")"
    [[ -n "${id}" ]] && spice_feature_enable "${id}"
  done
}

spice_features_to_env() {
  printf '%s' "${SPICE_FEATURES_ENABLED# }"
}

spice_features_from_env() {
  local csv="$1"
  SPICE_FEATURES_ENABLED=""
  spice_features_from_csv "${csv}"
}

spice_apply_feature_dependencies() {
  if ! spice_feature_enabled prometheus && spice_feature_enabled opencost; then
    echo "Note: OpenCost requires Prometheus; disabling OpenCost." >&2
    spice_feature_disable opencost
  fi
}

spice_apply_cli_feature_flags() {
  local allow="${FEATURES_ALLOW:-}" deny="${FEATURES_DENY:-}" envf="${SPICE_FEATURES:-}"
  [[ -n "${allow}${deny}${envf}" ]] || return 0
  SPICE_FEATURES_CLI_CONFIGURED=1
  local local_lab="${SPICE_FEATURE_LOCAL_LAB:-0}"
  spice_feature_init_defaults "${local_lab}"
  if [[ -n "${deny}" ]]; then
    local id
    deny="${deny//,/ }"
    for id in ${deny}; do
      spice_feature_disable "$(normalize_shell_token "${id}")"
    done
  fi
  if [[ -n "${allow}" ]]; then
    SPICE_FEATURES_ENABLED=""
    spice_features_from_csv "${allow}"
  elif [[ -n "${envf}" ]]; then
    SPICE_FEATURES_ENABLED=""
    spice_features_from_csv "${envf}"
  fi
  spice_apply_feature_dependencies
}

spice_features_show_summary() {
  local def id _lbl _def _loc _req
  echo "Selected optional features:" >&2
  for def in "${SPICE_FEATURE_DEFS[@]}"; do
    IFS='|' read -r id _lbl _def _loc _req <<<"${def}"
    if spice_feature_enabled "${id}"; then
      printf '  [x] %s\n' "${_lbl}" >&2
    else
      printf '  [ ] %s\n' "${_lbl}" >&2
    fi
  done
}

spice_select_features_bash_menu() {
  local local_lab="${1:-0}" def id _lbl _def _loc _req
  local -a ids=() labels=() selected=()
  local i n ch

  for def in "${SPICE_FEATURE_DEFS[@]}"; do
    IFS='|' read -r id _lbl _def _loc _req <<<"${def}"
    [[ "${_loc}" == "1" && "${local_lab}" != "1" ]] && continue
    ids+=("${id}")
    labels+=("${_lbl}")
    if spice_feature_enabled "${id}"; then
      selected+=("1")
    else
      selected+=("0")
    fi
  done

  echo "" >&2
  echo "Select optional features (number=toggle, Enter=confirm). [*] = enabled" >&2
  while true; do
    for i in "${!ids[@]}"; do
      if [[ "${selected[$i]}" == "1" ]]; then
        printf '  [*] %s  %s\n' "$((i + 1))" "${labels[$i]}" >&2
      else
        printf '  [ ] %s  %s\n' "$((i + 1))" "${labels[$i]}" >&2
      fi
    done
    read -r -p "Choice (1-${#ids[@]} toggle, or Enter to continue): " ch || ch=""
    [[ -z "${ch}" ]] && break
    if [[ "${ch}" =~ ^[0-9]+$ ]] && [[ "${ch}" -ge 1 ]] && [[ "${ch}" -le ${#ids[@]} ]]; then
      i=$((ch - 1))
      if [[ "${selected[$i]}" == "1" ]]; then
        selected[$i]="0"
        spice_feature_disable "${ids[$i]}"
      else
        selected[$i]="1"
        spice_feature_enable "${ids[$i]}"
      fi
    else
      echo "Invalid choice." >&2
    fi
  done
}

spice_select_features_gum() {
  local local_lab="${1:-0}" def id _lbl _def _loc _req
  local -a choices=() picked=()
  local out line

  for def in "${SPICE_FEATURE_DEFS[@]}"; do
    IFS='|' read -r id _lbl _def _loc _req <<<"${def}"
    [[ "${_loc}" == "1" && "${local_lab}" != "1" ]] && continue
    if spice_feature_enabled "${id}"; then
      choices+=("${_lbl},selected")
    else
      choices+=("${_lbl}")
    fi
  done

  mapfile -t picked < <(gum choose --no-limit "${choices[@]}" 2>/dev/null || true)
  SPICE_FEATURES_ENABLED=""
  spice_feature_init_defaults "${local_lab}"
  for def in "${SPICE_FEATURE_DEFS[@]}"; do
    IFS='|' read -r id _lbl _def _loc _req <<<"${def}"
    [[ "${_loc}" == "1" && "${local_lab}" != "1" ]] && continue
    spice_feature_disable "${id}"
  done
  for line in "${picked[@]}"; do
    line="${line%,selected}"
    for def in "${SPICE_FEATURE_DEFS[@]}"; do
      IFS='|' read -r id _lbl _def _loc _req <<<"${def}"
      [[ "${_lbl}" == "${line}" ]] && spice_feature_enable "${id}"
    done
  done
}

spice_select_features_dialog() {
  local local_lab="${1:-0}" dlg="$2" def id _lbl _def _loc _req
  local -a args=() out line
  args=(--separate-output --checklist "Spice optional features" 18 72 12)
  for def in "${SPICE_FEATURE_DEFS[@]}"; do
    IFS='|' read -r id _lbl _def _loc _req <<<"${def}"
    [[ "${_loc}" == "1" && "${local_lab}" != "1" ]] && continue
    if spice_feature_enabled "${id}"; then
      args+=("${id}" "${_lbl}" "on")
    else
      args+=("${id}" "${_lbl}" "off")
    fi
  done
  out="$("${dlg}" "${args[@]}" 2>/dev/null)" || return 1
  SPICE_FEATURES_ENABLED=""
  while IFS= read -r line; do
    [[ -n "${line}" ]] && spice_feature_enable "${line}"
  done <<<"${out}"
  return 0
}

spice_select_features_interactive() {
  local local_lab="${1:-0}"
  if command -v gum >/dev/null 2>&1; then
    spice_select_features_gum "${local_lab}" && return 0
  fi
  if command -v dialog >/dev/null 2>&1; then
    spice_select_features_dialog "${local_lab}" dialog && return 0
  fi
  if command -v whiptail >/dev/null 2>&1; then
    spice_select_features_dialog "${local_lab}" whiptail && return 0
  fi
  spice_select_features_bash_menu "${local_lab}"
}

spice_select_features() {
  local local_lab="${1:-0}"
  SPICE_FEATURE_LOCAL_LAB="${local_lab}"

  if [[ -n "${FEATURES_ALLOW:-}${FEATURES_DENY:-}${SPICE_FEATURES:-}" ]]; then
    spice_apply_cli_feature_flags
  fi

  if [[ "${SPICE_SKIP_GITEA_ACTIONS_RUNNER:-0}" == "1" ]]; then
    spice_feature_disable gitea_actions
  fi

  if [[ "${SPICE_FEATURES_CLI_CONFIGURED}" != "1" ]]; then
    spice_feature_init_defaults "${local_lab}"
  fi

  if [[ "${SPICE_FEATURES_CLI_CONFIGURED}" == "1" ]]; then
    spice_apply_feature_dependencies
    spice_features_show_summary
    return 0
  fi

  if [[ "${YES:-0}" == "1" ]] || spice_deps_refuse_install; then
    spice_apply_feature_dependencies
    spice_features_show_summary
    return 0
  fi

  if [[ -t 0 ]]; then
    echo "" >&2
    echo "Optional platform components (default: all enabled):" >&2
    spice_select_features_interactive "${local_lab}"
  fi

  spice_apply_feature_dependencies
  spice_features_show_summary
}

spice_load_features_from_install_env() {
  [[ -f "${STATE_DIR}/install.env" ]] || return 0
  # shellcheck source=/dev/null
  source "${STATE_DIR}/install.env"
  if [[ -n "${SPICE_FEATURES:-}" ]]; then
    spice_features_from_env "${SPICE_FEATURES}"
    SPICE_FEATURES_CLI_CONFIGURED=1
  fi
}

effective_release() {
  local v
  v="$(normalize_shell_token "${SPICE_RELEASE:-}")"
  if [[ -z "${v}" ]]; then
    v="$(normalize_shell_token "${SPICE_PACKAGED_RELEASE:-}")"
  fi
  if [[ -z "${v}" ]]; then
    v="0.0.0-dev"
  fi
  printf '%s' "${v}"
}

is_dev_tree() {
  [[ -d "${REPO_ROOT}/templates/gitops/apps" ]]
}

download_release() {
  local ver="$1"
  local dest="$2"
  local url="https://github.com/${SPICE_PRODUCT_REPO}/releases/download/${ver}/spice-platform-${ver}.tar.gz"
  mkdir -p "${dest}"
  echo "Downloading ${url}" >&2
  if ! curl -fsSL -o "${dest}/bundle.tgz" "${url}"; then
    die "failed to download release ${ver}. Check --release / SPICE_PRODUCT_REPO or that ${url} exists."
  fi
  tar -xzf "${dest}/bundle.tgz" -C "${dest}"
  # Expect spice-platform-${ver}/...
  echo "${dest}/spice-platform-${ver}"
}

resolve_bundle_root() {
  local ver
  ver="$(effective_release)"
  if [[ "${ver}" == "0.0.0-dev" ]] && is_dev_tree; then
    echo "${REPO_ROOT}"
    return
  fi
  local tmp="${STATE_DIR}/extract/${ver}"
  rm -rf "${tmp}"
  mkdir -p "${tmp}"
  if [[ "${ver}" == "0.0.0-dev" ]]; then
    die "Release ${ver} requires a git checkout with templates/gitops (clone the product repo) or pass --release with a published tag."
  fi
  download_release "${ver}" "${tmp}"
}

materialize_tree() {
  local bundle_root="$1"
  spice_source_gitops_lab_patches "${bundle_root}"
  local out="$2"
  local gitops_url="$3"
  local revision="$4"
  local platform_ver="$5"
  local gitops_backend="${6:-github}"

  rm -rf "${out}"
  mkdir -p "${out}"

  local tpl_dir="${bundle_root}/templates/gitops"
  if [[ ! -d "${tpl_dir}" && -d "${bundle_root}/gitops" ]]; then
    tpl_dir="${bundle_root}/gitops"
  fi
  if [[ ! -d "${tpl_dir}" ]]; then
    die "bundle missing templates/gitops (or legacy gitops/) under ${bundle_root}"
  fi

  local g_owner="local"
  local g_name="spice-platform"
  if [[ "${gitops_url}" != git://* ]]; then
    local authpath="${gitops_url#*://}"
    if [[ "${authpath}" == */* ]]; then
      local hp="${authpath%%/*}"
      local rest="${authpath#"${hp}"/}"
      rest="${rest%.git}"
      if [[ "${rest}" == */* ]]; then
        g_owner="${rest%%/*}"
        g_name="${rest##*/}"
      fi
    fi
  fi

  cp -R "${tpl_dir}/apps" "${out}/apps"
  cp -R "${tpl_dir}/bootstrap" "${out}/bootstrap"
  [[ -d "${tpl_dir}/addons" ]] && cp -R "${tpl_dir}/addons" "${out}/addons" || true
  [[ -d "${tpl_dir}/cost" ]] && cp -R "${tpl_dir}/cost" "${out}/cost" || true
  cp -R "${bundle_root}/charts" "${out}/charts"
  cp -R "${bundle_root}/deploy" "${out}/deploy"
  if [[ -d "${bundle_root}/.gitea" ]]; then
    cp -R "${bundle_root}/.gitea" "${out}/.gitea"
  fi
  mkdir -p "${out}/instances"
  cp -R "${bundle_root}/examples/instances/"* "${out}/instances/"
  cp "${tpl_dir}/platform-version.yaml" "${out}/platform-version.yaml"

  # Root Argo Application (platform-gitops) only syncs apps/*.yaml — copy optional addon apps here.
  local kps_app="${tpl_dir}/addons/kube-prometheus-stack/application-kube-prometheus-stack.yaml"
  if spice_feature_enabled prometheus && [[ -f "${kps_app}" ]]; then
    cp "${kps_app}" "${out}/apps/application-kube-prometheus-stack.yaml"
  fi
  local oc_app="${tpl_dir}/addons/opencost/application-opencost.yaml"
  if spice_feature_enabled opencost && [[ -f "${oc_app}" ]]; then
    cp "${oc_app}" "${out}/apps/application-opencost.yaml"
  fi
  local ss_app="${tpl_dir}/addons/superset/application-superset.yaml"
  if spice_feature_enabled superset && [[ -f "${ss_app}" ]]; then
    cp "${ss_app}" "${out}/apps/application-superset.yaml"
  fi

  # Substitute template tokens (portable sed; no sed -i).
  while IFS= read -r -d '' f; do
    case "${f}" in
      *.yaml|*.yml|*.md|*.txt|*.json|*.env) ;;
      *) continue ;;
    esac
    sed \
      -e "s|__GITOPS_REPO_HTTPS_URL__|${gitops_url}|g" \
      -e "s|__GITOPS_TARGET_REVISION__|${revision}|g" \
      -e "s|__PLATFORM_RELEASE__|${platform_ver}|g" \
      "${f}" >"${f}.tmp" && mv "${f}.tmp" "${f}"
  done < <(find "${out}" -type f -print0 2>/dev/null)

  local vf="${out}/deploy/helm/control-plane/values.yaml"
  if [[ -f "${vf}" ]]; then
    if [[ "${gitops_backend}" == "gitea" ]]; then
      local gitea_api="http://${SPICE_GITEA_RELEASE}-http.${SPICE_GITEA_NAMESPACE}.svc.cluster.local:3000/api/v1"
      sed \
        -e "s|^  gitopsRepoOwner:.*|  gitopsRepoOwner: ${g_owner}|" \
        -e "s|^  gitopsRepoName:.*|  gitopsRepoName: ${g_name}|" \
        -e "s|^  gitopsRepoBranch:.*|  gitopsRepoBranch: ${revision}|" \
        -e "s|^  gitopsBackend:.*|  gitopsBackend: gitea|" \
        -e "s|^  gitopsGiteaApiBaseUrl:.*|  gitopsGiteaApiBaseUrl: ${gitea_api}|" \
        "${vf}" >"${vf}.tmp" && mv "${vf}.tmp" "${vf}"
      # Kind + in-cluster Gitea: do not pull the control-plane or MCP sidecar from GHCR. Images are built on the
      # host and loaded into Kind (see build_kind_lab_control_plane_images).
      perl -pe '
        s|^  repository: ghcr\.io/.+/control-plane-mcp$|  repository: spice-cp-mcp-local|;
        s|^  repository: ghcr\.io/.+/control-plane$|  repository: spice-cp-local|;
        s|^  tag: [0-9a-f]{40}$|  tag: lab|;
      ' "${vf}" >"${vf}.labimg.tmp" && mv "${vf}.labimg.tmp" "${vf}"
    else
      sed \
        -e "s|^  gitopsRepoOwner:.*|  gitopsRepoOwner: ${g_owner}|" \
        -e "s|^  gitopsRepoName:.*|  gitopsRepoName: ${g_name}|" \
        -e "s|^  gitopsRepoBranch:.*|  gitopsRepoBranch: ${revision}|" \
        "${vf}" >"${vf}.tmp" && mv "${vf}.tmp" "${vf}"
    fi
  fi

  if spice_feature_enabled prometheus || spice_feature_enabled superset; then
    patch_materialized_addon_credentials "${out}"
  fi

  printf '%s\n' "${platform_ver}" >"${out}/.spice-platform-version"
}

helm_bootstrap() {
  local root="$1"
  local b=""
  if [[ -d "${root}/bootstrap" ]]; then
    b="${root}/bootstrap"
  elif [[ -d "${root}/templates/gitops/bootstrap" ]]; then
    b="${root}/templates/gitops/bootstrap"
  elif [[ -d "${root}/gitops/bootstrap" ]]; then
    b="${root}/gitops/bootstrap"
  else
    die "no bootstrap Helm values under ${root} (expected bootstrap/ or templates/gitops/bootstrap/)"
  fi
  helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx 2>/dev/null || true
  helm repo add hashicorp https://helm.releases.hashicorp.com 2>/dev/null || true
  helm repo add external-secrets https://charts.external-secrets.io 2>/dev/null || true
  helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
  helm repo add bitnami https://charts.bitnami.com/bitnami 2>/dev/null || true
  helm repo update
  helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
    -n ingress-nginx --create-namespace \
    -f "${b}/values-ingress-nginx.yaml"
  install_valkey_standalone "${b}"
  helm upgrade --install vault hashicorp/vault -n vault --create-namespace \
    -f "${b}/values-vault.yaml"
  helm upgrade --install external-secrets external-secrets/external-secrets \
    -n external-secrets --create-namespace \
    -f "${b}/values-external-secrets.yaml"
  kubectl -n external-secrets wait --for=condition=available deploy --all --timeout=180s || true
}

vault_eso_token() {
  local token
  token="$(kubectl -n vault logs vault-0 2>/dev/null | sed -n 's/^Root Token: //p' | head -1)"
  [[ -n "${token}" ]] || die "could not read Vault root token from logs"
  kubectl -n external-secrets delete secret vault-eso-token --ignore-not-found
  kubectl -n external-secrets create secret generic vault-eso-token --from-literal=token="${token}"
  kubectl -n vault exec vault-0 -- vault secrets enable -path=secret kv-v2 2>/dev/null || true
}

# Each instances/<name>/vault-seed.json is written to secret/spice/instances/<name> (KV v2).
# ESO dataFrom.extract needs at least one key or the ExternalSecret stays Degraded.
vault_seed_spice_instances_from_gitops() {
  local gitops_dir="$1"
  local instances_dir="${gitops_dir}/instances"
  [[ -d "${instances_dir}" ]] || return 0

  if ! command -v python3 >/dev/null 2>&1; then
    echo "warn: python3 not found; seeding only spice/instances/example" >&2
    kubectl -n vault exec vault-0 -- vault kv put secret/spice/instances/example ENV_VAR=VALUE
    return 0
  fi

  local seed_file
  for seed_file in "${instances_dir}"/*/vault-seed.json; do
    [[ -f "${seed_file}" ]] || continue
    python3 - "${seed_file}" <<'PY'
import json
import pathlib
import subprocess
import sys

seed_file = sys.argv[1]
instance_name = pathlib.Path(seed_file).parent.name
vault_path = f"secret/spice/instances/{instance_name}"

with open(seed_file, encoding="utf-8") as f:
    data = json.load(f)
if not isinstance(data, dict):
    sys.stderr.write(f"warn: invalid vault-seed.json for {instance_name}\n")
    sys.exit(0)

pairs = [(k, v) for k, v in data.items() if isinstance(v, str)]
if not pairs:
    sys.stderr.write(f"warn: no string keys in vault-seed for {instance_name}\n")
    sys.exit(0)

args = ["vault", "kv", "put", vault_path] + [f"{k}={v}" for k, v in pairs]
subprocess.run(["kubectl", "-n", "vault", "exec", "vault-0", "--", *args], check=True)
print(f"Seeded Vault KV at spice/instances/{instance_name} ({len(pairs)} keys)")
PY
  done
}

# Control-plane Superset + related config (ESO → control-plane-env Secret).
vault_seed_control_plane() {
  if ! spice_feature_enabled superset; then
    echo "Skipping Vault Superset seed (Superset feature disabled)." >&2
    return 0
  fi
  ensure_lab_addon_password_files
  local spw
  spw="$(tr -d '\n\r' <"${STATE_DIR}/superset-lab.password" 2>/dev/null || true)"
  if [[ -z "${spw}" ]]; then
    echo "warn: skipping Vault seed for spice/control-plane (no superset-lab.password)" >&2
    return 0
  fi
  # In-cluster URL (see templates/gitops/addons/superset/values-kind.yaml).
  kubectl -n vault exec vault-0 -- vault kv put secret/spice/control-plane \
    SUPERSET_URL="http://superset.superset.svc.cluster.local:8088" \
    SUPERSET_USERNAME="admin" \
    SUPERSET_PASSWORD="${spw}"
}

apply_argo_repo_secret() {
  local gitops_url="$1"
  local pat="$2"
  local repo_user="${3:-git}"
  kubectl -n argocd delete secret github-gitops --ignore-not-found
  if [[ "${gitops_url}" == git://* ]]; then
    kubectl -n argocd create secret generic github-gitops \
      --from-literal=type=git \
      --from-literal=url="${gitops_url}"
    kubectl -n argocd label secret github-gitops argocd.argoproj.io/secret-type=repository --overwrite
    return 0
  fi
  if [[ "${gitops_url}" == http://* ]]; then
    kubectl -n argocd create secret generic github-gitops \
      --from-literal=type=git \
      --from-literal=url="${gitops_url}" \
      --from-literal=username="${repo_user}" \
      --from-literal=password="${pat}" \
      --from-literal=insecure=true
  else
    kubectl -n argocd create secret generic github-gitops \
      --from-literal=type=git \
      --from-literal=url="${gitops_url}" \
      --from-literal=username="${repo_user}" \
      --from-literal=password="${pat}"
  fi
  kubectl -n argocd label secret github-gitops argocd.argoproj.io/secret-type=repository --overwrite
}

argocd_install() {
  local root="$1"
  local b="${root}/bootstrap"
  helm upgrade --install argocd argo/argo-cd -n argocd --create-namespace \
    -f "${b}/values-argocd.yaml"
  kubectl -n argocd rollout status deploy/argocd-server --timeout=300s
}

# Decode and print the bootstrap admin password (the chart creates argocd-initial-admin-secret once).
emit_argocd_admin_credentials() {
  local pw="" pwfile="${STATE_DIR}/argocd-initial-admin-password.txt" i
  for i in $(seq 1 90); do
    if kubectl -n argocd get secret argocd-initial-admin-secret >/dev/null 2>&1; then
      pw="$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null || true)"
      if [[ -n "${pw}" ]]; then
        break
      fi
    fi
    sleep 2
  done
  if [[ -n "${pw}" ]]; then
    umask 077
    printf '%s\n' "${pw}" >"${pwfile}"
    chmod 600 "${pwfile}" 2>/dev/null || true
    echo "" >&2
    echo "Argo CD UI: http://argocd.127.0.0.1.nip.io/  — sign in as admin with the password below (same value in ${pwfile})." >&2
    echo "Argo CD admin password: ${pw}" >&2
    if [[ -f "${STATE_DIR}/install.env" ]]; then
      printf '\nARGOCD_INITIAL_ADMIN_PASSWORD_FILE=%s\n' "${pwfile}" >>"${STATE_DIR}/install.env"
    fi
  else
    :
  fi
}

apply_cluster_store() {
  local root="$1"
  kubectl apply -f "${root}/bootstrap/manifests/cluster-secret-store.yaml"
}

apply_root_app() {
  local root="$1"
  kubectl apply -f "${root}/bootstrap/manifests/application-root.yaml"
}

write_state() {
  mkdir -p "${STATE_DIR}"
  umask 077
  local gitea_ui=""
  [[ "${SPICE_LOCAL_CLUSTER_MODE:-0}" -eq 1 ]] && gitea_ui="$(gitea_web_url)"
  cat >"${STATE_DIR}/install.env" <<EOF
CLUSTER_NAME=${CLUSTER_NAME}
GITOPS_REPO_URL=${GITOPS_REPO_URL:-}
SPICE_LOCAL_CLUSTER_MODE=${SPICE_LOCAL_CLUSTER_MODE:-0}
SPICE_GIT_EFFECTIVE_REPO_URL=${SPICE_GIT_EFFECTIVE_REPO_URL:-}
GITEA_UI_URL=${gitea_ui}
PLATFORM_RELEASE=$(effective_release)
MATERIALIZED_PATH=${SPICE_GITOPS_DIR}
VALKEY_PRIMARY_ADDR=$(valkey_primary_tcp_addr)
VALKEY_PASSWORD_FILE=${STATE_DIR}/valkey-lab.password
GRAFANA_ADMIN_PASSWORD_FILE=${STATE_DIR}/grafana-lab.password
SUPERSET_ADMIN_PASSWORD_FILE=${STATE_DIR}/superset-lab.password
SUPERSET_SECRET_KEY_FILE=${STATE_DIR}/superset-lab.secret-key
GRAFANA_SUPERSET_CREDENTIALS_FILE=${STATE_DIR}/grafana-superset-credentials.txt
SPICE_FEATURES=$(spice_features_to_env)
EOF
  if [[ "${SPICE_LOCAL_CLUSTER_MODE:-0}" -eq 1 ]]; then
    {
      printf '\n# Gitea Actions (Kind lab)\n'
      printf 'GITEA_ACTIONS_NAMESPACE=%s\n' "${SPICE_GITEA_ACTIONS_NAMESPACE}"
      printf 'GITEA_ACTIONS_RELEASE=%s\n' "${SPICE_GITEA_ACTIONS_RELEASE}"
    } >>"${STATE_DIR}/install.env"
  fi
  if [[ "${SPICE_LOCAL_CLUSTER_MODE:-0}" -eq 1 ]]; then
    {
      printf '%s\n' "# Local lab — Gitea admin login and Argo Git credential (same password)."
      printf 'GITEA_UI_URL=%s\n' "${gitea_ui}"
      printf 'GITEA_USERNAME=%s\n' "${SPICE_GITEA_ADMIN_USER}"
      printf 'GITEA_PASSWORD=%s\n' "${GITOPS_PAT}"
      printf 'IN_CLUSTER_REPO_URL=%s\n' "${SPICE_GIT_EFFECTIVE_REPO_URL}"
      printf '\n# Valkey (Redis protocol) — shared cache; password in VALKEY_PASSWORD_FILE.\n'
      printf 'VALKEY_PRIMARY_ADDR=%s\n' "$(valkey_primary_tcp_addr)"
      printf 'VALKEY_PASSWORD_FILE=%s\n' "${STATE_DIR}/valkey-lab.password"
      printf '\n# Gitea Actions act_runner (Helm release in namespace %s).\n' "${SPICE_GITEA_ACTIONS_NAMESPACE}"
      printf 'GITEA_ACTIONS_NAMESPACE=%s\n' "${SPICE_GITEA_ACTIONS_NAMESPACE}"
      printf 'GITEA_ACTIONS_RELEASE=%s\n' "${SPICE_GITEA_ACTIONS_RELEASE}"
    } >"${STATE_DIR}/gitea-local-credentials.txt"
    chmod 600 "${STATE_DIR}/gitea-local-credentials.txt" 2>/dev/null || true
  else
    rm -f "${STATE_DIR}/gitea-local-credentials.txt" 2>/dev/null || true
  fi
}

do_uninstall() {
  ensure_spice_host_dependencies uninstall
  if ! confirm "Delete Kind cluster '${CLUSTER_NAME}'?"; then
    echo "Skipping cluster delete." >&2
    if [[ ! -t 0 ]] && [[ "${YES:-0}" != "1" ]]; then
      echo "Re-run with: install.sh --uninstall --all --yes" >&2
    fi
    exit 0
  fi
  kind delete cluster --name "${CLUSTER_NAME}" || true
  echo "Removed Kind cluster ${CLUSTER_NAME}."
}

semver_gt() {
  # Very small semver compare a > b for x.y.z only
  local a="$1" b="$2"
  IFS=. read -r a1 a2 a3 <<<"${a#v}"
  IFS=. read -r b1 b2 b3 <<<"${b#v}"
  [[ "${a1:-0}" -gt "${b1:-0}" ]] && return 0
  [[ "${a1:-0}" -lt "${b1:-0}" ]] && return 1
  [[ "${a2:-0}" -gt "${b2:-0}" ]] && return 0
  [[ "${a2:-0}" -lt "${b2:-0}" ]] && return 1
  [[ "${a3:-0}" -gt "${b3:-0}" ]]
}

do_upgrade() {
  ensure_spice_host_dependencies upgrade
  local current latest api
  current="0.0.0"
  if [[ -f "${STATE_DIR}/install.env" ]]; then
    # shellcheck source=/dev/null
    source "${STATE_DIR}/install.env"
    current="${PLATFORM_RELEASE:-0.0.0}"
  fi
  [[ "${SPICE_LOCAL_CLUSTER_MODE:-0}" != "1" ]] || die "--upgrade is for remote GitOps only (install once with --gitops-repo, or re-materialize manually)."
  [[ -n "${GITOPS_REPO_URL:-}" ]] || die "--upgrade needs a saved remote GitOps URL in ${STATE_DIR}/install.env (local-only installs do not support --upgrade)."
  api="https://api.github.com/repos/${SPICE_PRODUCT_REPO}/releases/latest"
  echo "Checking ${api}"
  latest="$(curl -fsSL ${GITHUB_TOKEN:+-H "Authorization: Bearer ${GITHUB_TOKEN}"} \
    -H "Accept: application/vnd.github+json" \
    "${api}" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
  latest="$(normalize_shell_token "${latest}")"
  [[ -n "${latest}" ]] || die "could not determine latest release (private product repo: provide GITHUB_TOKEN in CI or your shell)"
  echo "Current: ${current}  Latest: ${latest}"
  if ! semver_gt "${latest}" "${current}"; then
    echo "No upgrade needed (or semver compare inconclusive)."
    exit 0
  fi
  local out="${MATERIALIZED_PATH:-${SPICE_GITOPS_DIR:-$(pwd)/spice-gitops-work}}"
  if ! confirm "Re-materialize GitOps tree at ${out} using ${latest}?"; then
    echo "Upgrade cancelled." >&2
    exit 0
  fi
  spice_load_features_from_install_env
  if [[ "${SPICE_FEATURES_CLI_CONFIGURED}" != "1" ]]; then
    spice_feature_init_defaults 0
  fi
  spice_apply_feature_dependencies
  local bundle
  bundle="$(SPICE_RELEASE="${latest}" resolve_bundle_root)"
  materialize_tree "${bundle}" "${out}" "${GITOPS_REPO_URL}" "${GITOPS_TARGET_REVISION:-main}" "${latest}"
  echo "Upgraded materialized tree at ${out}. Commit/push to your GitOps repo, then sync Argo."
}

GITOPS_REPO_URL="${GITOPS_REPO_URL:-}"
GITOPS_TARGET_REVISION="${GITOPS_TARGET_REVISION:-main}"
MODE="install"
MATERIALIZE_ONLY=""
YES="${YES:-0}"
FEATURES_ALLOW=""
FEATURES_DENY=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --gitops-repo) GITOPS_REPO_URL="$2"; shift 2 ;;
    --gitops-pat) GITOPS_PAT="$2"; shift 2 ;;
    --revision) GITOPS_TARGET_REVISION="$2"; shift 2 ;;
    --release) SPICE_RELEASE="$2"; shift 2 ;;
    --materialize) MATERIALIZE_ONLY="$2"; shift 2 ;;
    --upgrade) MODE="upgrade"; shift ;;
    --uninstall) MODE="uninstall"; shift ;;
    --all) UNINSTALL_ALL=1; shift ;;
    --yes) YES=1; shift ;;
    --features) FEATURES_ALLOW="$2"; shift 2 ;;
    --without-features) FEATURES_DENY="$2"; shift 2 ;;
    *) die "unknown arg: $1" ;;
  esac
done

GITOPS_REPO_URL="$(normalize_shell_token "${GITOPS_REPO_URL}")"
GITOPS_TARGET_REVISION="$(normalize_shell_token "${GITOPS_TARGET_REVISION}")"
if [[ -n "${SPICE_RELEASE:-}" ]]; then
  SPICE_RELEASE="$(normalize_shell_token "${SPICE_RELEASE}")"
fi

spice_ensure_curl
spice_resolve_default_release_tag_if_piped
if [[ -n "${SPICE_PACKAGED_RELEASE:-}" ]]; then
  SPICE_PACKAGED_RELEASE="$(normalize_shell_token "${SPICE_PACKAGED_RELEASE}")"
fi
unset _rel 2>/dev/null || true

if [[ "${MODE}" == "uninstall" ]]; then
  do_uninstall
  exit 0
fi

if [[ -n "${MATERIALIZE_ONLY}" ]]; then
  mat_gitops_backend="${SPICE_GITOPS_BACKEND:-github}"
  if [[ "${SPICE_MATERIALIZE_GITEA:-0}" == "1" ]] || [[ "${mat_gitops_backend}" == "gitea" ]]; then
    mat_gitops_backend="gitea"
    if [[ -z "${GITOPS_REPO_URL}" ]]; then
      GITOPS_REPO_URL="$(gitea_internal_http_clone_url)"
    fi
  elif [[ -z "${GITOPS_REPO_URL}" ]]; then
    GITOPS_REPO_URL="https://github.com/local/spice-platform-local.git"
  elif [[ -t 0 ]]; then
    echo "GitOps URL is set to: ${GITOPS_REPO_URL}" >&2
    read -r -p "Press Enter to keep it, or paste a different HTTPS .git URL: " _u || true
    if [[ -n "${_u}" ]]; then
      GITOPS_REPO_URL="$(normalize_shell_token "${_u}")"
    fi
  fi
  [[ "${GITOPS_REPO_URL}" == *.git ]] || GITOPS_REPO_URL="${GITOPS_REPO_URL%.}.git"
  ensure_spice_host_dependencies materialize
  mat_local_lab=0
  [[ "${mat_gitops_backend}" == "gitea" ]] && mat_local_lab=1
  spice_select_features "${mat_local_lab}"
  bundle="$(resolve_bundle_root)"
  ver="$(effective_release)"
  materialize_tree "${bundle}" "${MATERIALIZE_ONLY}" "${GITOPS_REPO_URL}" "${GITOPS_TARGET_REVISION}" "${ver}" "${mat_gitops_backend}"
  echo "Materialized GitOps tree at ${MATERIALIZE_ONLY}"
  exit 0
fi

if [[ ! -t 0 ]] && [[ "${YES:-0}" == "0" ]]; then
  YES=1
fi

if [[ "${MODE}" == "upgrade" ]]; then
  do_upgrade
  exit 0
fi

if [[ -t 0 ]] && [[ -z "${GITOPS_REPO_URL}" ]] && [[ "${SPICE_DISABLE_LOCAL_GITOPS:-0}" != "1" ]]; then
  read -r -p "GitOps repository HTTPS URL (.git), optional: " GITOPS_REPO_URL || true
  GITOPS_REPO_URL="$(normalize_shell_token "${GITOPS_REPO_URL}")"
fi

SPICE_LOCAL_CLUSTER_MODE=0
if [[ -z "${GITOPS_REPO_URL}" ]] && [[ "${SPICE_DISABLE_LOCAL_GITOPS:-0}" != "1" ]]; then
  SPICE_LOCAL_CLUSTER_MODE=1
fi

if [[ "${SPICE_LOCAL_CLUSTER_MODE}" -eq 1 ]]; then
  SPICE_GITOPS_DIR="${SPICE_GITOPS_DIR:-${STATE_DIR}/materialized}"
  mkdir -p "${SPICE_GITOPS_DIR}"
  SPICE_GITOPS_DIR="$(cd "${SPICE_GITOPS_DIR}" && pwd)"
  GITOPS_PAT="$(normalize_shell_token "${GITOPS_PAT:-}")"
  if [[ -z "${GITOPS_PAT}" ]]; then
    GITOPS_PAT="$(openssl rand -hex 16)"
  fi
  echo "Local-only lab: Gitea in Kind (UI $(gitea_web_url)); Argo will clone the GitOps tree over HTTP inside the cluster." >&2
else
  [[ -n "${GITOPS_REPO_URL}" ]] || die "Pass --gitops-repo https://github.com/org/repo.git for remote mode, or run interactively and leave the URL blank for a local-only lab."
  [[ "${GITOPS_REPO_URL}" == *.git ]] || GITOPS_REPO_URL="${GITOPS_REPO_URL%.}.git"
  SPICE_GITOPS_DIR="${SPICE_GITOPS_DIR:-$(pwd)/spice-gitops-work}"
  GITOPS_PAT="${GITOPS_PAT:-${GITHUB_TOKEN:-}}"
  if [[ -t 0 ]] && [[ -z "${GITOPS_PAT}" ]]; then
    read -r -s -p "Git PAT for Argo + control plane (Enter to skip if the GitOps repo is public): " GITOPS_PAT || true
    echo "" >&2
  fi
  GITOPS_PAT="$(normalize_shell_token "${GITOPS_PAT:-}")"
  SPICE_GIT_EFFECTIVE_REPO_URL="${GITOPS_REPO_URL}"
  echo "Using remote GitOps repository ${GITOPS_REPO_URL}" >&2
fi

[[ "${SPICE_DISABLE_LOCAL_GITOPS:-0}" != "1" ]] || [[ -n "${GITOPS_REPO_URL}" ]] || die "SPICE_DISABLE_LOCAL_GITOPS=1 requires --gitops-repo with an HTTPS .git URL."

ensure_spice_host_dependencies full "${SPICE_LOCAL_CLUSTER_MODE}"
spice_select_features "${SPICE_LOCAL_CLUSTER_MODE}"
bundle="$(resolve_bundle_root)"
ver="$(effective_release)"

KIND_CFG="${bundle}/hack/kind-config.yaml"
[[ -f "${KIND_CFG}" ]] || KIND_CFG="${REPO_ROOT}/hack/kind-config.yaml"

if [[ "${SPICE_LOCAL_CLUSTER_MODE}" -eq 1 ]]; then
  if ! kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}\$"; then
    kind create cluster --name "${CLUSTER_NAME}" --config "${KIND_CFG}"
  fi
  kubectl config use-context "kind-${CLUSTER_NAME}"

  helm_bootstrap "${bundle}"

  install_gitea_chart "${bundle}" "${GITOPS_PAT}"

  SPICE_GITEA_PF_PORT="${SPICE_GITEA_PF_PORT:-3333}"
  kubectl -n "${SPICE_GITEA_NAMESPACE}" port-forward "svc/${SPICE_GITEA_RELEASE}-http" "${SPICE_GITEA_PF_PORT}:3000" >/dev/null 2>&1 &
  GITEA_PF_PID=$!
  cleanup_gitea_pf() { kill "${GITEA_PF_PID:-0}" 2>/dev/null || true; }
  trap cleanup_gitea_pf EXIT INT TERM

  gitea_wait_api "${SPICE_GITEA_PF_PORT}"
  gitea_create_empty_repo "${GITOPS_PAT}" "${SPICE_GITEA_PF_PORT}"

  SPICE_GIT_EFFECTIVE_REPO_URL="$(gitea_internal_http_clone_url)"

  materialize_tree "${bundle}" "${SPICE_GITOPS_DIR}" "${SPICE_GIT_EFFECTIVE_REPO_URL}" "${GITOPS_TARGET_REVISION}" "${ver}" gitea
  gitea_push_materialized_workdir "${SPICE_GITOPS_DIR}" "${GITOPS_PAT}" "${SPICE_GITEA_PF_PORT}"
  install_gitea_actions_runner "${bundle}" "${GITOPS_PAT}" "${SPICE_GITEA_PF_PORT}"

  cleanup_gitea_pf
  trap - EXIT INT TERM
  wait "${GITEA_PF_PID}" 2>/dev/null || true
else
  materialize_tree "${bundle}" "${SPICE_GITOPS_DIR}" "${SPICE_GIT_EFFECTIVE_REPO_URL}" "${GITOPS_TARGET_REVISION}" "${ver}"
  if ! kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}\$"; then
    kind create cluster --name "${CLUSTER_NAME}" --config "${KIND_CFG}"
  fi
  kubectl config use-context "kind-${CLUSTER_NAME}"
  helm_bootstrap "${SPICE_GITOPS_DIR}"
fi

if [[ "${SPICE_LOCAL_CLUSTER_MODE}" -eq 1 ]]; then
  build_kind_lab_control_plane_images "${bundle}" "${CLUSTER_NAME}"
fi

kubectl -n vault wait --for=condition=ready pod/vault-0 --timeout=180s
vault_eso_token
vault_seed_spice_instances_from_gitops "${SPICE_GITOPS_DIR}"
if spice_feature_enabled prometheus || spice_feature_enabled superset; then
  ensure_lab_addon_password_files
fi
vault_seed_control_plane
apply_cluster_store "${SPICE_GITOPS_DIR}"
argocd_install "${SPICE_GITOPS_DIR}"

argo_repo_user=git
[[ "${SPICE_GIT_EFFECTIVE_REPO_URL}" == http://* ]] && argo_repo_user="${SPICE_GITEA_ADMIN_USER}"
apply_argo_repo_secret "${SPICE_GIT_EFFECTIVE_REPO_URL}" "${GITOPS_PAT}" "${argo_repo_user}"
apply_root_app "${SPICE_GITOPS_DIR}"

kubectl create namespace control-plane --dry-run=client -o yaml | kubectl apply -f -
vt="$(kubectl -n vault logs vault-0 2>/dev/null | sed -n 's/^Root Token: //p' | head -1)"
kubectl -n control-plane create secret generic control-plane-secrets \
  --from-literal=gitops_token="${GITOPS_PAT}" \
  --from-literal=vault_token="${vt}" \
  --from-literal=admin_api_key="$(openssl rand -hex 24)" \
  --dry-run=client -o yaml | kubectl apply -f -

write_state
emit_argocd_admin_credentials
echo "Bootstrap complete. GitOps materialized at ${SPICE_GITOPS_DIR}"
if [[ "${SPICE_LOCAL_CLUSTER_MODE}" -eq 1 ]]; then
  echo "Local-only: browse Gitea at $(gitea_web_url). Credentials: ${STATE_DIR}/gitea-local-credentials.txt (mode 600)." >&2
  spice_feature_enabled gitea_actions && echo "Gitea Actions runner: namespace ${SPICE_GITEA_ACTIONS_NAMESPACE} (Helm release ${SPICE_GITEA_ACTIONS_RELEASE})." >&2
  echo "The control plane uses Gitea REST (GITOPS_BACKEND=gitea) to list and edit instances in-repo." >&2
else
  echo "Push ${SPICE_GITOPS_DIR} to ${GITOPS_REPO_URL} if not already connected, then sync Argo application platform-gitops."
fi
if spice_feature_enabled prometheus || spice_feature_enabled superset; then
  echo "Grafana/Superset lab credentials (if enabled): ${STATE_DIR}/grafana-superset-credentials.txt" >&2
fi
if spice_feature_enabled prometheus; then
  echo "Grafana: http://grafana.127.0.0.1.nip.io/" >&2
fi
if spice_feature_enabled superset; then
  echo "Superset: http://superset.127.0.0.1.nip.io/" >&2
fi
if spice_feature_enabled opencost; then
  echo "OpenCost UI: http://opencost.127.0.0.1.nip.io/ (see addons/opencost README)" >&2
fi
