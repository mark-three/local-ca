################################################################
# Common functions for creating Cert Authorities
################################################################

msg_header() {
    local msg="${1}"

    echo "################################################################"
    echo "# ${msg}"
    echo "################################################################"
}

check_var_not_null() {
    local variable_name="${1}"
    local var_value="${2}"

    if [ -z "${var_value}" ]; then
        echo "Required variable ${variable_name} is empty so program will exit now!"
        exit 1
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

    # Copy the Root CA config, using SED to update the template values
    # Escape the CA path slashes for use in SED, note there are other ways to accomplish this, but this worked first
    local root_ca_dir_esc=$(echo ${ROOT_CA_DIR} | sed 's_/_\\/_g')
    local sed_query="s/ROOT_CA_DIR/${root_ca_dir_esc}/g"
    sed "${sed_query}" "${ROOT_CA_CONFIG_INPUT}" > "${ROOT_CA_CONFIG}"

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

    # Verify the Root CA Certificate
    openssl x509 -noout -text -in "${ROOT_CA_CERT_PATH}"
}

verify_root_ca() {
    msg_header "Verify the Root CA"

    # Verify the Root CA Certificate
    openssl x509 -noout -text -in "${ROOT_CA_CERT_PATH}"
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

    # Copy the Intermediate CA config, using SED to update the template values
    # Escape the CA path slashes for use in SED, note there are other ways to accomplish this, but this worked first
    local intermediate_ca_dir_esc=$(echo ${INTERMEDIATE_CA_DIR} | sed 's_/_\\/_g')
    local sed_query="s/INTERMEDIATE_CA_DIR/${intermediate_ca_dir_esc}/g"
    sed "${sed_query}" "${INTERMEDIATE_CA_CONFIG_INPUT}" > "${INTERMEDIATE_CA_CONFIG}"

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
    
    # Verify the Intermediate CA cert
    openssl x509 -noout -text -in "${INTERMEDIATE_CA_CERT_PATH}"

    # Verify the Intermediate CA cert against the Root CA cert
    openssl verify -CAfile "${ROOT_CA_CERT_PATH}" \
        "${INTERMEDIATE_CA_CERT_PATH}"

    # Create the cert chain file
    cat "${INTERMEDIATE_CA_CERT_PATH}" \
      "${ROOT_CA_CERT_PATH}" > "${INTERMEDIATE_CA_CHAIN_PATH}"
    chmod 444 "${INTERMEDIATE_CA_CHAIN_PATH}"
}

verify_intermediate_ca() {
    msg_header "Verify Intermediate CA"
    # Verify the Intermediate CA cert
    openssl x509 -noout -text -in "${INTERMEDIATE_CA_CERT_PATH}"

    # Verify the Intermediate CA cert against the Root CA cert
    openssl verify -CAfile "${ROOT_CA_CERT_PATH}" \
        "${INTERMEDIATE_CA_CERT_PATH}"

    # Verify if the cert chain needs to be verified
    # "${INTERMEDIATE_CA_CHAIN_PATH}"
}

check_system_config_exists() {
    local system_name="${1}"
    local system_ext_path="${BASE_SYSTEM_CONFIGS_DIR}/${system_name}.ext"
    if [[ ! -f "${system_ext_path}" ]] ; then
        echo "File ${system_ext_path} does not exist, exitting."
        exit
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
        -days 375 -notext -md sha256 \
        -passin "pass:${INTERMEDIATE_KEY_PASS}" \
        -in "${system_signing_request_path}" \
        -out "${system_cert_path}"

    # chmod 444 "${system_cert_path}"
}


verify_system_cert() {
    local system_name="${1}"
    msg_header "Verify the cert for system: ${system_name}"
    
    local system_cert_dir_path="${BASE_SYSTEMS_DIR}/${system_name}"
    local system_cert_path="${system_cert_dir_path}/${system_name}.cert.pem"

    # Verify the system cert
    openssl x509 -noout -text \
      -in "${system_cert_path}"

    # Verify the system cert has a valid chain of trust
    openssl verify \
        -CAfile "${INTERMEDIATE_CA_CHAIN_PATH}" \
        "${system_cert_path}"
}

