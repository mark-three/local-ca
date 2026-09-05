# shellcheck shell=bash
################################################################
# Common functions for creating Cert Authorities
#
# Sourced by the create_* / revoke_* scripts. Requires .env to have
# been sourced first.
################################################################

msg_header() {
    local msg="${1}"

    echo "################################################################"
    echo "# ${msg}"
    echo "################################################################"
}

# Render the shared OpenSSL config template for one CA. The root and the
# intermediate differ only in these five values, so they share one template
# rather than two near-identical files that have to be kept in sync.
render_ca_config() {
    local ca_dir="${1}"
    local key_file="${2}"
    local cert_file="${3}"
    local crl_file="${4}"
    local policy="${5}"
    local out_path="${6}"

    # The directory is a path, so escape its slashes for use as a sed replacement.
    local ca_dir_esc
    ca_dir_esc="$(echo "${ca_dir}" | sed 's_/_\\/_g')"

    sed \
        -e "s/CA_DIR/${ca_dir_esc}/g" \
        -e "s/CA_KEY_FILE/${key_file}/g" \
        -e "s/CA_CERT_FILE/${cert_file}/g" \
        -e "s/CA_CRL_FILE/${crl_file}/g" \
        -e "s/CA_POLICY/${policy}/g" \
        "${CA_CONFIG_TEMPLATE}" > "${out_path}"
}

# Print the parts of a certificate worth reading. The full `openssl x509 -text`
# dump is ~60 lines per cert and was previously printed twice per CA, which
# buried the `openssl verify` result that actually matters.
summarise_cert() {
    local cert_path="${1}"

    openssl x509 -noout -subject -issuer -dates -in "${cert_path}"
    openssl x509 -noout -ext basicConstraints,keyUsage,subjectAltName \
        -in "${cert_path}" 2>/dev/null || true
    echo "Full detail: openssl x509 -noout -text -in ${cert_path}"
}

# Fail early with a useful message if the CA has not been generated yet.
# Every downstream step (signing, trusting, verifying) needs these two files.
require_ca_built() {
    local missing=0

    if [[ ! -f "${ROOT_CA_CERT_PATH}" ]]; then
        echo "ERROR: Root CA cert not found: ${ROOT_CA_CERT_PATH}" >&2
        missing=1
    fi
    if [[ ! -f "${INTERMEDIATE_CA_CERT_PATH}" ]]; then
        echo "ERROR: Intermediate CA cert not found: ${INTERMEDIATE_CA_CERT_PATH}" >&2
        missing=1
    fi

    if [[ "${missing}" -eq 1 ]]; then
        echo "Run 'just ca' (or ./create_root_intermediate_ca.sh) first." >&2
        return 1
    fi
}

create_root_ca() {
    msg_header "Create the Root CA"

    # Delete the previously existing CA folder structure
    # WARNING: This deletes all previous CA's at the root directory, this should only be run once per CA
    rm -rf "${CA_BASE_DIR}"

    # Create the Root CA folder structure
    mkdir -p "${ROOT_CA_CERTS_DIR}"
    mkdir -p "${ROOT_CA_CRL_DIR}"
    mkdir -p "${ROOT_CA_NEW_CERTS_DIR}"
    mkdir -p "${ROOT_CA_PRIVATE_DIR}"
    chmod 700 "${ROOT_CA_PRIVATE_DIR}"
    touch "${ROOT_CA_INDEX_TXT}"
    echo 1000 > "${ROOT_CA_SERIAL}"

    # Render the shared OpenSSL config template for the Root CA
    render_ca_config "${ROOT_CA_DIR}" "ca.key.pem" "ca.cert.pem" "ca.crl.pem" \
        "policy_strict" "${ROOT_CA_CONFIG}"

    # Create the Root CA Private Key
    openssl genrsa \
        -aes256 \
        -passout "pass:${ROOT_KEY_PASS}" \
        -out "${ROOT_CA_KEY_PATH}" \
        4096
    chmod 400 "${ROOT_CA_KEY_PATH}"

    # Create the Root CA Certificate, autofilling the Subject fields with -subj
    openssl req \
        -config "${ROOT_CA_CONFIG}" \
        -key "${ROOT_CA_KEY_PATH}" \
        -new -x509 -days 7300 \
        -sha256 \
        -extensions v3_ca \
        -passin "pass:${ROOT_KEY_PASS}" \
        -subj "${ROOT_SUBJ_STR}" \
        -out "${ROOT_CA_CERT_PATH}"
    chmod 444 "${ROOT_CA_CERT_PATH}"
}

verify_root_ca() {
    msg_header "Verify the Root CA"

    summarise_cert "${ROOT_CA_CERT_PATH}"
}

