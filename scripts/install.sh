#!/usr/bin/env bash
set -Eeuo pipefail

trap 'echo "[ERROR] Installation failed" >&2' ERR

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)
ENV_FILE="${REPO_ROOT}/.env"
VERSIONS_FILE="${REPO_ROOT}/.versions"
BUILD_DIR="${REPO_ROOT}/build"

log() {
  printf '[INFO] %s\n' "$1"
}

require_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "[ERROR] This installer must be run as root" >&2
    exit 1
  fi
}

ensure_env_file() {
  if [[ ! -f "${ENV_FILE}" ]]; then
    log "Creating .env from template"
    cp "${REPO_ROOT}/.env.example" "${ENV_FILE}"
  fi
}

load_env() {
  set -a
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
  set +a
  INSTALL_PREFIX=${INSTALL_PREFIX:-/root/untitledIRC}
  export INSTALL_PREFIX
}

run_dependencies() {
  log "Provisioning dependencies"
  "${SCRIPT_DIR}/deps.sh"
}

run_secret_generation() {
  log "Ensuring secret values"
  "${SCRIPT_DIR}/random.sh"
  load_env
}

render_template() {
  local template_path="$1"
  local destination_path="$2"
  shift 2 || true
  local -a args=()
  while (($#)); do
    args+=("$1")
    shift
  done
  python3 - "$template_path" "$destination_path" "${args[@]}" <<'PY'
import os
import sys
from pathlib import Path
import re

template_path = Path(sys.argv[1])
destination_path = Path(sys.argv[2])
variables = dict(os.environ)
for entry in sys.argv[3:]:
    if '=' in entry:
        key, value = entry.split('=', 1)
        variables[key] = value.replace('\\n', '\n')

content = template_path.read_text(encoding='utf-8')

def replace(match: re.Match) -> str:
    key = match.group(1)
    return variables.get(key, '')

rendered = re.sub(r"{{\s*([A-Z0-9_]+)\s*}}", replace, content)
destination_path.parent.mkdir(parents=True, exist_ok=True)
destination_path.write_text(rendered, encoding='utf-8')
PY
}

update_versions_file() {
  local key="$1" value="$2"
  python3 - "$VERSIONS_FILE" "$key" "$value" <<'PY'
import sys
from pathlib import Path

def update(path: Path, key: str, value: str) -> None:
    lines = []
    found = False
    if path.exists():
        with path.open('r', encoding='utf-8') as handle:
            for raw in handle.readlines():
                if raw.startswith(f"{key}="):
                    lines.append(f"{key}={value}\n")
                    found = True
                else:
                    lines.append(raw)
    if not found:
        lines.append(f"{key}={value}\n")
    with path.open('w', encoding='utf-8') as handle:
        handle.writelines(lines)

if __name__ == '__main__':
    update(Path(sys.argv[1]), sys.argv[2], sys.argv[3])
PY
}

install_unrealircd() {
  local install_dir="${INSTALL_PREFIX}/unrealircd"
  if [[ -x "${install_dir}/bin/unrealircd" ]]; then
    log "UnrealIRCd already installed"
    return
  fi
  mkdir -p "${BUILD_DIR}"
  local tarball="${BUILD_DIR}/unrealircd-latest.tar.gz"
  log "Downloading UnrealIRCd"
  curl -fsSL "https://www.unrealircd.org/downloads/unrealircd-latest.tar.gz" -o "${tarball}"
  rm -rf "${BUILD_DIR}/unrealircd-src"
  mkdir -p "${BUILD_DIR}/unrealircd-src"
  tar -xzf "${tarball}" -C "${BUILD_DIR}/unrealircd-src" --strip-components=1
  local version
  version=$(grep -Eo 'UNREALIRCD_VERSION "+[^"]+"' "${BUILD_DIR}/unrealircd-src/include/version.h" | awk -F'"' '{print $2}')
  log "Building UnrealIRCd ${version}"
  pushd "${BUILD_DIR}/unrealircd-src" >/dev/null
  ./configure --prefix="${install_dir}" >/tmp/unreal-config.log
  make -j"$(nproc)" >/tmp/unreal-build.log
  make install >/tmp/unreal-install.log
  popd >/dev/null
  chown -R untitledirc:untitledirc "${install_dir}"
  update_versions_file "UNREALIRCD" "${version}"
}

configure_unrealircd() {
  local install_dir="${INSTALL_PREFIX}/unrealircd"
  local conf_dir="${install_dir}/conf"
  mkdir -p "${conf_dir}/tls" "${install_dir}/logs" "${install_dir}/data"
  local plain_block
  if [[ "${ENABLE_PLAIN_TEXT_LISTENER,,}" == "true" ]]; then
    plain_block=$'listen {\n    ip *;\n    port 6667;\n    options {\n        clientsonly;\n    };\n}\n'
  else
    plain_block='# Plain-text listener disabled'
  fi
  render_template "${REPO_ROOT}/unrealircd/templates/unrealircd.conf" "${conf_dir}/unrealircd.conf" \
    "PLAIN_LISTENER_BLOCK=${plain_block//$'\n'/\\n}"
  render_template "${REPO_ROOT}/unrealircd/templates/tls.cnf" "${conf_dir}/tls.cnf"
  chown -R untitledirc:untitledirc "${install_dir}/conf"
}

ensure_self_signed_tls() {
  local tls_dir="${INSTALL_PREFIX}/unrealircd/conf/tls"
  local cert="${tls_dir}/fullchain.pem"
  local key="${tls_dir}/privkey.pem"
  if [[ -f "${cert}" && -f "${key}" ]]; then
    return
  fi
  log "Generating temporary self-signed TLS certificate"
  local tmpdir
  tmpdir=$(mktemp -d)
  openssl req -x509 -nodes -newkey rsa:4096 \
    -keyout "${tmpdir}/self.key" \
    -out "${tmpdir}/self.crt" \
    -days 30 \
    -subj "/C=${TLS_COUNTRY}/ST=${TLS_STATE}/L=${TLS_LOCALITY}/O=${NETWORK_NAME}/CN=${SERVER_NAME}"
  install -o untitledirc -g untitledirc -m 640 "${tmpdir}/self.crt" "${cert}"
  install -o untitledirc -g untitledirc -m 600 "${tmpdir}/self.key" "${key}"
  rm -rf "${tmpdir}"
}

install_anope() {
  local install_dir="${INSTALL_PREFIX}/anope"
  if [[ -x "${install_dir}/bin/services" ]]; then
    log "Anope already installed"
    return
  fi
  mkdir -p "${BUILD_DIR}"
  local tarball="${BUILD_DIR}/anope-latest.tar.gz"
  log "Fetching latest Anope release metadata"
  local download_url version
  read -r download_url version < <(python3 - <<'PY'
import json
import sys
import urllib.request

data = json.load(urllib.request.urlopen('https://api.github.com/repos/anope/anope/releases/latest'))
for asset in data.get('assets', []):
    name = asset.get('name', '')
    if name.endswith('.tar.gz') and 'windows' not in name.lower():
        print(asset['browser_download_url'], data.get('tag_name', ''))
        break
PY
)
  if [[ -z "${download_url:-}" ]]; then
    echo "[ERROR] Unable to determine Anope download URL" >&2
    exit 1
  fi
  log "Downloading Anope ${version}"
  curl -fsSL "${download_url}" -o "${tarball}"
  rm -rf "${BUILD_DIR}/anope-src"
  mkdir -p "${BUILD_DIR}/anope-src"
  tar -xzf "${tarball}" -C "${BUILD_DIR}/anope-src" --strip-components=1
  pushd "${BUILD_DIR}/anope-src" >/dev/null
  ./Config -quick --prefix="${install_dir}" --enable-extras=m_httpd,m_webcpanel >/tmp/anope-config.log
  make -j"$(nproc)" >/tmp/anope-build.log
  make install >/tmp/anope-install.log
  popd >/dev/null
  chown -R untitledirc:untitledirc "${install_dir}"
  update_versions_file "ANOPE" "${version}"
}

configure_anope() {
  local install_dir="${INSTALL_PREFIX}/anope"
  mkdir -p "${install_dir}/data" "${install_dir}/logs"
  render_template "${REPO_ROOT}/anope/templates/services.conf" "${install_dir}/conf/services.conf"
  chown -R untitledirc:untitledirc "${install_dir}/conf" "${install_dir}/data" "${install_dir}/logs"
}

install_systemd_unit() {
  local template="$1" unit_name="$2"
  local destination="/etc/systemd/system/${unit_name}"
  render_template "${template}" "${destination}"
}

configure_systemd() {
  log "Configuring systemd units"
  install_systemd_unit "${REPO_ROOT}/systemd/unrealircd.service" "unrealircd.service"
  install_systemd_unit "${REPO_ROOT}/systemd/anope.service" "anope.service"
  systemctl daemon-reload
  systemctl enable --now unrealircd.service
  systemctl enable --now anope.service
}

main() {
  require_root
  ensure_env_file
  load_env
  run_dependencies
  run_secret_generation
  install_unrealircd
  configure_unrealircd
  ensure_self_signed_tls
  install_anope
  configure_anope
  configure_systemd
  log "Installation complete"
}

main "$@"
