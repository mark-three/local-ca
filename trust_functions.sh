# shellcheck shell=bash
################################################################
# Functions for installing / removing the local CA from the
# operating system and browser (NSS) trust stores.
#
# Sourced by trust_ca.sh and untrust_ca.sh. Requires .env and
# common_functions.sh to have been sourced first.
################################################################

# File names used inside the system trust store directory. Each file holds
# exactly ONE certificate on purpose - see the note in install_system_trust.
SYSTEM_TRUST_ROOT_FILE="local-ca-root.crt"
SYSTEM_TRUST_INTERMEDIATE_FILE="local-ca-intermediate.crt"

# Legacy file name from earlier versions of deploy_ca.sh, cleaned up on install.
SYSTEM_TRUST_LEGACY_FILE="myCA.crt"

################################################################
# System trust store
################################################################

# Print the absolute path of a trust store tool, searching the sbin directories
# as well as PATH. Distros ship these in /usr/sbin, which is not on a regular
# user's PATH on Debian - so `command -v update-ca-certificates` finds nothing
# even on a machine that plainly has it.
find_sbin() {
    local tool="${1}"
    local dir

    if command -v "${tool}" >/dev/null 2>&1; then
        command -v "${tool}"
        return 0
    fi
    for dir in /usr/sbin /sbin /usr/local/sbin; do
        if [[ -x "${dir}/${tool}" ]]; then
            echo "${dir}/${tool}"
            return 0
        fi
    done
    return 1
}

# Print the trust store flavour of this machine: debian, rhel, arch or unknown.
detect_system_trust_flavour() {
    if [[ -d /usr/local/share/ca-certificates ]] && find_sbin update-ca-certificates >/dev/null; then
        echo "debian"
    elif find_sbin update-ca-trust >/dev/null; then
        echo "rhel"
    elif [[ -d /etc/ca-certificates/trust-source/anchors ]] && find_sbin trust >/dev/null; then
        echo "arch"
    else
        echo "unknown"
    fi
}

# Print the directory that locally-added anchors belong in.
system_trust_dir() {
    case "$(detect_system_trust_flavour)" in
        debian) echo "/usr/local/share/ca-certificates" ;;
        rhel)   echo "/etc/pki/ca-trust/source/anchors" ;;
        arch)   echo "/etc/ca-certificates/trust-source/anchors" ;;
        *)      return 1 ;;
    esac
}

# Print the CApath that clients read the rebuilt bundle from.
system_trust_ca_path() {
    case "$(detect_system_trust_flavour)" in
        rhel) echo "/etc/pki/tls/certs" ;;
        *)    echo "/etc/ssl/certs" ;;
    esac
}

# Rebuild the consolidated system bundle after adding or removing an anchor.
# The absolute path is used so this works from a shell without sbin on PATH.
system_trust_update() {
    case "$(detect_system_trust_flavour)" in
        debian) sudo "$(find_sbin update-ca-certificates)" ;;
        rhel)   sudo "$(find_sbin update-ca-trust)" extract ;;
        arch)   sudo "$(find_sbin trust)" extract-compat ;;
        *)      return 1 ;;
    esac
}

# Fail with a useful message if this machine has no trust store we understand.
require_system_trust_store() {
    if [[ "$(detect_system_trust_flavour)" == "unknown" ]]; then
        echo "ERROR: could not detect a supported system trust store." >&2
        echo "       Supported: Debian/Ubuntu (update-ca-certificates)," >&2
        echo "                  RHEL/Fedora (update-ca-trust)," >&2
        echo "                  Arch (trust extract-compat)." >&2
        echo "       Install the CA by hand - see 'just trust-help'." >&2
        return 1
    fi
}

install_system_trust() {
    msg_header "Install the CA into the system trust store"

    require_system_trust_store
    require_ca_built

    local trust_dir
    trust_dir="$(system_trust_dir)"

    # update-ca-certificates only ingests files ending in .crt, and only reads
    # the FIRST certificate in each file. Installing the ca-chain bundle as one
    # file therefore silently drops the root - so root and intermediate go in
    # as two separate single-certificate files.
    echo "Installing into ${trust_dir} (requires sudo)"
    sudo rm -f "${trust_dir:?}/${SYSTEM_TRUST_LEGACY_FILE}"
    sudo install -m 644 "${ROOT_CA_CERT_PATH}" "${trust_dir}/${SYSTEM_TRUST_ROOT_FILE}"
    sudo install -m 644 "${INTERMEDIATE_CA_CERT_PATH}" "${trust_dir}/${SYSTEM_TRUST_INTERMEDIATE_FILE}"
    system_trust_update

    verify_system_trust
}

