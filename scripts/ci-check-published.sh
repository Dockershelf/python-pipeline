#!/usr/bin/env bash
# Check whether a package version is already in the APT repository on the droplet.
#
# When already published, sets GITHUB_OUTPUT skip=true so CI can skip build/smoke/publish.
# When DEPLOY_HOST is unset, always sets skip=false (local / unconfigured publish).
#
# Usage (from packaging repo root, changelog mode):
#   DEPLOY_HOST=... DEPLOY_USER=... DEPLOY_DIR=... \
#     ./scripts/ci-check-published.sh trixie amd64
#
# Usage (from a directory with .deb files, deb mode):
#   ./scripts/ci-check-published.sh --deb dist trixie amd64

set -euo pipefail

DEB_DIR=""
if [[ "${1:-}" == --deb ]]; then
    DEB_DIR="${2:?usage: ci-check-published.sh --deb <dir> <trixie|unstable> <arch>}"
    shift 2
fi

CODENAME="${1:?usage: ci-check-published.sh [--deb <dir>] <trixie|unstable> <arch>}"
ARCH="${2:?usage: ci-check-published.sh [--deb <dir>] <trixie|unstable> <arch>}"

write_outputs() {
    local skip="$1"
    local reason="$2"
    if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
        echo "skip=${skip}" >>"$GITHUB_OUTPUT"
        echo "reason=${reason}" >>"$GITHUB_OUTPUT"
    fi
    echo "${reason}"
}

if [[ -z "${DEPLOY_HOST:-}" ]]; then
    write_outputs false "skip=false (DEPLOY_HOST not configured)"
    exit 0
fi

for var in DEPLOY_USER DEPLOY_DIR; do
    if [[ -z "${!var:-}" ]]; then
        echo "missing ${var}" >&2
        exit 1
    fi
done

if [[ -n "$DEB_DIR" ]]; then
    shopt -s nullglob
    debs=("${DEB_DIR}"/*.deb)
    if [[ ${#debs[@]} -eq 0 ]]; then
        echo "no .deb files in ${DEB_DIR}" >&2
        exit 1
    fi
    PKG="$(dpkg-deb -f "${debs[0]}" Package)"
    VERSION="$(dpkg-deb -f "${debs[0]}" Version)"
else
    CHANGELOG="changelogs/mainline/${CODENAME}"
    CONTROL="debiandirs/${CODENAME}/control"
    if [[ ! -f "$CHANGELOG" ]]; then
        echo "missing ${CHANGELOG}" >&2
        exit 1
    fi
    if [[ ! -f "$CONTROL" ]]; then
        echo "missing ${CONTROL}" >&2
        exit 1
    fi
    if command -v dpkg-parsechangelog >/dev/null 2>&1; then
        VERSION="$(dpkg-parsechangelog --file "$CHANGELOG" --show-field=Version)"
    else
        VERSION="$(sed -n '1s/.*(\([^)]*\)).*/\1/p' "$CHANGELOG")"
    fi
    PKG="$(awk '/^Package: / { print $2; exit }' "$CONTROL")"
fi

if [[ -z "$PKG" || -z "$VERSION" ]]; then
    echo "could not resolve package name or version" >&2
    exit 1
fi

LIST="$(
    ssh -o BatchMode=yes -o ConnectTimeout=15 \
        "${DEPLOY_USER}@${DEPLOY_HOST}" \
        "GNUPGHOME=${DEPLOY_DIR}/.gnupg reprepro -b ${DEPLOY_DIR} list ${CODENAME} ${PKG} 2>/dev/null" \
        || true
)"

published=0
while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if [[ "$line" == *"|${VERSION}|${ARCH}"* ]]; then
        published=1
        break
    fi
    if [[ "$line" == *"|${VERSION}|all"* ]]; then
        published=1
        break
    fi
done <<<"$LIST"

if [[ "$published" -eq 1 ]]; then
    write_outputs true "skip=true: ${PKG}=${VERSION} already in ${CODENAME} for ${ARCH}"
    exit 0
fi

write_outputs false "skip=false: ${PKG}=${VERSION} not yet in ${CODENAME} for ${ARCH}"
exit 0
