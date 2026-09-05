# shellcheck shell=bash
# Every variable here is consumed by the scripts that source this file, which
# the linter cannot see from inside it - hence the blanket unused-var waiver.
# shellcheck disable=SC2034
################################################################
# Computed paths for the CA tree.
#
# These are derived from the values you set in .env and are NOT meant to be
# edited per-machine. They live here, tracked in git, rather than in .env -
# which is gitignored - so that a change to the layout reaches everyone
# instead of only new clones.
#
# Sourcing order is always: .env -> paths.sh -> common_functions.sh
################################################################

BASE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
CA_BASE_DIR="${BASE_SCRIPT_DIR}/output"
BASE_CONFIGS_DIR="${BASE_SCRIPT_DIR}/configs"

# Shared OpenSSL config template, rendered per-CA by create_root_ca and
# create_intermediate_ca.
CA_CONFIG_TEMPLATE="${BASE_CONFIGS_DIR}/openssl.cnf.template"

# Root CA
ROOT_CA_DIR="${CA_BASE_DIR}/root"
ROOT_CA_CONFIG="${ROOT_CA_DIR}/openssl.cnf"
ROOT_SUBJ_STR="/CN=${ROOT_CA_CN}/O=${ORGANIZATION_NAME}/C=${COUNTRY_CODE}/ST=${STATE_PROVINCE_CODE}"
ROOT_CA_CERTS_DIR="${ROOT_CA_DIR}/certs"
ROOT_CA_CRL_DIR="${ROOT_CA_DIR}/crl"
ROOT_CA_NEW_CERTS_DIR="${ROOT_CA_DIR}/newcerts"
ROOT_CA_PRIVATE_DIR="${ROOT_CA_DIR}/private"
ROOT_CA_INDEX_TXT="${ROOT_CA_DIR}/index.txt"
ROOT_CA_SERIAL="${ROOT_CA_DIR}/serial"
ROOT_CA_KEY_PATH="${ROOT_CA_PRIVATE_DIR}/ca.key.pem"
ROOT_CA_CERT_PATH="${ROOT_CA_CERTS_DIR}/ca.cert.pem"

# Intermediate CA
INTERMEDIATE_CA_DIR="${CA_BASE_DIR}/intermediate"
INTERMEDIATE_CA_CONFIG="${INTERMEDIATE_CA_DIR}/openssl.cnf"
INTERMEDIATE_SUBJ_STR="/O=${ORGANIZATION_NAME}/OU=${INTERMEDIATE_CA_OU}/CN=${INTERMEDIATE_CA_CN}/C=${COUNTRY_CODE}/ST=${STATE_PROVINCE_CODE}"
INTERMEDIATE_CA_CERTS_DIR="${INTERMEDIATE_CA_DIR}/certs"
INTERMEDIATE_CA_CRL_DIR="${INTERMEDIATE_CA_DIR}/crl"
INTERMEDIATE_CA_CSR_DIR="${INTERMEDIATE_CA_DIR}/csr"
INTERMEDIATE_CA_NEW_CERTS_DIR="${INTERMEDIATE_CA_DIR}/newcerts"
INTERMEDIATE_CA_PRIVATE_DIR="${INTERMEDIATE_CA_DIR}/private"
INTERMEDIATE_CA_INDEX_TXT="${INTERMEDIATE_CA_DIR}/index.txt"
INTERMEDIATE_CA_SERIAL="${INTERMEDIATE_CA_DIR}/serial"
INTERMEDIATE_CRL_NUMBER="${INTERMEDIATE_CA_DIR}/crlnumber"
INTERMEDIATE_CRL_PATH="${INTERMEDIATE_CA_CRL_DIR}/intermediate.crl.pem"
INTERMEDIATE_CA_SIGN_REQUEST="${INTERMEDIATE_CA_CSR_DIR}/intermediate.csr.pem"
INTERMEDIATE_CA_KEY_PATH="${INTERMEDIATE_CA_PRIVATE_DIR}/intermediate.key.pem"
INTERMEDIATE_CA_CERT_PATH="${INTERMEDIATE_CA_CERTS_DIR}/intermediate.cert.pem"
INTERMEDIATE_CA_CHAIN_PATH="${INTERMEDIATE_CA_CERTS_DIR}/ca-chain.cert.pem"

# System certs
BASE_SYSTEMS_DIR="${CA_BASE_DIR}/systems"
BASE_SYSTEM_CONFIGS_DIR="${BASE_CONFIGS_DIR}/systems"

# How long an issued system cert is valid for. Kept under the 398-day cap
# that browsers enforce on publicly-trusted certs, out of habit.
SYSTEM_CERT_EXPIRY_DAYS=375
