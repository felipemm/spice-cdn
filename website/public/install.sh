#!/usr/bin/env bash
# Spice platform local installer (Kind + GitOps bootstrap).
# Pinned installs use a GitHub Release tarball; dev mode uses this git checkout when SPICE_RELEASE=0.0.0-dev.
set -euo pipefail

# Injected when copied into a release tarball (see .github/workflows/release.yml).
SPICE_PACKAGED_RELEASE="v0.1.0"

SPICE_PRODUCT_REPO="${SPICE_PRODUCT_REPO:-felipemm/spice-cdn}"
SPICE_GITOPS_DIR="${SPICE_GITOPS_DIR:-}"
CLUSTER_NAME="${CLUSTER_NAME:-spice-gitops}"
STATE_DIR="${STATE_DIR:-"$HOME/.spice-platform"}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

usage() {
  cat <<'USAGE'
Usage:
  install.sh [options]

Options:
  --gitops-repo URL     HTTPS Git URL of your GitOps repo (must end with .git), e.g. https://github.com/org/spice-gitops.git
  --revision BRANCH     Argo targetRevision / git revision (default: main)
  --release VERSION     Platform version tag (default: packaged release or 0.0.0-dev for local tree)
  --materialize DIR     Only render templates into DIR and exit (no cluster changes)
  --upgrade             Check GitHub for newer release than state file and re-materialize (see docs)
  --uninstall --all     kind delete cluster (CLUSTER_NAME)
  --yes                 Skip confirmation prompts (dangerous with --uninstall)

Env:
  SPICE_RELEASE         Same as --release
  SPICE_GITOPS_DIR      Output / materialized GitOps tree (default: ./spice-gitops-work)
  SPICE_PRODUCT_REPO     GitHub owner/repo for downloads (default: felipemm/spice-cdn)
  GITHUB_TOKEN          Optional; for upgrade API or private release assets
USAGE
}

die() {
  echo "error: $*" >&2
  exit 1
}

prompt() {
  local var="$1"
  local msg="$2"
  if [[ -n "${!var:-}" ]]; then
    return 0
  fi
  local val
  read -r -p "${msg} " val || true
  printf -v "${var}" '%s' "${val}"
}

confirm() {
  [[ "${YES:-0}" == "1" ]] && return 0
  local ans
  read -r -p "$* [y/N] " ans || true
  [[ "${ans}" == "y" || "${ans}" == "Y" ]]
}

effective_release() {
  local v="${SPICE_RELEASE:-}"
  if [[ -z "${v}" && -n "${SPICE_PACKAGED_RELEASE}" ]]; then
    v="${SPICE_PACKAGED_RELEASE}"
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
  echo "Downloading ${url}"
  if ! curl -fsSL -o "${dest}/bundle.tgz" "${url}"; then
    die "failed to download release ${ver}. Set SPICE_PRODUCT_REPO or create a GitHub Release with spice-platform-${ver}.tar.gz"
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
    die "Release ${ver} requires a git checkout with templates/gitops (clone the product repo) or set SPICE_RELEASE to a published tag."
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

  local go="${gitops_url#https://github.com/}"
  go="${go%.git}"
  local g_owner="${go%%/*}"
  local g_name="${go##*/}"

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
  local b="${root}/bootstrap"
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
  kubectl -n argocd delete secret github-gitops --ignore-not-found
  kubectl -n argocd create secret generic github-gitops \
    --from-literal=type=git \
    --from-literal=url="${gitops_url}" \
    --from-literal=username=git \
    --from-literal=password="${pat}"
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
  cat >"${STATE_DIR}/install.env" <<EOF
CLUSTER_NAME=${CLUSTER_NAME}
GITOPS_REPO_URL=${GITOPS_REPO_URL}
PLATFORM_RELEASE=$(effective_release)
MATERIALIZED_PATH=${SPICE_GITOPS_DIR}
EOF
}

