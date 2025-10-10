#!/usr/bin/env bash
# shellcheck disable=SC1078,SC1079,SC1072,SC1073
set -Eeuo pipefail

trap 'echo "[ERROR] Lets Encrypt issuance failed" >&2' ERR

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ENV_FILE="${SCRIPT_DIR}/../.env"

if [[ "${1:-}" == "--auth-hook" ]]; then
  HOST="_acme-challenge.${CERTBOT_DOMAIN}"
  VALUE="${CERTBOT_VALIDATION}"
  cat <<INFO
============================================================
Manual DNS-01 Challenge
============================================================
Create the following TXT record before continuing:

Host : ${HOST}
Value: ${VALUE}

Use your DNS provider to publish the record. This helper can
check propagation using dig.
INFO
  while true; do
    read -r -p "Press [Enter] once the record exists, or type \"check\" to query DNS: " response
    if [[ -z "${response}" ]]; then
      break
    fi
    if [[ "${response}" == "check" ]]; then
      dig +short TXT "${HOST}" | sed 's/^/  -> /'
    else
      echo "Type \"check\" or press Enter to continue." >&2
    fi
  done
  exit 0
fi

if [[ "${1:-}" == "--cleanup-hook" ]]; then
  HOST="_acme-challenge.${CERTBOT_DOMAIN}"
  echo "[INFO] Validation complete for ${HOST}" >&2
  exit 0
fi

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "[ERROR] Missing .env file. Run install.sh first." >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "${ENV_FILE}"
set +a

INSTALL_PREFIX=${INSTALL_PREFIX:-/root/untitledIRC}
SERVER_NAME=${SERVER_NAME:?SERVER_NAME not set in .env}
LETSENCRYPT_EMAIL=${LETSENCRYPT_EMAIL:-admin@${SERVER_NAME}}

ensure_directories() {
  mkdir -p "${INSTALL_PREFIX}/unrealircd/conf/tls"
}

run_certbot() {
  certbot certonly \
    --manual \
    --preferred-challenges dns \
    --manual-auth-hook "${SCRIPT_DIR}/le-dns-manual.sh --auth-hook" \
    --manual-cleanup-hook "${SCRIPT_DIR}/le-dns-manual.sh --cleanup-hook" \
    --manual-public-ip-logging-ok \
    --agree-tos \
    --no-eff-email \
    -m "${LETSENCRYPT_EMAIL}" \
    -d "${SERVER_NAME}" \
    --keep
}

deploy_certificate() {
  local live_path="/etc/letsencrypt/live/${SERVER_NAME}"
  local cert="${live_path}/fullchain.pem"
  local key="${live_path}/privkey.pem"
  if [[ ! -f "${cert}" || ! -f "${key}" ]]; then
    echo "[ERROR] Certificate files not found in ${live_path}" >&2
    exit 1
  fi
  local target_dir="${INSTALL_PREFIX}/unrealircd/conf/tls"
  local backup_cert="${target_dir}/fullchain.pem.bak"
  local backup_key="${target_dir}/privkey.pem.bak"
  if [[ -f "${target_dir}/fullchain.pem" ]]; then
    cp "${target_dir}/fullchain.pem" "${backup_cert}"
  fi
  if [[ -f "${target_dir}/privkey.pem" ]]; then
    cp "${target_dir}/privkey.pem" "${backup_key}"
  fi
  install -o untitledirc -g untitledirc -m 640 "${cert}" "${target_dir}/fullchain.pem"
  install -o untitledirc -g untitledirc -m 600 "${key}" "${target_dir}/privkey.pem"
  systemctl restart unrealircd.service
  echo "[INFO] Deployed Lets Encrypt certificate and restarted UnrealIRCd"
}

main() {
  ensure_directories
  run_certbot
  deploy_certificate
}

main "$@"