remove_system_trust() {
    msg_header "Remove the CA from the system trust store"

    require_system_trust_store

    local trust_dir
    trust_dir="$(system_trust_dir)"

    echo "Removing from ${trust_dir} (requires sudo)"
    sudo rm -f \
        "${trust_dir:?}/${SYSTEM_TRUST_ROOT_FILE}" \
        "${trust_dir:?}/${SYSTEM_TRUST_INTERMEDIATE_FILE}" \
        "${trust_dir:?}/${SYSTEM_TRUST_LEGACY_FILE}"
    system_trust_update

    if system_trust_has_ca; then
        echo "WARNING: the CA still verifies against the system store." >&2
        echo "         It may have been installed by hand under a different name." >&2
        return 1
    fi
    echo "OK: the CA is no longer in the system trust store."
}

# Return 0 if the system store currently trusts the Root CA.
system_trust_has_ca() {
    openssl verify -CApath "$(system_trust_ca_path)" "${ROOT_CA_CERT_PATH}" >/dev/null 2>&1
}

verify_system_trust() {
    msg_header "Verify the CA is in the system trust store"

    local ca_path
    ca_path="$(system_trust_ca_path)"

    # Verify the way a client does: chain each cert against the rebuilt store.
    openssl verify -CApath "${ca_path}" "${ROOT_CA_CERT_PATH}"
    openssl verify -CApath "${ca_path}" "${INTERMEDIATE_CA_CERT_PATH}"
}

################################################################
# Browser (NSS) trust stores
################################################################

