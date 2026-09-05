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


help() {
    cat <<EOF
Usage: $(basename "${0}") [ --force ] [ --help ]

Creates the Root CA, the Intermediate CA and the Root-Intermediate chain.

  --force   skip the confirmation prompt (for non-interactive use)
  --help    show this message

WARNING: this deletes ${CA_BASE_DIR} first, which includes every system cert
already issued. Those certs stay valid on disk elsewhere but can no longer be
verified or revoked, so they all need re-issuing against the new CA.
EOF
    exit 2
}

FORCE=""

SHORT=fh
LONG=force,help
OPTS=$(getopt -a -n "$(basename "${0}")" --options "${SHORT}" --longoptions "${LONG}" -- "$@")
eval set -- "${OPTS}"

while :; do
    case "${1}" in
        --force | -f)
            FORCE=1
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

# create_root_ca wipes ${CA_BASE_DIR}, taking every issued system cert with it.
# Confirm before doing that to an existing CA.
if [[ -z "${FORCE}" && -d "${CA_BASE_DIR}" ]]; then
    msg_header "An existing CA was found at ${CA_BASE_DIR}"
    echo "Regenerating deletes it, along with every system cert issued from it."
    echo "Those certs will still be deployed on your services but will no longer"
    echo "chain to a trusted CA - each one has to be re-issued."
    echo
    read -r -p "Type 'yes' to delete and regenerate: " confirm
    if [[ "${confirm}" != "yes" ]]; then
        echo "Aborted; nothing was changed."
        exit 1
    fi
fi

# Create and verify Root CA
create_root_ca
verify_root_ca

# Create and verify Intermediate CA
create_intermediate_ca
verify_intermediate_ca

msg_header "CA created"
echo "Root CA cert:  ${ROOT_CA_CERT_PATH}"
echo "Chain file:    ${INTERMEDIATE_CA_CHAIN_PATH}"
echo
echo "Next: 'just trust' to install it into the system and browser trust stores."
