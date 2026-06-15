#!/usr/bin/env bash
# Generate an ed25519 SSH key pair for CI APT publish.
#
# Usage:
#   ./create-ci-deploy-key.sh [output-dir]
#
# Writes:
#   dockershelf-deploy-ci      (private — store as GitHub secret DEPLOY_SSH_KEY)
#   dockershelf-deploy-ci.pub  (public — pass to bootstrap-droplet.sh)

set -euo pipefail

OUT_DIR="${1:-.}"
KEY_NAME="dockershelf-deploy-ci"
PRIVATE_KEY="${OUT_DIR}/${KEY_NAME}"
PUBLIC_KEY="${PRIVATE_KEY}.pub"

if [[ -e "$PRIVATE_KEY" || -e "$PUBLIC_KEY" ]]; then
    echo "refusing to overwrite existing key in ${OUT_DIR}" >&2
    exit 1
fi

mkdir -p "$OUT_DIR"
ssh-keygen -t ed25519 -f "$PRIVATE_KEY" -N "" -C "dockershelf-ci-apt-publish"

chmod 600 "$PRIVATE_KEY"
chmod 644 "$PUBLIC_KEY"

cat <<EOF

CI deploy key created:

  Private key: ${PRIVATE_KEY}
  Public key:  ${PUBLIC_KEY}

Next steps:
  1. Add the public key when running bootstrap-droplet.sh:
       DEPLOY_PUBLIC_KEY="\$(cat ${PUBLIC_KEY})" ./bootstrap-droplet.sh

  2. Store the private key as GitHub secret DEPLOY_SSH_KEY (org or repo level):
       gh secret set DEPLOY_SSH_KEY --org Dockershelf < ${PRIVATE_KEY}

  3. Set repository variables (see docs/deploy-setup.md).

EOF

echo "--- public key ---"
cat "$PUBLIC_KEY"