do_uninstall() {
  if ! confirm "Delete Kind cluster '${CLUSTER_NAME}'?"; then
    echo "Aborted."
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
  api="https://api.github.com/repos/${SPICE_PRODUCT_REPO}/releases/latest"
  echo "Checking ${api}"
  latest="$(curl -fsSL ${GITHUB_TOKEN:+-H "Authorization: Bearer ${GITHUB_TOKEN}"} "${api}" | sed -n 's/^  "tag_name": "\(.*\)"/\1/p' | head -1)"
  [[ -n "${latest}" ]] || die "could not determine latest release (set GITHUB_TOKEN for private repos)"
  echo "Current: ${current}  Latest: ${latest}"
  if ! semver_gt "${latest}" "${current}"; then
    echo "No upgrade needed (or semver compare inconclusive)."
    exit 0
  fi
  if ! confirm "Re-materialize GitOps tree at SPICE_GITOPS_DIR using ${latest}?"; then
    exit 0
  fi
  local out="${SPICE_GITOPS_DIR:-$(pwd)/spice-gitops-work}"
  [[ -n "${GITOPS_REPO_URL:-}" ]] || die "Set GITOPS_REPO_URL for --upgrade"
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

if [[ "${MODE}" == "uninstall" ]]; then
  do_uninstall
  exit 0
fi

if [[ -n "${MATERIALIZE_ONLY}" ]]; then
  prompt GITOPS_REPO_URL "GitOps repo HTTPS URL (.git):"
  [[ "${GITOPS_REPO_URL}" == *.git ]] || GITOPS_REPO_URL="${GITOPS_REPO_URL%.}.git"
  bundle="$(resolve_bundle_root)"
  ver="$(effective_release)"
  materialize_tree "${bundle}" "${MATERIALIZE_ONLY}" "${GITOPS_REPO_URL}" "${GITOPS_TARGET_REVISION}" "${ver}"
  echo "Materialized GitOps tree at ${MATERIALIZE_ONLY}"
  exit 0
fi

if [[ "${MODE}" == "upgrade" ]]; then
  do_upgrade
  exit 0
fi

prompt GITOPS_REPO_URL "GitOps repo HTTPS URL (must end with .git):"
[[ -n "${GITOPS_REPO_URL}" ]] || die "GITOPS_REPO_URL required"
[[ "${GITOPS_REPO_URL}" == *.git ]] || GITOPS_REPO_URL="${GITOPS_REPO_URL%.}.git"

GITOPS_PAT="${GITOPS_PAT:-${GITHUB_TOKEN:-}}"

prompt GITOPS_PAT "Git PAT for Argo + control plane (repo contents:write on GitOps repo) [env: GITOPS_PAT]:"
[[ -n "${GITOPS_PAT:-}" ]] || die "GITOPS_PAT required for bootstrap"

SPICE_GITOPS_DIR="${SPICE_GITOPS_DIR:-$(pwd)/spice-gitops-work}"
bundle="$(resolve_bundle_root)"
ver="$(effective_release)"
materialize_tree "${bundle}" "${SPICE_GITOPS_DIR}" "${GITOPS_REPO_URL}" "${GITOPS_TARGET_REVISION}" "${ver}"

KIND_CFG="${bundle}/hack/kind-config.yaml"
[[ -f "${KIND_CFG}" ]] || KIND_CFG="${REPO_ROOT}/hack/kind-config.yaml"
if ! kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}\$"; then
  kind create cluster --name "${CLUSTER_NAME}" --config "${KIND_CFG}"
fi
kubectl config use-context "kind-${CLUSTER_NAME}"

helm_bootstrap "${SPICE_GITOPS_DIR}"
kubectl -n vault wait --for=condition=ready pod/vault-0 --timeout=180s
vault_eso_token
apply_cluster_store "${SPICE_GITOPS_DIR}"
argocd_install "${SPICE_GITOPS_DIR}"
apply_argo_repo_secret "${GITOPS_REPO_URL}" "${GITOPS_PAT}"
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
echo "Push ${SPICE_GITOPS_DIR} to ${GITOPS_REPO_URL} if not already connected, then sync Argo application platform-gitops."
echo "Argo admin password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
