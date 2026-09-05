#!/bin/bash
################################################################
# pre-commit hook: refuse to commit CA material.
#
# gitleaks and detect-private-key catch secrets by content. This catches them
# by path, which is what actually goes wrong here: the .gitignore protects
# ./output and .env, but a `git add -f`, a renamed output directory or a key
# copied somewhere else while debugging all slip straight past it.
#
# pre-commit passes the staged file names as arguments.
################################################################
set -uo pipefail

# Path patterns that must never be committed.
readonly PATTERNS=(
    '(^|/)\.env$'                 # real credentials; .env.example is fine
    '(^|/)output/'                # the generated CA tree
    '\.key(\.pem)?$'              # private keys
    '\.key\.pem$'
    '-no-pass\.key\.pem$'         # unencrypted service keys
    '\.p12$|\.pfx$|\.jks$'        # key bundles
    '(^|/)private/'               # the CA private directories
    '\.csr(\.pem)?$'              # signing requests
    'ca-chain\.cert\.pem$'
    '\.cert\.pem$'                # issued certs belong on the host, not in git
)

status=0

for file in "$@"; do
    for pattern in "${PATTERNS[@]}"; do
        if [[ "${file}" =~ ${pattern} ]]; then
            echo "BLOCKED: ${file}"
            echo "         matches forbidden path pattern: ${pattern}"
            status=1
            break
        fi
    done
done

if [[ "${status}" -ne 0 ]]; then
    cat <<'EOF'

CA keys and certificates must not be committed. They are generated locally by
'just ca' / 'just cert NAME' and belong only on the machine that uses them.

If a file was staged by accident:
    git restore --staged <file>

If you are certain a match is a false positive, add an exclusion in
.pre-commit-config.yaml rather than passing --no-verify.
EOF
fi

exit "${status}"
