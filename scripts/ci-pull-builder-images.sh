#!/usr/bin/env bash
# Pull GHCR builder images (pull-only; no local build fallback).
#
# Usage (from python-pipeline/ with py repos in parent workspace):
#   PIPELINE_DIR=$PWD WORKSPACE=$PWD/.. ./scripts/ci-pull-builder-images.sh

set -euo pipefail

PIPELINE_DIR="${PIPELINE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

export DOCKERSHELF_BUILDER_IMAGE="${DOCKERSHELF_BUILDER_IMAGE:-ghcr.io/dockershelf/dockershelf-python-builder}"
export DOCKERSHELF_TOOLS_IMAGE="${DOCKERSHELF_TOOLS_IMAGE:-ghcr.io/dockershelf/dockershelf-python-builder/tools}"
SUITES="${DOCKERSHELF_SUITES:-trixie unstable}"

echo "Pulling $DOCKERSHELF_TOOLS_IMAGE"
docker pull "$DOCKERSHELF_TOOLS_IMAGE"

for suite in $SUITES; do
    echo "Pulling ${DOCKERSHELF_BUILDER_IMAGE}/${suite}"
    docker pull "${DOCKERSHELF_BUILDER_IMAGE}/${suite}"
done
