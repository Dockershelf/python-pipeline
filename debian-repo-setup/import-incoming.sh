#!/usr/bin/env bash
# Run on the DigitalOcean droplet after rsync delivers .deb files to incoming/.
#
# Usage (from deploy user):
#   ./import-incoming.sh trixie
#   ./import-incoming.sh unstable
#
# Expects:
#   REPO_ROOT=/var/www/debian
#   INCOMING=/var/www/debian/incoming

set -euo pipefail

CODENAME="${1:?usage: import-incoming.sh <trixie|unstable>}"
REPO_ROOT="${REPO_ROOT:-/var/www/debian}"
INCOMING="${INCOMING:-${REPO_ROOT}/incoming}"

shopt -s nullglob
debs=("${INCOMING}"/*.deb)
if [ "${#debs[@]}" -eq 0 ]; then
    echo "No .deb files in ${INCOMING}"
    exit 0
fi

for deb in "${debs[@]}"; do
    echo "Including ${deb} into ${CODENAME}..."
    reprepro -b "${REPO_ROOT}" includedeb "${CODENAME}" "${deb}"
    rm -f "${deb}"
done

echo "Done. Repository updated under ${REPO_ROOT}/dists/${CODENAME}/"
