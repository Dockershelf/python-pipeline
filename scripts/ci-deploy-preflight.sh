#!/usr/bin/env bash
# Validate deploy environment before rsync/SSH publish.
#
# Usage:
#   DEPLOY_HOST=... DEPLOY_USER=... DEPLOY_DIR=... DEPLOY_INCOMING=... \
#     ./scripts/ci-deploy-preflight.sh
#
# Options:
#   --connectivity   Also verify SSH login and incoming directory exist.

set -euo pipefail

CONNECTIVITY=0
if [[ "${1:-}" == --connectivity ]]; then
    CONNECTIVITY=1
fi

missing=()
for var in DEPLOY_HOST DEPLOY_USER DEPLOY_DIR DEPLOY_INCOMING; do
    if [[ -z "${!var:-}" ]]; then
        missing+=("$var")
    fi
done

if [[ ${#missing[@]} -gt 0 ]]; then
    echo "missing required deploy variables: ${missing[*]}" >&2
    echo "expected values (see docs/deploy-setup.md):" >&2
    echo "  DEPLOY_HOST=apt.dockershelf.com" >&2
    echo "  DEPLOY_USER=deploy" >&2
    echo "  DEPLOY_DIR=/var/www/debian" >&2
    echo "  DEPLOY_INCOMING=/var/www/debian/incoming" >&2
    exit 1
fi

if [[ "$CONNECTIVITY" -eq 1 ]]; then
    if ! command -v ssh >/dev/null 2>&1; then
        echo "ssh not found in PATH" >&2
        exit 1
    fi
    mkdir -p ~/.ssh
    ssh-keyscan -H "$DEPLOY_HOST" >> ~/.ssh/known_hosts 2>/dev/null || true
    ssh -o BatchMode=yes -o ConnectTimeout=15 \
        "${DEPLOY_USER}@${DEPLOY_HOST}" true
    ssh -o BatchMode=yes -o ConnectTimeout=15 \
        "${DEPLOY_USER}@${DEPLOY_HOST}" \
        "test -d '${DEPLOY_INCOMING}'"
    echo "SSH connectivity OK (${DEPLOY_USER}@${DEPLOY_HOST}, incoming=${DEPLOY_INCOMING})"
else
    echo "deploy variables OK (${DEPLOY_USER}@${DEPLOY_HOST})"
fi
