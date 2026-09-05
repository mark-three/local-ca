# local-ca - task runner
#
# Run `just` with no arguments to list every recipe.

set shell := ["bash", "-euo", "pipefail", "-c"]

root := justfile_directory()

# Show all available recipes
default:
    @just --list --unsorted

################################################################
# Setup
################################################################

# Create .env from the example if it does not exist yet
init:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ -f "{{ root }}/.env" ]]; then
        echo ".env already exists - leaving it alone."
    else
        cp "{{ root }}/.env.example" "{{ root }}/.env"
        echo "Created .env from .env.example."
        echo "Edit it now: set ROOT_KEY_PASS / INTERMEDIATE_KEY_PASS / SYSTEM_KEY_PASS"
        echo "and the certificate subject values."
    fi

# Install the git hooks (pre-commit, commit-msg, pre-push)
setup:
    pre-commit install --install-hooks
    pre-commit install --hook-type commit-msg
    pre-commit install --hook-type pre-push
    @echo "Hooks installed. Commit messages are now checked against Conventional Commits."

# Check that the tools this repo needs are present
doctor:
    #!/usr/bin/env bash
    set -uo pipefail
    status=0
    check() {
        local tool="${1}" why="${2}" hint="${3:-}"
        if command -v "${tool}" >/dev/null 2>&1; then
            printf '  ok       %-12s %s\n' "${tool}" "${why}"
        else
            printf '  MISSING  %-12s %s\n' "${tool}" "${why}"
            [[ -n "${hint}" ]] && printf '           install: %s\n' "${hint}"
            status=1
        fi
    }
    echo "Required:"
    check openssl    "generate and inspect certificates"
    check getopt     "argument parsing in the scripts"
    echo "Trust stores:"
    check certutil   "browser (NSS) trust stores" "sudo apt install libnss3-tools"
    echo "Development:"
    check pre-commit "git hooks"                  "pipx install pre-commit"
    check cz         "conventional commit helper" "pipx install commitizen"
    echo
    if [[ -f "{{ root }}/.env" ]]; then
        echo "  ok       .env         present"
    else
        echo "  MISSING  .env         run 'just init'"
        status=1
    fi
    exit "${status}"

################################################################
# Certificate authority
################################################################

# Create the Root CA, Intermediate CA and chain (prompts before overwriting)
ca *ARGS:
    "{{ root }}/create_root_intermediate_ca.sh" {{ ARGS }}

# Scaffold configs/systems/NAME.ext from the example, ready to edit
new-system NAME:
    #!/usr/bin/env bash
    set -euo pipefail
    src="{{ root }}/configs/systems/example.ext"
    dest="{{ root }}/configs/systems/{{ NAME }}.ext"
    if [[ -f "${dest}" ]]; then
        echo "${dest} already exists - edit it directly."
        exit 0
    fi
    sed 's/\bexample\b/{{ NAME }}/g' "${src}" > "${dest}"
    echo "Created ${dest}"
    echo "Edit the [alt_names] block so the DNS and IP entries match the host,"
    echo "then run: just cert {{ NAME }}"

# Issue a certificate for a system (needs configs/systems/NAME.ext)
cert NAME:
    "{{ root }}/create_system_cert.sh" --system "{{ NAME }}"

# Revoke a system certificate
revoke NAME:
    "{{ root }}/revoke_system_cert.sh" --system "{{ NAME }}"

# Revoke and re-issue a system certificate
renew NAME: (revoke NAME) (cert NAME)

# Show the certificate chain and expiry for a system
verify NAME:
    #!/usr/bin/env bash
    set -euo pipefail
    source "{{ root }}/.env"
    cert="${BASE_SYSTEMS_DIR}/{{ NAME }}/{{ NAME }}.cert.pem"
    [[ -f "${cert}" ]] || { echo "No certificate at ${cert}" >&2; exit 1; }
    openssl x509 -noout -subject -issuer -dates -ext subjectAltName -in "${cert}"
    echo
    # Verify the way a strict client does: trust only the root, and rely on the
    # intermediate being served alongside the leaf (as the fullchain file is).
    openssl verify -CAfile "${ROOT_CA_CERT_PATH}" \
        -untrusted "${INTERMEDIATE_CA_CERT_PATH}" "${cert}"