create_intermediate_ca() {
    msg_header "Create Intermediate CA"

    # Delete any existing Intermediate CA folder structure
    rm -rf "${INTERMEDIATE_CA_DIR}"

    # Create the Intermediate CA folder structure
    mkdir -p "${INTERMEDIATE_CA_CERTS_DIR}"
    mkdir -p "${INTERMEDIATE_CA_CRL_DIR}"
    mkdir -p "${INTERMEDIATE_CA_CSR_DIR}"
    mkdir -p "${INTERMEDIATE_CA_NEW_CERTS_DIR}"
    mkdir -p "${INTERMEDIATE_CA_PRIVATE_DIR}"
    chmod 700 "${INTERMEDIATE_CA_PRIVATE_DIR}"
    touch "${INTERMEDIATE_CA_INDEX_TXT}"
    echo 1000 > "${INTERMEDIATE_CA_SERIAL}"
    echo 1000 > "${INTERMEDIATE_CRL_NUMBER}"

    # Render the shared OpenSSL config template for the Intermediate CA
    render_ca_config "${INTERMEDIATE_CA_DIR}" "intermediate.key.pem" \
        "intermediate.cert.pem" "intermediate.crl.pem" "policy_loose" \
        "${INTERMEDIATE_CA_CONFIG}"

    # Create the Intermediate CA Private Key
    openssl genrsa \
        -aes256 \
        -passout "pass:${INTERMEDIATE_KEY_PASS}" \
        -out "${INTERMEDIATE_CA_KEY_PATH}" \
        4096
    chmod 400 "${INTERMEDIATE_CA_KEY_PATH}"

    # Create the Intermediate CA signing request
    openssl req \
        -config "${INTERMEDIATE_CA_CONFIG}" \
        -subj "${INTERMEDIATE_SUBJ_STR}" \
        -new -sha256 \
        -passin "pass:${INTERMEDIATE_KEY_PASS}" \
        -key "${INTERMEDIATE_CA_KEY_PATH}" \
        -out "${INTERMEDIATE_CA_SIGN_REQUEST}"

    # Create the Intermediate CA cert
    openssl ca \
        -batch \
        -config "${ROOT_CA_CONFIG}" \
        -passin "pass:${ROOT_KEY_PASS}" \
        -extensions v3_intermediate_ca \
        -days 3650 -notext -md sha256 \
        -in "${INTERMEDIATE_CA_SIGN_REQUEST}" \
        -out "${INTERMEDIATE_CA_CERT_PATH}"
    chmod 444 "${INTERMEDIATE_CA_CERT_PATH}"

    # Create the cert chain file
    cat "${INTERMEDIATE_CA_CERT_PATH}" \
      "${ROOT_CA_CERT_PATH}" > "${INTERMEDIATE_CA_CHAIN_PATH}"
    chmod 444 "${INTERMEDIATE_CA_CHAIN_PATH}"
}

verify_intermediate_ca() {
    msg_header "Verify Intermediate CA"

    summarise_cert "${INTERMEDIATE_CA_CERT_PATH}"
    echo

    # Verify the Intermediate CA cert against the Root CA cert
    openssl verify -CAfile "${ROOT_CA_CERT_PATH}" \
        "${INTERMEDIATE_CA_CERT_PATH}"
}

check_system_config_exists() {
    local system_name="${1}"
    local system_ext_path="${BASE_SYSTEM_CONFIGS_DIR}/${system_name}.ext"
    if [[ ! -f "${system_ext_path}" ]] ; then
        echo "ERROR: config ${system_ext_path} does not exist." >&2
        echo "Create it with 'just new-system ${system_name}' and set the DNS/IP entries." >&2
        exit 1
    fi
}

