#!/bin/bash -e

BASE_SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
source "${BASE_SCRIPT_DIR}/.env"
source "${BASE_SCRIPT_DIR}/common_functions.sh"


help()
{
    echo "Usage: $(basename "${0}")
            --system-name SYSTEM_NAME
            [ --help  ]"
    exit 2
}

# Parse the input parameters
SHORT=s:,h
LONG=system-name:,help
OPTS=$(getopt -a -n "$(basename "${0}")" --options $SHORT --longoptions $LONG -- "$@")

eval set -- "$OPTS"

while :
do
  case "${1}" in
    --system-name )
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

if [[ -z "${SYSTEM_NAME}" ]]; then
    echo "\$SYSTEM_NAME is NOT set"
    help
    exit 1
fi

# Verify the input param SYSTEM_NAME exists
check_var_not_null "SYSTEM_NAME" "${SYSTEM_NAME}"

# Verify the System config file exists
check_system_config_exists "${SYSTEM_NAME}"

# Create and verify cert for system with system name
create_system_cert "${SYSTEM_NAME}"
verify_system_cert "${SYSTEM_NAME}"
