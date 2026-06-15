#!/usr/bin/env bash
# Install built .deb packages in a Debian suite container and run import smoke tests.
#
# Usage:
#   ./scripts/debian-smoke-test.sh --dist trixie --py 3.14 --dist-dir ../python-pipeline/dist

set -euo pipefail

DIST=""
PY=""
DIST_DIR=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dist)
            DIST="$2"
            shift 2
            ;;
        --py)
            PY="$2"
            shift 2
            ;;
        --dist-dir)
            DIST_DIR="$2"
            shift 2
            ;;
        *)
            echo "unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

if [[ -z "$DIST" || -z "$PY" || -z "$DIST_DIR" ]]; then
    echo "usage: $0 --dist trixie --py 3.14 --dist-dir path/to/debs" >&2
    exit 1
fi

DIST_DIR="$(cd "$DIST_DIR" && pwd)"
shopt -s nullglob
debs=("$DIST_DIR"/*.deb)
if [[ ${#debs[@]} -eq 0 ]]; then
    echo "no .deb files in $DIST_DIR" >&2
    exit 1
fi

IMAGE="debian:${DIST}-slim"
CONTAINER="dockershelf-smoke-$$"
trap 'docker rm -f "$CONTAINER" >/dev/null 2>&1 || true' EXIT

docker run -d --name "$CONTAINER" "$IMAGE" sleep 3600
docker exec "$CONTAINER" mkdir -p /debs
docker cp "$DIST_DIR/." "$CONTAINER:/debs/"

docker exec "$CONTAINER" bash -euxc "
    apt-get update -qq
    shopt -s nullglob
    pkgs=(/debs/*.deb)
    dpkg -i \"\${pkgs[@]}\" || true
    DEBIAN_FRONTEND=noninteractive apt-get -f install -y -qq
    python${PY} --version
    python${PY} -c 'import ssl, ctypes, sqlite3'
"

echo "smoke test passed for python${PY} on ${DIST}"
