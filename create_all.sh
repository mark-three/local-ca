#!/bin/bash -e

BASE_SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
source "${BASE_SCRIPT_DIR}/.env"
source "${BASE_SCRIPT_DIR}/common_functions.sh"


# # Create and verify Root CA
# create_root_ca
# verify_root_ca

# # Create and verify Intermediate CA
# create_intermediate_ca
# verify_intermediate_ca


# # Create and verify cert for system example
# SYSTEM_NAME="example"
# create_system_cert "${SYSTEM_NAME}"
# verify_system_cert "${SYSTEM_NAME}"

