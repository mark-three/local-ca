#!/bin/bash
set -euo pipefail

BASE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

# .env is sourced before common_functions.sh, so this guard is inlined rather
# than shared - without it every script fails with an opaque "unbound variable".
if [[ ! -f "${BASE_SCRIPT_DIR}/.env" ]]; then
    echo "ERROR: ${BASE_SCRIPT_DIR}/.env not found." >&2
    echo "Run 'just init' (or cp .env.example .env) and set the key passwords." >&2
    exit 1
fi

# shellcheck source=.env.example
source "${BASE_SCRIPT_DIR}/.env"
# shellcheck source=paths.sh
source "${BASE_SCRIPT_DIR}/paths.sh"
# shellcheck source=common_functions.sh
source "${BASE_SCRIPT_DIR}/common_functions.sh"


help()
{
    echo "Usage: $(basename "${0}")
            --system SYSTEM_NAME
            [ --help  ]"
    exit 2
}

# Parse the input parameters
SHORT=s:,h
LONG=system:,help
OPTS=$(getopt -a -n "$(basename "${0}")" --options "${SHORT}" --longoptions "${LONG}" -- "$@")

eval set -- "$OPTS"

while :
do
  case "${1}" in
    --system )
      SYSTEM_NAME="${2}"
      shift 2
      ;;
    --help)
      help
      ;;
    --)
      shift;
      break
      ;;
    *)
      echo "Unexpected option: $1"
      help
      ;;
  esac
done

if [[ -z "${SYSTEM_NAME:-}" ]]; then
    echo "ERROR: --system SYSTEM_NAME is required" >&2
    help
    exit 1
fi

# Verify the System config file exists
check_system_config_exists "${SYSTEM_NAME}"

# Revoke the cert for system with system name
revoke_system_cert "${SYSTEM_NAME}"
