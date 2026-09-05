#!/bin/bash
################################################################
# DEPRECATED: kept so existing muscle memory and any scripts that call it
# keep working. Superseded by trust_ca.sh, which also handles the browser
# (NSS) trust stores and has a matching untrust_ca.sh.
################################################################
set -euo pipefail

BASE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

echo "NOTE: deploy_ca.sh is deprecated - use 'just trust-system' or ./trust_ca.sh --system" >&2

exec "${BASE_SCRIPT_DIR}/trust_ca.sh" --system "$@"
