#!/bin/bash -e

BASE_SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
source "${BASE_SCRIPT_DIR}/.env"
source "${BASE_SCRIPT_DIR}/common_functions.sh"

# SYSTEM_NAME="bonus"
# create_system_cert "${SYSTEM_NAME}"

sudo cp "${INTERMEDIATE_CA_CHAIN_PATH}" /usr/local/share/ca-certificates/myCA.crt
sudo update-ca-certificates

awk -v cmd='openssl x509 -noout -subject' '/BEGIN/{close(cmd)};{print | cmd}' < /etc/ssl/certs/ca-certificates.crt | grep Local
