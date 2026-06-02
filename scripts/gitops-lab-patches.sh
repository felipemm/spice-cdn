# Kind lab patches for materialized GitOps trees (sourced by install.sh and push-gitea-gitops.sh).
# Requires: STATE_DIR (default ~/.spice-platform)

spice_patch_feature_enabled() {
  local id="$1"
  if declare -F spice_feature_enabled >/dev/null 2>&1; then
    spice_feature_enabled "${id}"
  else
    return 0
  fi
}

ensure_lab_addon_password_files() {
  umask 077
  mkdir -p "${STATE_DIR}"
  local gf="${STATE_DIR}/grafana-lab.password"
  local sf="${STATE_DIR}/superset-lab.password"
  local sk="${STATE_DIR}/superset-lab.secret-key"
  if spice_patch_feature_enabled prometheus && [[ ! -s "${gf}" ]]; then
    openssl rand -hex 16 >"${gf}"
  fi
  if spice_patch_feature_enabled superset && [[ ! -s "${sf}" ]]; then
    openssl rand -hex 16 >"${sf}"
  fi
  if spice_patch_feature_enabled superset && [[ ! -s "${sk}" ]]; then
    openssl rand -hex 32 >"${sk}"
  fi
  chmod 600 "${gf}" "${sf}" "${sk}" 2>/dev/null || true
}

write_grafana_superset_credentials_summary() {
  umask 077
  local gpw="" spw="" ssk=""
  local outf="${STATE_DIR}/grafana-superset-credentials.txt"
  if spice_patch_feature_enabled prometheus && [[ -s "${STATE_DIR}/grafana-lab.password" ]]; then
    gpw="$(tr -d '\n\r' <"${STATE_DIR}/grafana-lab.password")"
  fi
  if spice_patch_feature_enabled superset && [[ -s "${STATE_DIR}/superset-lab.password" ]]; then
    spw="$(tr -d '\n\r' <"${STATE_DIR}/superset-lab.password")"
    ssk="$(tr -d '\n\r' <"${STATE_DIR}/superset-lab.secret-key")"
  fi
  if [[ -z "${gpw}${spw}" ]]; then
    return 0
  fi
  {
    if spice_patch_feature_enabled prometheus && [[ -n "${gpw}" ]]; then
      cat <<EOF
# Grafana (kube-prometheus-stack) — Kind lab defaults (ingress + nip.io).
# Helm values are patched into the materialized GitOps apps from the password files below.

GRAFANA_URL=http://grafana.127.0.0.1.nip.io/
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=${gpw}
GRAFANA_ADMIN_PASSWORD_FILE=${STATE_DIR}/grafana-lab.password

EOF
    fi
    if spice_patch_feature_enabled superset && [[ -n "${spw}" ]]; then
      cat <<EOF
SUPERSET_URL=http://superset.127.0.0.1.nip.io/
SUPERSET_ADMIN_USERNAME=admin
SUPERSET_ADMIN_PASSWORD=${spw}
SUPERSET_ADMIN_PASSWORD_FILE=${STATE_DIR}/superset-lab.password
SUPERSET_SECRET_KEY=${ssk}
SUPERSET_SECRET_KEY_FILE=${STATE_DIR}/superset-lab.secret-key

# Control plane reads Superset config from Vault KV (path spice/control-plane), synced by ESO to Secret control-plane-env.
# Keys: SUPERSET_URL, SUPERSET_USERNAME, SUPERSET_PASSWORD (install.sh seeds Vault; Helm externalSecret.syncSuperset: true).
EOF
    fi
  } >"${outf}"
  chmod 600 "${outf}" 2>/dev/null || true
}

patch_materialized_control_plane_vault() {
  local out="$1"
  local vf="${out}/deploy/helm/control-plane/values.yaml"
  [[ -f "${vf}" ]] || return 0
  if spice_patch_feature_enabled superset; then
    perl -0777 -pe '
      s/^externalSecret:\n  enabled: false/externalSecret:\n  enabled: true/ms;
      s/^  syncSuperset: false/  syncSuperset: true/ms;
    ' "${vf}" >"${vf}.tmp" && mv "${vf}.tmp" "${vf}"
  else
    perl -0777 -pe '
      s/^externalSecret:\n  enabled: false/externalSecret:\n  enabled: true/ms;
    ' "${vf}" >"${vf}.tmp" && mv "${vf}.tmp" "${vf}"
  fi
}

patch_materialized_addon_credentials() {
  local out="$1"
  ensure_lab_addon_password_files
  local gpw="" spw="" ssk=""
  if spice_patch_feature_enabled prometheus && [[ -s "${STATE_DIR}/grafana-lab.password" ]]; then
    gpw="$(tr -d '\n\r' <"${STATE_DIR}/grafana-lab.password")"
  fi
  if spice_patch_feature_enabled superset && [[ -s "${STATE_DIR}/superset-lab.password" ]]; then
    spw="$(tr -d '\n\r' <"${STATE_DIR}/superset-lab.password")"
    ssk="$(tr -d '\n\r' <"${STATE_DIR}/superset-lab.secret-key")"
  fi
  local kps="${out}/apps/application-kube-prometheus-stack.yaml"
  if [[ -f "${kps}" && -n "${gpw}" ]]; then
    SPICE_PATCH_GRAFANA_PW="${gpw}" perl -0777 -pe 's/adminPassword: admin/adminPassword: $ENV{SPICE_PATCH_GRAFANA_PW}/g' "${kps}" >"${kps}.tmp" && mv "${kps}.tmp" "${kps}"
  fi
  local ss="${out}/apps/application-superset.yaml"
  if [[ -f "${ss}" && -n "${spw}" && -n "${ssk}" ]]; then
    SPICE_PATCH_SUPERSET_PW="${spw}" SPICE_PATCH_SUPERSET_SK="${ssk}" perl -0777 -pe '
      s/SUPERSET_SECRET_KEY: "spice-kind-lab-superset-secret-key-change-me"/SUPERSET_SECRET_KEY: "$ENV{SPICE_PATCH_SUPERSET_SK}"/g;
      s/(        init:\n)(          resources:)/$1          adminUser:\n            username: admin\n            firstname: Superset\n            lastname: Admin\n            email: admin@superset.com\n            password: $ENV{SPICE_PATCH_SUPERSET_PW}\n$2/s;
    ' "${ss}" >"${ss}.tmp" && mv "${ss}.tmp" "${ss}"
  fi
  patch_materialized_control_plane_vault "${out}"
  write_grafana_superset_credentials_summary
}
