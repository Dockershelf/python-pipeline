#!/usr/bin/env bash
# Run on the DigitalOcean droplet after rsync delivers .deb files to incoming/.
#
# Usage (from deploy user):
#   ./import-incoming.sh trixie amd64
#   ./import-incoming.sh unstable arm64
#
# Expects:
#   REPO_ROOT=/var/www/debian
#   INCOMING=/var/www/debian/incoming

set -euo pipefail

CODENAME="${1:?usage: import-incoming.sh <trixie|unstable> [arch]}"
ARCH="${2:-}"
REPO_ROOT="${REPO_ROOT:-/var/www/debian}"
INCOMING="${INCOMING:-${REPO_ROOT}/incoming}"
GNUPGHOME="${GNUPGHOME:-${REPO_ROOT}/.gnupg}"
export GNUPGHOME

# Scope to per-arch subdir if ARCH is given (multi-arch publish isolation)
if [[ -n "$ARCH" ]]; then
    INCOMING="${INCOMING}/${ARCH}"
fi

CLEAN_PKGS=()
RETRIED_PKGS=()

deb_matches_codename() {
    local deb="$1"
    # Dockershelf packages encode the suite in the version, e.g. 3.14.6-1+trixie2.
    [[ "$(basename "$deb")" == *"+${CODENAME}"* ]]
}

include_deb() {
    local deb="$1"
    local pkg version rc=0
    pkg="$(dpkg-deb -f "$deb" Package)"
    version="$(dpkg-deb -f "$deb" Version)"

    if reprepro -b "${REPO_ROOT}" list "${CODENAME}" "${pkg}" 2>/dev/null \
        | grep -qF "${version}"; then
        echo "Removing existing ${pkg}=${version} from ${CODENAME} before import..." >&2
        reprepro -b "${REPO_ROOT}" remove "${CODENAME}" "${pkg}" || true
    fi

    if reprepro -b "${REPO_ROOT}" includedeb "${CODENAME}" "${deb}"; then
        CLEAN_PKGS+=("${pkg}")
        return 0
    fi
    rc=$?

    echo "reprepro includedeb failed for ${pkg} (exit ${rc}); removing and retrying once..." >&2
    reprepro -b "${REPO_ROOT}" remove "${CODENAME}" "${pkg}" || true
    reprepro -b "${REPO_ROOT}" includedeb "${CODENAME}" "${deb}"
    RETRIED_PKGS+=("${pkg}")
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

echo "Import summary for ${CODENAME}:"
if [ "${#CLEAN_PKGS[@]}" -gt 0 ]; then
    echo "  clean: ${CLEAN_PKGS[*]}"
fi
if [ "${#RETRIED_PKGS[@]}" -gt 0 ]; then
    echo "  retried: ${RETRIED_PKGS[*]}"
fi

# Regenerate indices (picks up new arches automatically)
reprepro -b "${REPO_ROOT}" export

echo "Done. Repository updated under ${REPO_ROOT}/dists/${CODENAME}/"
