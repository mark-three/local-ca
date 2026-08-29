#!/bin/bash -e

BASE_SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
source "${BASE_SCRIPT_DIR}/.env"
source "${BASE_SCRIPT_DIR}/common_functions.sh"

# Install the Root and Intermediate CA certs into the system trust store so
# CLI clients (curl, openssl, python requests, etc.) trust them. Browsers use
# their own trust store (NSS) and must be configured separately - see README.
#
# NOTES on update-ca-certificates (Debian/Ubuntu):
#   - It only picks up files under /usr/local/share/ca-certificates/ that end
#     in .crt - a .pem file is silently ignored.
#   - Each .crt file must contain exactly ONE certificate. The hashing step
#     only reads the first cert in a multi-cert file, so installing the
#     ca-chain bundle as a single file silently drops the second cert.
#     Root and Intermediate are therefore installed as separate files.

TRUST_STORE_DIR="/usr/local/share/ca-certificates"
ROOT_TRUST_PATH="${TRUST_STORE_DIR}/local-ca-root.crt"
INTERMEDIATE_TRUST_PATH="${TRUST_STORE_DIR}/local-ca-intermediate.crt"

msg_header "Install CA certs into the system trust store"

# Remove the legacy multi-cert bundle install (only the first cert was hashed)
sudo rm -f "${TRUST_STORE_DIR}/myCA.crt"

sudo cp "${ROOT_CA_CERT_PATH}" "${ROOT_TRUST_PATH}"
sudo cp "${INTERMEDIATE_CA_CERT_PATH}" "${INTERMEDIATE_TRUST_PATH}"
sudo update-ca-certificates

msg_header "Verify the CA certs are in the system trust store"

# Both the Root and Intermediate CA subjects must appear in the bundle
TRUSTED_SUBJECTS=$(awk -v cmd='openssl x509 -noout -subject' '/BEGIN/{close(cmd)};{print | cmd}' \
    < /etc/ssl/certs/ca-certificates.crt)
echo "${TRUSTED_SUBJECTS}" | grep "${ROOT_CA_CN}"
echo "${TRUSTED_SUBJECTS}" | grep "${INTERMEDIATE_CA_CN}"
