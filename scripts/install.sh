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
  local ver=()
  [[ -n "${GITEA_CHART_VERSION:-}" ]] && ver=(--version "${GITEA_CHART_VERSION}")
  helm upgrade --install "${SPICE_GITEA_RELEASE}" gitea-charts/gitea \
    -n "${SPICE_GITEA_NAMESPACE}" --create-namespace \
    "${ver[@]}" \
    -f "${vf}" -f "${secretf}"
  kubectl -n "${SPICE_GITEA_NAMESPACE}" rollout status "deploy/${SPICE_GITEA_RELEASE}" --timeout=600s
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

gitea_push_materialized_workdir() {
  local work="$1"
  local admin_pass="$2"
  local port="$3"
  command -v git >/dev/null 2>&1 || die "local Gitea mode requires git in PATH"
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

# Piped install without an embedded tag: default to latest GitHub Release of the product repo (avoids 0.0.0-dev).
if [[ "${INSTALL_FROM_PIPE}" -eq 1 ]] && [[ -z "${SPICE_PACKAGED_RELEASE}" ]] && [[ -z "${SPICE_RELEASE:-}" ]]; then
  _rel="$(fetch_latest_github_release_tag)" || true
  if [[ -n "${_rel}" ]]; then
    SPICE_PACKAGED_RELEASE="$(normalize_shell_token "${_rel}")"
  fi
fi
if [[ -n "${SPICE_PACKAGED_RELEASE:-}" ]]; then
  SPICE_PACKAGED_RELEASE="$(normalize_shell_token "${SPICE_PACKAGED_RELEASE}")"
fi
unset _rel 2>/dev/null || true

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
  --yes                 Answer yes to confirmation prompts (recommended for uninstall when piping)

Defaults:
  Unset GITOPS_REPO_URL → local Kind lab: Gitea in-cluster (HTTP for Argo), ingress UI at
  http://gitea.127.0.0.1.nip.io/ ; materialized tree is pushed once to Gitea (admin password = Argo repo secret).
  Piped installs (no TTY) default --yes for bootstrap steps so you are not asked to type confirmations.

Optional overrides (environment):
  SPICE_RELEASE, SPICE_GITOPS_DIR, SPICE_PRODUCT_REPO, CLUSTER_NAME, STATE_DIR
  GITOPS_REPO_URL, GITOPS_PAT, GITOPS_TARGET_REVISION, GITHUB_TOKEN
  SPICE_GITEA_NAMESPACE, SPICE_GITEA_RELEASE, SPICE_GITEA_REPO_NAME, SPICE_GITEA_ADMIN_USER, SPICE_GITEA_INGRESS_HOST
  SPICE_DISABLE_LOCAL_GITOPS=1  Require --gitops-repo (fail if URL empty)

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

confirm() {
  [[ "${YES:-0}" == "1" ]] && return 0
  if [[ ! -t 0 ]] || [[ "${NONINTERACTIVE:-0}" == "1" ]] || [[ "${CI:-}" == "1" ]] || [[ "${CI:-}" == "true" ]]; then
    return 1
  fi
  local ans
  read -r -p "$* [y/N] " ans || true
  [[ "${ans}" == "y" || "${ans}" == "Y" ]]
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
  local out="$2"
  local gitops_url="$3"
  local revision="$4"
  local platform_ver="$5"

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

  local app_insecure="" appset_git="" appset_src=""
  if [[ "${gitops_url}" == http://* ]]; then
    app_insecure='    insecure: true'
    appset_git='        insecure: true'
    appset_src='        insecure: true'
  fi

  cp -R "${tpl_dir}/apps" "${out}/apps"
  cp -R "${tpl_dir}/bootstrap" "${out}/bootstrap"
  [[ -d "${tpl_dir}/addons" ]] && cp -R "${tpl_dir}/addons" "${out}/addons" || true
  [[ -d "${tpl_dir}/cost" ]] && cp -R "${tpl_dir}/cost" "${out}/cost" || true
  cp -R "${bundle_root}/charts" "${out}/charts"
  cp -R "${bundle_root}/deploy" "${out}/deploy"
  mkdir -p "${out}/instances"
  cp -R "${bundle_root}/examples/instances/"* "${out}/instances/"
  cp "${tpl_dir}/platform-version.yaml" "${out}/platform-version.yaml"

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
      -e "s|__GITOPS_APP_INSECURE__|${app_insecure}|g" \
      -e "s|__GITOPS_APPSET_GIT_INSECURE__|${appset_git}|g" \
      -e "s|__GITOPS_APPSET_SRC_INSECURE__|${appset_src}|g" \
      "${f}" >"${f}.tmp" && mv "${f}.tmp" "${f}"
  done < <(find "${out}" -type f -print0 2>/dev/null)

  local vf="${out}/deploy/helm/control-plane/values.yaml"
  if [[ -f "${vf}" ]]; then
    sed \
      -e "s|^  gitopsRepoOwner:.*|  gitopsRepoOwner: ${g_owner}|" \
      -e "s|^  gitopsRepoName:.*|  gitopsRepoName: ${g_name}|" \
      -e "s|^  gitopsRepoBranch:.*|  gitopsRepoBranch: ${revision}|" \
      "${vf}" >"${vf}.tmp" && mv "${vf}.tmp" "${vf}"
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
  helm repo update
  helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
    -n ingress-nginx --create-namespace \
    -f "${b}/values-ingress-nginx.yaml"
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
  local insecure=()
  if [[ "${gitops_url}" == http://* ]]; then
    insecure=(--from-literal=insecure=true)
  fi
  kubectl -n argocd create secret generic github-gitops \
    --from-literal=type=git \
    --from-literal=url="${gitops_url}" \
    --from-literal=username="${repo_user}" \
    --from-literal=password="${pat}" \
    "${insecure[@]}"
  kubectl -n argocd label secret github-gitops argocd.argoproj.io/secret-type=repository --overwrite
}

argocd_install() {
  local root="$1"
  local b="${root}/bootstrap"
  helm upgrade --install argocd argo/argo-cd -n argocd --create-namespace \
    -f "${b}/values-argocd.yaml"
  kubectl -n argocd rollout status deploy/argocd-server --timeout=300s
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
EOF
  if [[ "${SPICE_LOCAL_CLUSTER_MODE:-0}" -eq 1 ]]; then
    {
      printf '%s\n' "# Local lab — Gitea admin login and Argo Git credential (same password)."
      printf 'GITEA_UI_URL=%s\n' "${gitea_ui}"
      printf 'GITEA_USERNAME=%s\n' "${SPICE_GITEA_ADMIN_USER}"
      printf 'GITEA_PASSWORD=%s\n' "${GITOPS_PAT}"
      printf 'IN_CLUSTER_REPO_URL=%s\n' "${SPICE_GIT_EFFECTIVE_REPO_URL}"
    } >"${STATE_DIR}/gitea-local-credentials.txt"
    chmod 600 "${STATE_DIR}/gitea-local-credentials.txt" 2>/dev/null || true
  else
    rm -f "${STATE_DIR}/gitea-local-credentials.txt" 2>/dev/null || true
  fi
}

do_uninstall() {
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
    *) die "unknown arg: $1" ;;
  esac
done

GITOPS_REPO_URL="$(normalize_shell_token "${GITOPS_REPO_URL}")"
GITOPS_TARGET_REVISION="$(normalize_shell_token "${GITOPS_TARGET_REVISION}")"
if [[ -n "${SPICE_RELEASE:-}" ]]; then
  SPICE_RELEASE="$(normalize_shell_token "${SPICE_RELEASE}")"
fi

if [[ "${MODE}" == "uninstall" ]]; then
  do_uninstall
  exit 0
fi

if [[ -n "${MATERIALIZE_ONLY}" ]]; then
  if [[ -z "${GITOPS_REPO_URL}" ]]; then
    GITOPS_REPO_URL="https://github.com/local/spice-platform-local.git"
  elif [[ -t 0 ]]; then
    echo "GitOps URL is set to: ${GITOPS_REPO_URL}" >&2
    read -r -p "Press Enter to keep it, or paste a different HTTPS .git URL: " _u || true
    if [[ -n "${_u}" ]]; then
      GITOPS_REPO_URL="$(normalize_shell_token "${_u}")"
    fi
  fi
  [[ "${GITOPS_REPO_URL}" == *.git ]] || GITOPS_REPO_URL="${GITOPS_REPO_URL%.}.git"
  bundle="$(resolve_bundle_root)"
  ver="$(effective_release)"
  materialize_tree "${bundle}" "${MATERIALIZE_ONLY}" "${GITOPS_REPO_URL}" "${GITOPS_TARGET_REVISION}" "${ver}"
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
  echo "Tip: leave blank for a local-only Kind lab (no GitHub GitOps repository)." >&2
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
  if [[ -z "${GITOPS_PAT}" ]]; then
    echo "warning: no Git PAT; Argo needs credentials if the GitOps repository is private." >&2
  fi
  SPICE_GIT_EFFECTIVE_REPO_URL="${GITOPS_REPO_URL}"
  echo "Using remote GitOps repository ${GITOPS_REPO_URL}" >&2
fi

[[ "${SPICE_DISABLE_LOCAL_GITOPS:-0}" != "1" ]] || [[ -n "${GITOPS_REPO_URL}" ]] || die "SPICE_DISABLE_LOCAL_GITOPS=1 requires --gitops-repo with an HTTPS .git URL."

bundle="$(resolve_bundle_root)"
ver="$(effective_release)"

KIND_CFG="${bundle}/hack/kind-config.yaml"
[[ -f "${KIND_CFG}" ]] || KIND_CFG="${REPO_ROOT}/hack/kind-config.yaml"

if [[ "${SPICE_LOCAL_CLUSTER_MODE}" -eq 1 ]]; then
  if ! kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}\$"; then
    kind create cluster --name "${CLUSTER_NAME}" --config "${KIND_CFG}"
  else
    echo "warning: Kind cluster '${CLUSTER_NAME}' already exists; continuing (recreate the cluster if Gitea or ingress drift)." >&2
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

  materialize_tree "${bundle}" "${SPICE_GITOPS_DIR}" "${SPICE_GIT_EFFECTIVE_REPO_URL}" "${GITOPS_TARGET_REVISION}" "${ver}"
  gitea_push_materialized_workdir "${SPICE_GITOPS_DIR}" "${GITOPS_PAT}" "${SPICE_GITEA_PF_PORT}"

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

kubectl -n vault wait --for=condition=ready pod/vault-0 --timeout=180s
vault_eso_token
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
echo "Bootstrap complete. GitOps materialized at ${SPICE_GITOPS_DIR}"
if [[ "${SPICE_LOCAL_CLUSTER_MODE}" -eq 1 ]]; then
  echo "Local-only: browse Gitea at $(gitea_web_url). Credentials: ${STATE_DIR}/gitea-local-credentials.txt (mode 600). Control plane GitHub features still need a real GitHub PAT if you use them." >&2
else
  echo "Push ${SPICE_GITOPS_DIR} to ${GITOPS_REPO_URL} if not already connected, then sync Argo application platform-gitops."
fi
echo "Argo admin password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
