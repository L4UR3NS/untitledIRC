#!/usr/bin/env bash
set -Eeuo pipefail

trap 'echo "[ERROR] Verification failed" >&2' ERR

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)
ENV_FILE="${REPO_ROOT}/.env"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "[ERROR] Missing .env file. Run install.sh first." >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "${ENV_FILE}"
set +a

INSTALL_PREFIX=${INSTALL_PREFIX:-/root/untitledIRC}

ok() {
  printf '[OK] %s\n' "$1"
}

fail() {
  printf '[FAIL] %s\n' "$1"
  exit 1
}

check_service() {
  local service="$1" message="$2"
  if systemctl is-active --quiet "$service"; then
    ok "$message"
  else
    systemctl status "$service" --no-pager
    fail "$message"
  fi
}

check_port() {
  local port="$1" desc="$2"
  if ss -tln | awk '{print $4}' | grep -q ":${port}$"; then
    ok "$desc"
  else
    fail "$desc"
  fi
}

check_certificate() {
  local cert_path="${INSTALL_PREFIX}/unrealircd/conf/tls/fullchain.pem"
  if [[ ! -f "${cert_path}" ]]; then
    fail "TLS certificate present"
  fi
  local enddate
  enddate=$(openssl x509 -in "${cert_path}" -noout -enddate | cut -d'=' -f2)
  ok "TLS certificate valid until ${enddate}"
}

check_unreal_log() {
  local log_file="${INSTALL_PREFIX}/unrealircd/logs/unrealircd.log"
  if [[ -f "${log_file}" ]] && grep -q "Server Ready" "${log_file}"; then
    ok "UnrealIRCd log indicates server ready"
  else
    fail "UnrealIRCd ready state"
  fi
}

check_anope_log() {
  local log_file="${INSTALL_PREFIX}/anope/logs/services.log"
  if [[ -f "${log_file}" ]] && grep -Eiq "connected|link" "${log_file}"; then
    ok "Anope linked to UnrealIRCd"
  else
    fail "Anope link status"
  fi
}

check_webcp() {
  local status
  status=$(curl -s -o /dev/null -w '%{http_code}' -u "${WEBPANEL_USER}:${WEBPANEL_PASSWORD}" "http://127.0.0.1:8080/")
  if [[ "${status}" == "200" ]]; then
    ok "Anope WebCP reachable"
  else
    fail "Anope WebCP reachable (HTTP ${status})"
  fi
}

main() {
  check_service unrealircd.service "UnrealIRCd service running"
  check_service anope.service "Anope service running"
  check_port 6697 "TLS listener active on 6697"
  if [[ "${ENABLE_PLAIN_TEXT_LISTENER,,}" == "true" ]]; then
    check_port 6667 "Plain-text listener active on 6667"
  fi
  check_port 7000 "Link port active on 7000"
  check_port 8080 "WebCP listener active on 8080"
  check_certificate
  check_unreal_log
  check_anope_log
  check_webcp
  cat <<INFO

Next steps:
  - Connect to IRC: ircs://${SERVER_NAME}:6697
  - Access WebCP:   http://<server-address>:8080/
INFO
}

main "$@"
