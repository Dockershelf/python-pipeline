#!/usr/bin/env bash
# Prepare CI workspace: init cpython submodule and export image env vars.
#
# Usage:
#   PY_REPO_DIR=/path/to/py3.14 PIPELINE_DIR=/path/to/python-pipeline \
#     ./scripts/ci-setup-workspace.sh
#
# Or pass positional args: ./ci-setup-workspace.sh /path/to/py3.14 [/path/to/python-pipeline]

set -euo pipefail

PY_REPO_DIR="${PY_REPO_DIR:-${1:-}}"
PIPELINE_DIR="${PIPELINE_DIR:-${2:-}}"

if [[ -z "$PY_REPO_DIR" ]]; then
    echo "PY_REPO_DIR required (env or first argument)" >&2
    exit 1
fi

PY_REPO_DIR="$(cd "$PY_REPO_DIR" && pwd)"
PIPELINE_DIR="${PIPELINE_DIR:-$(dirname "$PY_REPO_DIR")/python-pipeline}"
PIPELINE_DIR="$(cd "$PIPELINE_DIR" && pwd)"

for f in meta-gbp build docker-run tools; do
    if [[ ! -e "$PIPELINE_DIR/$f" ]]; then
        echo "missing $PIPELINE_DIR/$f" >&2
        exit 1
    fi
done

git -C "$PY_REPO_DIR" submodule update --init cpython
git -C "$PY_REPO_DIR/cpython" fetch --tags origin

if [[ -x "$PIPELINE_DIR/scripts/fix-changelog-headings.sh" ]]; then
    bash "$PIPELINE_DIR/scripts/fix-changelog-headings.sh" "$PY_REPO_DIR"
fi

export PY_REPO_DIR
export PIPELINE_DIR
export DOCKERSHELF_ARCH="${DOCKERSHELF_ARCH:-amd64}"
export DOCKERSHELF_BUILDER_IMAGE="${DOCKERSHELF_BUILDER_IMAGE:-ghcr.io/dockershelf/dockershelf-python-builder}"
export DOCKERSHELF_TOOLS_IMAGE="${DOCKERSHELF_TOOLS_IMAGE:-ghcr.io/dockershelf/dockershelf-python-builder/tools}"

if [[ -n "${GITHUB_ENV:-}" ]]; then
    {
        echo "PY_REPO_DIR=$PY_REPO_DIR"
        echo "PIPELINE_DIR=$PIPELINE_DIR"
        echo "DOCKERSHELF_ARCH=$DOCKERSHELF_ARCH"
        echo "DOCKERSHELF_BUILDER_IMAGE=$DOCKERSHELF_BUILDER_IMAGE"
        echo "DOCKERSHELF_TOOLS_IMAGE=$DOCKERSHELF_TOOLS_IMAGE"
    } >>"$GITHUB_ENV"
fi

echo "PY_REPO_DIR=$PY_REPO_DIR"
echo "PIPELINE_DIR=$PIPELINE_DIR"
echo "DOCKERSHELF_ARCH=$DOCKERSHELF_ARCH"
echo "DOCKERSHELF_BUILDER_IMAGE=$DOCKERSHELF_BUILDER_IMAGE"
echo "DOCKERSHELF_TOOLS_IMAGE=$DOCKERSHELF_TOOLS_IMAGE"