create_system_cert() {
    local system_name="${1}"
    msg_header "Create system cert: ${system_name}"

    local system_cert_dir_path="${BASE_SYSTEMS_DIR}/${system_name}"
    local system_key_path="${system_cert_dir_path}/${system_name}.key.pem"
    local system_key_no_pass_path="${system_cert_dir_path}/${system_name}-no-pass.key.pem"
    local system_signing_request_path="${system_cert_dir_path}/${system_name}.csr.pem"
    local system_cert_path="${system_cert_dir_path}/${system_name}.cert.pem"
    local system_fullchain_path="${system_cert_dir_path}/${system_name}.fullchain.cert.pem"
    local system_subj_str="/C=${COUNTRY_CODE}/ST=${STATE_PROVINCE_CODE}/O=${ORGANIZATION_NAME}/OU=${SYSTEM_CERTS_OU}/CN=${system_name}"
    local system_ext_path="${BASE_SYSTEM_CONFIGS_DIR}/${system_name}.ext"


    # Make the system cert path
    mkdir -p "${system_cert_dir_path}"

    # Create a system key with password
    rm -rf "${system_key_path}"
    openssl genrsa \
        -aes256 \
        -passout "pass:${SYSTEM_KEY_PASS}" \
        -out "${system_key_path}" 2048

    # Rewrite system key without password
    openssl rsa \
        -passin "pass:${SYSTEM_KEY_PASS}" \
        -in "${system_key_path}" \
        -out "${system_key_no_pass_path}"
    # chmod 400 "${system_key_path}"
    # chmod 400 "${system_key_no_pass_path}"

    # Create a system signing request
    rm -rf "${system_signing_request_path}"
    openssl req \
        -config "${INTERMEDIATE_CA_CONFIG}" \
        -key "${system_key_path}" \
        -subj "${system_subj_str}" \
        -passin "pass:${SYSTEM_KEY_PASS}" \
        -new -sha256 \
        -out "${system_signing_request_path}"

    # Create a system cert, with custom ext file
    openssl ca \
        -batch \
        -config "${INTERMEDIATE_CA_CONFIG}" \
        -extensions server_cert \
        -extfile "${system_ext_path}" \
        -days "${SYSTEM_CERT_EXPIRY_DAYS}" \
        -notext \
        -md sha256 \
        -passin "pass:${INTERMEDIATE_KEY_PASS}" \
        -in "${system_signing_request_path}" \
        -out "${system_cert_path}"

    # chmod 444 "${system_cert_path}"

    # Create the fullchain file (leaf + intermediate) for services to serve.
    # Clients only ship with the root/intermediate as a trust anchor, so the
    # server must send the intermediate on the wire; serving only the leaf
    # breaks strict clients (curl/openssl do not fetch missing intermediates
    # the way browsers do via AIA chasing).
    cat "${system_cert_path}" \
        "${INTERMEDIATE_CA_CERT_PATH}" > "${system_fullchain_path}"
}


verify_system_cert() {
    local system_name="${1}"
    msg_header "Verify the cert for system: ${system_name}"

    local system_cert_dir_path="${BASE_SYSTEMS_DIR}/${system_name}"
    local system_cert_path="${system_cert_dir_path}/${system_name}.cert.pem"

    summarise_cert "${system_cert_path}"
    echo

    # Verify the system cert has a valid chain of trust
    openssl verify \
        -CAfile "${INTERMEDIATE_CA_CHAIN_PATH}" \
        "${system_cert_path}"

    # Verify the way a real client does: trust only the root, and rely on the
    # intermediate being served alongside the leaf (as the fullchain file does)
    openssl verify \
        -CAfile "${ROOT_CA_CERT_PATH}" \
        -untrusted "${INTERMEDIATE_CA_CERT_PATH}" \
        "${system_cert_path}"
}


revoke_system_cert() {
    local system_name="${1}"
    msg_header "Revoke system cert: ${system_name}"

    local system_cert_dir_path="${BASE_SYSTEMS_DIR}/${system_name}"
    local system_cert_path="${system_cert_dir_path}/${system_name}.cert.pem"

    # An already-revoked cert makes `openssl ca -revoke` exit non-zero. That is
    # not a failure worth stopping for - it is the normal state when `just
    # renew` is run twice, and stopping there would skip the re-issue that
    # actually replaces the certificate.
    local revoke_output
    if ! revoke_output="$(openssl ca \
        -config "${INTERMEDIATE_CA_CONFIG}" \
        -passin "pass:${INTERMEDIATE_KEY_PASS}" \
        -revoke "${system_cert_path}" 2>&1)"; then
        if [[ "${revoke_output}" == *"Already revoked"* ]]; then
            echo "${system_name} was already revoked; continuing."
        else
            echo "${revoke_output}" >&2
            return 1
        fi
    else
        echo "${revoke_output}"
    fi

    generate_crl

    cat <<EOF

################################################################
# READ THIS - revocation is recorded, not enforced
################################################################
${system_name} is now marked revoked in the CA database, and the CRL at
${INTERMEDIATE_CRL_PATH}
has been regenerated.

Nothing in this repo publishes that CRL, and issued certificates carry no
crlDistributionPoints extension, so no client will ever fetch or check it.
The revoked certificate stays fully trusted everywhere until it expires.

Replacing the certificate is the actual remedy:

    just renew ${system_name}

then deploy the new key and fullchain to the host and restart the service.
EOF
}

# Regenerate the intermediate CRL. Kept current so the artefact exists if the
# CRL is ever published - see the warning in revoke_system_cert.
generate_crl() {
    mkdir -p "${INTERMEDIATE_CA_CRL_DIR}"
    openssl ca \
        -config "${INTERMEDIATE_CA_CONFIG}" \
        -passin "pass:${INTERMEDIATE_KEY_PASS}" \
        -gencrl \
        -out "${INTERMEDIATE_CRL_PATH}"
}