# List every issued certificate with its expiry date
list:
    #!/usr/bin/env bash
    set -euo pipefail
    source "{{ root }}/.env"
    if [[ ! -d "${BASE_SYSTEMS_DIR}" ]]; then
        echo "No certificates issued yet."
        exit 0
    fi
    printf '%-24s %-28s %s\n' "SYSTEM" "EXPIRES" "STATUS"
    for dir in "${BASE_SYSTEMS_DIR}"/*/; do
        name="$(basename "${dir}")"
        cert="${dir}${name}.cert.pem"
        [[ -f "${cert}" ]] || continue
        expiry="$(openssl x509 -noout -enddate -in "${cert}" | cut -d= -f2)"
        if openssl x509 -noout -checkend 0 -in "${cert}" >/dev/null 2>&1; then
            if openssl x509 -noout -checkend 2592000 -in "${cert}" >/dev/null 2>&1; then
                status="valid"
            else
                status="expires within 30 days"
            fi
        else
            status="EXPIRED"
        fi
        printf '%-24s %-28s %s\n' "${name}" "${expiry}" "${status}"
    done

################################################################
# Trust stores
################################################################

# Install the CA into both the system and browser trust stores
trust:
    "{{ root }}/trust_ca.sh"

# Install the CA into the system trust store only (curl, python, wget - uses sudo)
trust-system:
    "{{ root }}/trust_ca.sh" --system

# Install the CA into the browser (Chrome/Firefox NSS) trust stores only
trust-browsers:
    "{{ root }}/trust_ca.sh" --browsers

# Show where the CA is currently trusted
trust-status:
    @"{{ root }}/trust_ca.sh" --status

# Print copy-paste instructions for trusting the CA by hand
trust-help:
    @"{{ root }}/trust_ca.sh" --instructions

# Remove the CA from both trust stores (leaves ./output alone)
untrust:
    "{{ root }}/untrust_ca.sh"

################################################################
# Removal
################################################################

# Remove the CA from every trust store AND delete the generated output
uninstall:
    #!/usr/bin/env bash
    set -euo pipefail
    source "{{ root }}/.env"
    echo "This removes ${ROOT_CA_CN} from the system and browser trust stores"
    echo "and deletes ${CA_BASE_DIR}, including every key and issued certificate."
    echo
    read -r -p "Type 'yes' to continue: " confirm
    if [[ "${confirm}" != "yes" ]]; then
        echo "Aborted; nothing was changed."
        exit 1
    fi
    "{{ root }}/untrust_ca.sh"
    rm -rf "${CA_BASE_DIR:?}"
    echo "Deleted ${CA_BASE_DIR}"
    echo
    echo "Certificates already deployed to your services are now untrusted"
    echo "and cannot be revoked - remove them from those hosts too."

# Delete the generated output only, leaving the trust stores as they are
clean:
    #!/usr/bin/env bash
    set -euo pipefail
    source "{{ root }}/.env"
    read -r -p "Delete ${CA_BASE_DIR}? Type 'yes' to continue: " confirm
    [[ "${confirm}" == "yes" ]] || { echo "Aborted."; exit 1; }
    rm -rf "${CA_BASE_DIR:?}"
    echo "Deleted ${CA_BASE_DIR}"

################################################################
# Development
################################################################

# Run every pre-commit hook against the whole tree
lint:
    pre-commit run --all-files

# Update the pinned pre-commit hook versions
lint-update:
    pre-commit autoupdate

# Write a Conventional Commit interactively
commit:
    cz commit

# Check that the staged commit message follows Conventional Commits
check-commit:
    cz check --rev-range HEAD~1..HEAD