# Print every NSS database on this machine, one "sql:/path" per line.
# Chrome/Chromium/Edge share ~/.pki/nssdb; Firefox keeps one per profile,
# including the snap and flatpak locations.
nss_db_paths() {
    local dir
    local -a candidates=()

    shopt -s nullglob
    candidates+=("${HOME}/.pki/nssdb")
    candidates+=("${HOME}"/.mozilla/firefox/*/)
    candidates+=("${HOME}"/snap/firefox/common/.mozilla/firefox/*/)
    candidates+=("${HOME}"/.var/app/org.mozilla.firefox/.mozilla/firefox/*/)
    shopt -u nullglob

    for dir in "${candidates[@]}"; do
        dir="${dir%/}"
        # cert9.db is the modern (sql) NSS database. A directory without one is
        # not a real profile - except ~/.pki/nssdb, which we create on demand.
        if [[ -f "${dir}/cert9.db" || "${dir}" == "${HOME}/.pki/nssdb" ]]; then
            echo "sql:${dir}"
        fi
    done
}

# Fail with per-distro install instructions if certutil is missing.
require_certutil() {
    if command -v certutil >/dev/null 2>&1; then
        return 0
    fi

    echo "ERROR: certutil not found - it lives in the NSS tools package." >&2
    echo >&2
    case "$(detect_system_trust_flavour)" in
        debian) echo "    sudo apt install libnss3-tools" >&2 ;;
        rhel)   echo "    sudo dnf install nss-tools" >&2 ;;
        arch)   echo "    sudo pacman -S nss" >&2 ;;
        *)      echo "    Install your distribution's NSS tools package (libnss3-tools / nss-tools / nss)." >&2 ;;
    esac
    echo >&2
    echo "Then re-run this command. To import by hand instead, see 'just trust-help'." >&2
    return 1
}

install_nss_trust() {
    msg_header "Install the Root CA into the browser (NSS) trust stores"

    require_certutil
    require_ca_built

    # Browsers must trust the ROOT, not the chain file: most import paths read
    # only the first certificate in a multi-cert file, so importing
    # ca-chain.cert.pem installs the intermediate and leaves you untrusted.
    local db
    local installed=0

    # Chrome reads ~/.pki/nssdb even when it does not exist yet; create it so
    # the CA is trusted the first time Chrome starts.
    if [[ ! -f "${HOME}/.pki/nssdb/cert9.db" ]]; then
        echo "Creating empty NSS database at ${HOME}/.pki/nssdb"
        mkdir -p "${HOME}/.pki/nssdb"
        certutil -d "sql:${HOME}/.pki/nssdb" -N --empty-password
    fi

    while read -r db; do
        [[ -n "${db}" ]] || continue
        echo "Importing '${ROOT_CA_CN}' into ${db}"
        # Delete first so re-running does not stack duplicate nicknames.
        certutil -d "${db}" -D -n "${ROOT_CA_CN}" >/dev/null 2>&1 || true
        # "C,," trusts this CA to identify websites (and nothing else).
        certutil -d "${db}" -A -t "C,," -n "${ROOT_CA_CN}" -i "${ROOT_CA_CERT_PATH}"
        installed=$((installed + 1))
    done < <(nss_db_paths)

    if [[ "${installed}" -eq 0 ]]; then
        echo "No NSS databases found - no browser profiles to update." >&2
        return 0
    fi

    echo "Imported into ${installed} NSS database(s)."
    echo "NOTE: restart any running browser for the change to take effect."
}

remove_nss_trust() {
    msg_header "Remove the Root CA from the browser (NSS) trust stores"

    require_certutil

    local db
    local removed=0

    while read -r db; do
        [[ -n "${db}" ]] || continue
        if certutil -d "${db}" -D -n "${ROOT_CA_CN}" >/dev/null 2>&1; then
            echo "Removed '${ROOT_CA_CN}' from ${db}"
            removed=$((removed + 1))
        fi
    done < <(nss_db_paths)

    echo "Removed from ${removed} NSS database(s)."
    if [[ "${removed}" -gt 0 ]]; then
        echo "NOTE: restart any running browser for the change to take effect."
    fi
}

################################################################
# Status and manual instructions
################################################################

trust_status() {
    msg_header "Local CA trust status"

    if [[ ! -f "${ROOT_CA_CERT_PATH}" ]]; then
        echo "Root CA:  NOT BUILT (${ROOT_CA_CERT_PATH} is missing)"
        echo "Run 'just ca' to build it."
        return 0
    fi

    echo "Root CA:  ${ROOT_CA_CERT_PATH}"
    echo "  CN:     ${ROOT_CA_CN}"
    echo "  Expiry: $(openssl x509 -noout -enddate -in "${ROOT_CA_CERT_PATH}" | cut -d= -f2)"
    echo

    echo "System trust store ($(detect_system_trust_flavour)):"
    if system_trust_has_ca; then
        echo "  TRUSTED"
    else
        echo "  not trusted - run 'just trust-system'"
    fi
    echo

    echo "Browser (NSS) trust stores:"
    if ! command -v certutil >/dev/null 2>&1; then
        echo "  certutil not installed - cannot check. Run 'just trust-help'."
        return 0
    fi
    local db found
    found=0
    while read -r db; do
        [[ -n "${db}" ]] || continue
        found=1
        if certutil -d "${db}" -L -n "${ROOT_CA_CN}" >/dev/null 2>&1; then
            echo "  TRUSTED      ${db}"
        else
            echo "  not trusted  ${db}"
        fi
    done < <(nss_db_paths)
    [[ "${found}" -eq 1 ]] || echo "  no NSS databases found"
}

print_manual_instructions() {
    local flavour
    flavour="$(detect_system_trust_flavour)"

    cat <<EOF
################################################################
# Trusting ${ROOT_CA_CN} by hand
################################################################

Root CA certificate:
    ${ROOT_CA_CERT_PATH}

Scripted route - install the NSS tools, then re-run 'just trust':
EOF

    case "${flavour}" in
        debian) echo "    sudo apt install libnss3-tools" ;;
        rhel)   echo "    sudo dnf install nss-tools" ;;
        arch)   echo "    sudo pacman -S nss" ;;
        *)      echo "    <install your distribution's NSS tools package>" ;;
    esac

    cat <<EOF
    just trust

Or by hand:
    Firefox   Settings -> Privacy & Security -> Certificates ->
              View Certificates -> Authorities -> Import ->
              ${ROOT_CA_CERT_PATH}
              and tick "Trust this CA to identify websites".
    Chrome    Settings -> Privacy and security -> Security ->
              Manage certificates -> Authorities -> Import, same file.

For curl and other CLI tools, which use the system anchors rather than either
browser store, run these yourself:

EOF

    if [[ "${flavour}" == "unknown" ]]; then
        echo "    <copy ${ROOT_CA_CERT_PATH} into your distribution's anchor directory and rebuild the bundle>"
    else
        echo "    sudo cp ${ROOT_CA_CERT_PATH} $(system_trust_dir)/${SYSTEM_TRUST_ROOT_FILE}"
        echo "    sudo cp ${INTERMEDIATE_CA_CERT_PATH} $(system_trust_dir)/${SYSTEM_TRUST_INTERMEDIATE_FILE}"
        case "${flavour}" in
            debian) echo "    sudo $(find_sbin update-ca-certificates)" ;;
            rhel)   echo "    sudo $(find_sbin update-ca-trust) extract" ;;
            arch)   echo "    sudo $(find_sbin trust) extract-compat" ;;
        esac
    fi

    cat <<EOF

Until then, pass the CA explicitly:

    curl --cacert ${ROOT_CA_CERT_PATH} https://your-service.local/
EOF
}
