#!/usr/bin/env bash
# Rsync .deb files to the APT droplet and run reprepro import (same as make publish).
#
# Usage:
#   DEPLOY_HOST=... DEPLOY_USER=... DEPLOY_DIR=... DEPLOY_INCOMING=... \
#     ./scripts/ci-publish.sh trixie /path/to/dist amd64

set -euo pipefail

CODENAME="${1:?usage: ci-publish.sh <trixie|unstable> <dist-dir> [arch]}"
DIST_DIR="${2:?usage: ci-publish.sh <trixie|unstable> <dist-dir> [arch]}"
ARCH="${3:-amd64}"

HOST="${DEPLOY_HOST:?DEPLOY_HOST required}"
USER="${DEPLOY_USER:?DEPLOY_USER required}"
REPO_ROOT="${DEPLOY_DIR:?DEPLOY_DIR required}"
INCOMING="${DEPLOY_INCOMING:?DEPLOY_INCOMING required}"

DIST_DIR="$(cd "$DIST_DIR" && pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMPORT_SCRIPT="$SCRIPT_DIR/../debian-repo-setup/import-incoming.sh"

# Per-arch incoming subdir (avoids clobbering between concurrent arch publishes)
REMOTE_INCOMING="${INCOMING}/${ARCH}"

shopt -s nullglob
debs=("$DIST_DIR"/*.deb)
if [[ ${#debs[@]} -eq 0 ]]; then
    echo "no .deb files in $DIST_DIR" >&2
    exit 1
fi

echo "Publishing ${#debs[@]} package(s) for ${CODENAME}/${ARCH} to ${USER}@${HOST}:${REMOTE_INCOMING}/"
ssh "${USER}@${HOST}" "mkdir -p ${REMOTE_INCOMING}"
rsync -av --delete "${debs[@]}" "${USER}@${HOST}:${REMOTE_INCOMING}/"

ssh "${USER}@${HOST}" \
    "REPO_ROOT=${REPO_ROOT} INCOMING=${INCOMING} bash -s ${CODENAME} ${ARCH}" \
    <"$IMPORT_SCRIPT"

echo "Published to ${CODENAME}/${ARCH}"
