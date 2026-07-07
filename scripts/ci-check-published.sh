#!/usr/bin/env bash
# Check whether a package version is already in the public APT repository.
#
# When already published, sets GITHUB_OUTPUT skip=true so CI can skip build/smoke/publish.
#
# Usage (from packaging repo root, changelog mode):
#   ./scripts/ci-check-published.sh trixie amd64
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

APT_URL="${DOCKERSHELF_APT_URL:-https://apt.dockershelf.com/dockershelf}"

write_outputs() {
    local skip="$1"
    local reason="$2"
    if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
        echo "skip=${skip}" >>"$GITHUB_OUTPUT"
        echo "reason=${reason}" >>"$GITHUB_OUTPUT"
    fi
    echo "${reason}"
}

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

PACKAGES_URL="${APT_URL}/dists/${CODENAME}/main/binary-${ARCH}/Packages.gz"
PACKAGES=""
if ! PACKAGES="$(curl -fsSL "$PACKAGES_URL" | zcat 2>/dev/null)"; then
    write_outputs false "skip=false (could not fetch ${PACKAGES_URL})"
    exit 0
fi

published=0
if awk -v pkg="$PKG" -v ver="$VERSION" '
    $1 == "Package:" && $2 == pkg { inpkg = 1; next }
    inpkg && $1 == "Package:" { inpkg = 0 }
    inpkg && $1 == "Version:" && $2 == ver { found = 1; exit }
    END { exit !found }
' <<<"$PACKAGES"; then
    published=1
fi

if [[ "$published" -eq 1 ]]; then
    write_outputs true "skip=true: ${PKG}=${VERSION} already in ${CODENAME}/${ARCH}"
    exit 0
fi

write_outputs false "skip=false: ${PKG}=${VERSION} not yet in ${CODENAME}/${ARCH}"
exit 0
