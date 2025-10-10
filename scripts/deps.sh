#!/usr/bin/env bash
set -Eeuo pipefail

trap 'echo "[ERROR] Dependency installation failed" >&2' ERR

log() {
  printf '[INFO] %s\n' "$1"
}

require_ubuntu() {
  if [[ ! -r /etc/os-release ]]; then
    echo "[ERROR] Unable to determine OS release" >&2
    exit 1
  fi
  # shellcheck disable=SC1091
  source /etc/os-release
  if [[ "${ID}" != "ubuntu" ]]; then
    echo "[ERROR] Unsupported distribution: ${ID:-unknown}. Ubuntu 22.04 or newer is required." >&2
    exit 1
  fi
  local major minor
  IFS='.' read -r major minor <<<"${VERSION_ID}"
  if (( major < 22 || (major == 22 && minor < 4) )); then
    echo "[ERROR] Ubuntu 22.04 or newer is required (detected ${VERSION_ID})." >&2
    exit 1
  fi
}

install_packages() {
  local packages=(
    build-essential
    cmake
    pkg-config
    libssl-dev
    zlib1g-dev
    libpcre2-dev
    libargon2-dev
    libcurl4-openssl-dev
    libsqlite3-dev
    git
    curl
    wget
    tar
    openssl
    certbot
    python3
    python3-venv
    apache2-utils
    ufw
  )
  log "Updating apt package cache"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  log "Installing build and runtime dependencies"
  apt-get install -y "${packages[@]}"
}

create_system_user() {
  local user=untitledirc
  if id -u "$user" >/dev/null 2>&1; then
    log "System user '$user' already exists"
    return
  fi
  log "Creating system user '$user'"
  useradd --system --home-dir /root/untitledIRC --shell /usr/sbin/nologin "$user"
}

configure_ufw() {
  if ! command -v ufw >/dev/null 2>&1; then
    echo "[WARN] UFW not installed; skipping firewall configuration" >&2
    return
  fi
  local ports=(6697 6667 7000 8080)
  for port in "${ports[@]}"; do
    if ufw status verbose 2>/dev/null | grep -q "${port}/tcp"; then
      continue
    fi
    log "Allowing TCP port ${port} via UFW"
    ufw allow "${port}/tcp" || true
  done
}

main() {
  require_ubuntu
  install_packages
  create_system_user
  configure_ufw
  log "Dependency provisioning completed"
}

main "$@"
