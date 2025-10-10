#!/usr/bin/env bash
set -Eeuo pipefail

trap 'echo "[ERROR] Secret generation failed" >&2' ERR

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)
ENV_FILE="${REPO_ROOT}/.env"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "[ERROR] Missing .env file at ${ENV_FILE}. Run install.sh first." >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "${ENV_FILE}"
set +a

update_env_var() {
  local key="$1" value="$2"
  python3 - "$ENV_FILE" "$key" "$value" <<'PY'
import os
import sys
from pathlib import Path

def update_env(path: Path, key: str, value: str) -> None:
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
    env_path = Path(sys.argv[1])
    key = sys.argv[2]
    value = sys.argv[3]
    update_env(env_path, key, value)
PY
}

generate_password() {
  python3 - <<'PY'
import secrets
import string
alphabet = string.ascii_letters + string.digits
print(''.join(secrets.choice(alphabet) for _ in range(24)))
PY
}

generate_sha512_hash() {
  python3 - <<'PY'
import crypt
import secrets
import string

def make_password(length: int = 24) -> str:
    alphabet = string.ascii_letters + string.digits
    return ''.join(secrets.choice(alphabet) for _ in range(length))

plain = make_password()
hashed = crypt.crypt(plain, crypt.mksalt(crypt.METHOD_SHA512))
print(f"{plain}\n{hashed}")
PY
}

generate_htpasswd_hash() {
  local user="$1" password="$2"
  htpasswd -bnB "$user" "$password" | cut -d':' -f2-
}

ensure_secret() {
  local key="$1" generator="$2"
  local current="${!key-}"
  if [[ -n "${current}" ]]; then
    return
  fi
  local value
  value="$($generator)"
  update_env_var "$key" "$value"
  export "$key"="$value"
  printf '[INFO] Generated %s\n' "$key"
}

ensure_oper_hash() {
  if [[ -n "${OPER_PASSWORD_HASH:-}" ]]; then
    return
  fi
  local output plain hash
  output="$(generate_sha512_hash)"
  plain="${output%%$'\n'*}"
  hash="${output#*$'\n'}"
  update_env_var "OPER_PASSWORD_HASH" "$hash"
  update_env_var "OPER_PASSWORD_PLAIN" "$plain"
  export OPER_PASSWORD_HASH="$hash"
  export OPER_PASSWORD_PLAIN="$plain"
  printf '[INFO] Generated OPER_PASSWORD_HASH and stored plain password in OPER_PASSWORD_PLAIN\n'
}

ensure_webpanel_password() {
  if [[ -n "${WEBPANEL_PASSWORD:-}" ]]; then
    if [[ -z "${WEBPANEL_PASSWORD_HASH:-}" ]]; then
      local hash
      hash="$(generate_htpasswd_hash "${WEBPANEL_USER}" "${WEBPANEL_PASSWORD}")"
      update_env_var "WEBPANEL_PASSWORD_HASH" "$hash"
      export WEBPANEL_PASSWORD_HASH="$hash"
      printf '[INFO] Derived WEBPANEL_PASSWORD_HASH from existing WEBPANEL_PASSWORD\n'
    fi
    return
  fi
  local password hash
  password="$(generate_password)"
  hash="$(generate_htpasswd_hash "${WEBPANEL_USER}" "$password")"
  update_env_var "WEBPANEL_PASSWORD" "$password"
  update_env_var "WEBPANEL_PASSWORD_HASH" "$hash"
  export WEBPANEL_PASSWORD="$password"
  export WEBPANEL_PASSWORD_HASH="$hash"
  printf '[INFO] Generated WebCP credentials\n'
}

ensure_cloak_keys() {
  local keys=(CLOAK_KEY1 CLOAK_KEY2 CLOAK_KEY3)
  for key in "${keys[@]}"; do
    if [[ -z "${!key-}" ]]; then
      local value
      value="$(generate_password)"
      update_env_var "$key" "$value"
      export "$key"="$value"
      printf '[INFO] Generated %s\n' "$key"
    fi
  done
}

main() {
  ensure_oper_hash
  ensure_secret LINK_PASSWORD generate_password
  ensure_secret SERVICES_PASSWORD generate_password
  ensure_secret OPERSERV_PASSWORD generate_password
  ensure_secret NICKSERV_PASSWORD generate_password
  ensure_webpanel_password
  ensure_cloak_keys
  printf '[INFO] Secret generation completed\n'
}

main "$@"
