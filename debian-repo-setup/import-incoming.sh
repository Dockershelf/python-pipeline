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
GNUPGHOME="${GNUPGHOME:-${REPO_ROOT}/.gnupg}"
export GNUPGHOME

deb_matches_codename() {
    local deb="$1"
    # Dockershelf packages encode the suite in the version, e.g. 3.14.6-1+trixie2.
    [[ "$(basename "$deb")" == *"+${CODENAME}"* ]]
}

include_deb() {
    local deb="$1"
    local pkg
    pkg="$(dpkg-deb -f "$deb" Package)"

    if reprepro -b "${REPO_ROOT}" includedeb "${CODENAME}" "${deb}"; then
        return 0
    fi

    local rc=$?
    echo "reprepro includedeb failed for ${pkg} (exit ${rc}); removing and retrying once..." >&2
    reprepro -b "${REPO_ROOT}" remove "${CODENAME}" "${pkg}" || true
    reprepro -b "${REPO_ROOT}" includedeb "${CODENAME}" "${deb}"
}

shopt -s nullglob
debs=("${INCOMING}"/*.deb)
if [ "${#debs[@]}" -eq 0 ]; then
    echo "No .deb files in ${INCOMING}"
    exit 0
fi

matched=0
for deb in "${debs[@]}"; do
    if ! deb_matches_codename "$deb"; then
        echo "Skipping ${deb} (not for ${CODENAME})"
        continue
    fi
    matched=$((matched + 1))
    echo "Including ${deb} into ${CODENAME}..."
    include_deb "$deb"
    rm -f "${deb}"
done

if [ "$matched" -eq 0 ]; then
    echo "No .deb files for ${CODENAME} in ${INCOMING}" >&2
    exit 1
fi

echo "Done. Repository updated under ${REPO_ROOT}/dists/${CODENAME}/"
