#!/bin/bash
################################################################
# Install the local CA into this machine's trust stores.
#
#   system    - the OS anchors used by curl, openssl, python, wget, ...
#   browsers  - the NSS databases used by Chrome/Chromium and Firefox
#
# Browsers do NOT read the system store and the system store does not read
# the browser ones, so both are needed for a seamless local HTTPS setup.
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
Usage: $(basename "${0}") [ --system | --browsers ] [ --status ] [ --instructions ] [ --help ]

  (no flags)       install into both the system and browser trust stores
  --system         install into the system trust store only (uses sudo)
  --browsers       install into the browser NSS trust stores only
  --status         show where the CA is currently trusted, then exit
  --instructions   print manual / copy-paste trust instructions, then exit
  --help           show this message
EOF
    exit 2
}

DO_SYSTEM=""
DO_BROWSERS=""

SHORT=h
LONG=system,browsers,status,instructions,help
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
        --status)
            trust_status
            exit 0
            ;;
        --instructions)
            print_manual_instructions
            exit 0
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

require_ca_built

if [[ -n "${DO_SYSTEM}" ]]; then
    install_system_trust
fi

if [[ -n "${DO_BROWSERS}" ]]; then
    install_nss_trust
fi

msg_header "Done"
echo "Run '$(basename "${0}") --status' to review, or 'untrust_ca.sh' to undo."
