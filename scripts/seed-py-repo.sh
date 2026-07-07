#!/usr/bin/env bash
# Seed a local py3.XX packaging repository from the python-pipeline template.
#
# Usage:
#   ./seed-py-repo.sh 3.15 /path/to/dockershelf-pipeline/py3.15
#
# The upstream `cpython/` submodule gitlink is registered pointing to the
# ${PY_MINOR} branch HEAD, but the working tree is not cloned here (too large
# for bootstrap). Initialize it later with ../init-cpython-submodules.sh or:
#   git submodule update --init cpython

set -euo pipefail

PY_MINOR="${1:?usage: seed-py-repo.sh <minor e.g. 3.15> <target-dir>}"
TARGET="${2:?usage: seed-py-repo.sh <minor> <target-dir>}"
PIPELINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="${PIPELINE}/templates/py-packaging"

if [ -e "${TARGET}" ]; then
    echo "ERROR: ${TARGET} already exists"
    exit 1
fi

# Compute the next minor (used for the unused NVER variable in debian/rules).
PY_MAJOR="${PY_MINOR%%.*}"
PY_PATCH="${PY_MINOR##*.}"
PY_MINOR_NEXT="${PY_MAJOR}.$((PY_PATCH + 1))"

cp -a "${TEMPLATE}" "${TARGET}"

while IFS= read -r -d '' file; do
    if grep -q '__PY_MINOR__\|__PY_MINOR_DIR__\|__PY_MINOR_NEXT__' "${file}" 2>/dev/null; then
        perl -pi -e "s/__PY_MINOR_DIR__/py${PY_MINOR}/g; s/__PY_MINOR_NEXT__/${PY_MINOR_NEXT}/g; s/__PY_MINOR__/${PY_MINOR}/g" "${file}"
    fi
done < <(find "${TARGET}" -type f -print0)

cd "${TARGET}"
git init -b main

# Register cpython/ as a proper 160000 gitlink pointing to the ${PY_MINOR}
# branch HEAD, matching the node-pipeline/go-pipeline submodule pattern.
# The working tree is populated later by init-cpython-submodules.sh or:
#   git submodule update --init cpython
CPYTHON_SHA="$(curl -fsSL "https://api.github.com/repos/python/cpython/branches/${PY_MINOR}" \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['commit']['sha'])")"
mkdir -p cpython
git update-index --add --cacheinfo 160000 "${CPYTHON_SHA}" cpython
git add .gitmodules
git commit -m "Initial py${PY_MINOR} Debian packaging repository"

echo "Seeded ${TARGET} (run init-cpython-submodules.sh to fetch upstream cpython)"
