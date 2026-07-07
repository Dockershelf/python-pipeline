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

CODENAME="${1:?usage: import-incoming.sh <trixie|unstable> [arch] [publish-id]}"
ARCH="${2:-}"
PUBLISH_ID="${3:-}"
REPO_ROOT="${REPO_ROOT:-/var/www/debian}"
INCOMING="${INCOMING:-${REPO_ROOT}/incoming}"
GNUPGHOME="${GNUPGHOME:-${REPO_ROOT}/.gnupg}"
PUBLISH_LOCK="${PUBLISH_LOCK:-${REPO_ROOT}/.publish.lock}"
export GNUPGHOME

# The script holds PUBLISH_LOCK on fd 9 for the entire import loop (see below),
# so reprepro calls are already serialized. This wrapper is intentionally a
# plain reprepro invocation — re-locking the same file from the same process
# deadlocks on Linux (flock locks are per open-file-description, not per pid).
reprepro_locked() {
    reprepro "$@"
}

# Validate PUBLISH_ID: it is used in a path, so reject anything outside
# [A-Za-z0-9._-] to prevent path traversal/escape.
if [[ -n "${PUBLISH_ID}" ]] && [[ ! "${PUBLISH_ID}" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "invalid PUBLISH_ID: ${PUBLISH_ID}" >&2
    exit 1
fi

# Scope to per-arch subdir if ARCH is given (multi-arch publish isolation).
# If PUBLISH_ID is also given, scope further to a unique per-publish subdir so
# concurrent publishes (from different repos/pipelines sharing the droplet)
# only process the files they rsync'd and cannot delete each other's files.
if [[ -n "$ARCH" ]]; then
    INCOMING="${INCOMING}/${ARCH}"
fi
if [[ -n "$PUBLISH_ID" ]]; then
    INCOMING="${INCOMING}/${PUBLISH_ID}"
fi

# Clean up the per-publish subdir on exit so failed imports don't leave
# stale .deb files accumulating on the droplet.
if [[ -n "${PUBLISH_ID}" ]]; then
    trap 'rm -rf "${INCOMING}" 2>/dev/null || true' EXIT
fi

CLEAN_PKGS=()
RETRIED_PKGS=()

deb_matches_codename() {
    local deb="$1"
    # Dockershelf packages encode the suite in the version, e.g. 3.14.6-1+trixie2.
    [[ "$(basename "$deb")" == *"+${CODENAME}"* ]]
}

deb_matches_arch() {
    local deb="$1"
    [[ -z "$ARCH" ]] || [[ "$(basename "$deb")" == *_"${ARCH}".deb ]]
}

include_deb() {
    local deb="$1"
    local pkg version rc=0
    pkg="$(dpkg-deb -f "$deb" Package)"
    version="$(dpkg-deb -f "$deb" Version)"

    # Scope reprepro operations to the target architecture when ARCH is set.
    # Without -A, `reprepro remove <codename> <pkg>` deletes the package for
    # ALL architectures and removes every arch's pool file — a concurrent or
    # prior publish of another arch would then lose its files. -A limits the
    # list/remove to the arch being imported so cross-arch pool files survive.
    local arch_args=()
    if [[ -n "${ARCH:-}" ]]; then
        arch_args=(-A "${ARCH}")
    fi

    if reprepro_locked -b "${REPO_ROOT}" "${arch_args[@]}" list "${CODENAME}" "${pkg}" 2>/dev/null \
        | grep -qF "${version}"; then
        echo "Removing existing ${pkg}=${version} from ${CODENAME}/${ARCH:-all} before import..." >&2
        reprepro_locked -b "${REPO_ROOT}" "${arch_args[@]}" remove "${CODENAME}" "${pkg}" || true
    fi

    if reprepro_locked -b "${REPO_ROOT}" includedeb "${CODENAME}" "${deb}"; then
        CLEAN_PKGS+=("${pkg}")
        return 0
    fi
    rc=$?

    echo "reprepro includedeb failed for ${pkg} (exit ${rc}); removing and retrying once..." >&2
    reprepro_locked -b "${REPO_ROOT}" "${arch_args[@]}" remove "${CODENAME}" "${pkg}" || true
    reprepro_locked -b "${REPO_ROOT}" includedeb "${CODENAME}" "${deb}"
    RETRIED_PKGS+=("${pkg}")
}

shopt -s nullglob
debs=("${INCOMING}"/*.deb)
if [ "${#debs[@]}" -eq 0 ]; then
    echo "No .deb files in ${INCOMING}"
    exit 0
fi

# Hold the publish lock for the entire import so concurrent publishes from
# different repos/pipelines (which share the same reprepro repo and lock file)
# serialize at the droplet. The per-command reprepro_locked() is not sufficient
# because the read-remove-include-rm sequence must be atomic.
exec 9>"$PUBLISH_LOCK"
flock -w 600 9

matched=0
for deb in "${debs[@]}"; do
    if ! deb_matches_codename "$deb"; then
        echo "Skipping ${deb} (not for ${CODENAME})"
        continue
    fi
    if ! deb_matches_arch "$deb"; then
        echo "Skipping ${deb} (not for ${ARCH})"
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
