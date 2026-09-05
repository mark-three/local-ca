#!/bin/bash
################################################################
# Remove the local CA from this machine's trust stores.
#
# The inverse of trust_ca.sh. This leaves the generated CA in ./output
# untouched - use 'just uninstall' to remove that as well.
################################################################
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
# shellcheck source=trust_functions.sh
source "${BASE_SCRIPT_DIR}/trust_functions.sh"

help() {
    cat <<EOF
Usage: $(basename "${0}") [ --system | --browsers ] [ --help ]

  (no flags)   remove from both the system and browser trust stores
  --system     remove from the system trust store only (uses sudo)
  --browsers   remove from the browser NSS trust stores only
  --help       show this message
EOF
    exit 2
}

DO_SYSTEM=""
DO_BROWSERS=""

SHORT=h
LONG=system,browsers,help
OPTS=$(getopt -a -n "$(basename "${0}")" --options "${SHORT}" --longoptions "${LONG}" -- "$@")
eval set -- "${OPTS}"

while :; do
    case "${1}" in
        --system)
            DO_SYSTEM=1
            shift
            ;;
        --browsers)
            DO_BROWSERS=1
            shift
            ;;
        --help | -h)
            help
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "Unexpected option: ${1}" >&2
            help
            ;;
    esac
done

# No target flags means both.
if [[ -z "${DO_SYSTEM}" && -z "${DO_BROWSERS}" ]]; then
    DO_SYSTEM=1
    DO_BROWSERS=1
fi

# Removal only needs the Root CA cert to know what to look for. If the output
# directory is already gone we can still clean the system store by file name,
# and the NSS stores by nickname, so this is not fatal.
if [[ ! -f "${ROOT_CA_CERT_PATH}" ]]; then
    echo "NOTE: ${ROOT_CA_CERT_PATH} is missing; removing by name only."
fi

if [[ -n "${DO_BROWSERS}" ]]; then
    remove_nss_trust
fi

if [[ -n "${DO_SYSTEM}" ]]; then
    remove_system_trust
fi

msg_header "Done"
