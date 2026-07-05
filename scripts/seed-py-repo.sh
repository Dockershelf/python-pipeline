#!/usr/bin/env bash
# Seed a local py3.XX packaging repository from an existing Dockershelf py line.
#
# Usage:
#   ./seed-py-repo.sh 3.15 /path/to/dockershelf-pipeline/py3.15
#   ./seed-py-repo.sh 3.15 /path/to/py3.15 --from 3.14
#
# The cpython submodule is not cloned here (large). Initialize later with:
#   git submodule update --init cpython

set -euo pipefail

PY_MINOR="${1:?usage: seed-py-repo.sh <minor e.g. 3.15> <target-dir> [--from <minor>]}"
TARGET="${2:?usage: seed-py-repo.sh <minor> <target-dir> [--from <minor>]}"
shift 2

FROM_MINOR=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --from)
            FROM_MINOR="${2:?--from requires a minor version e.g. 3.14}"
            shift 2
            ;;
        *)
            echo "unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

if [[ -z "$FROM_MINOR" ]]; then
    FROM_MAJOR="${PY_MINOR%%.*}"
    FROM_PATCH="${PY_MINOR##*.}"
    FROM_MINOR="${FROM_MAJOR}.$((FROM_PATCH - 1))"
fi

ORG="${DOCKERSHELF_GITHUB_ORG:-Dockershelf}"
SOURCE_REPO="py${FROM_MINOR}"
TARGET_REPO="py${PY_MINOR}"
SOURCE_URL="https://github.com/${ORG}/${SOURCE_REPO}.git"
BRANCH="${PY_MINOR}"

if [ -e "${TARGET}" ]; then
    echo "ERROR: ${TARGET} already exists"
    exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Cloning ${SOURCE_URL} ..."
git clone --depth 1 "$SOURCE_URL" "$TMP/src"

rm -rf "$TMP/src/.git"
cp -a "$TMP/src" "$TARGET"

replace_in_tree() {
    local from="$1"
    local to="$2"
    while IFS= read -r -d '' file; do
        if grep -q "${from}" "${file}" 2>/dev/null; then
            perl -pi -e "s/\Q${from}\E/${to}/g" "${file}"
        fi
    done < <(find "${TARGET}" -type f -print0)
}

replace_in_tree "libpython${FROM_MINOR}" "libpython${PY_MINOR}"
replace_in_tree "python${FROM_MINOR}" "python${PY_MINOR}"
replace_in_tree "${FROM_MINOR}" "${PY_MINOR}"
replace_in_tree "${SOURCE_REPO}" "${TARGET_REPO}"

cd "${TARGET}"
rm -rf cpython
mkdir -p cpython
cat > .gitmodules <<EOF
[submodule "cpython"]
	path = cpython
	url = https://github.com/python/cpython.git
	branch = ${BRANCH}
EOF
cat > cpython/.gitkeep <<'EOF'
# Populated by: git submodule update --init cpython
EOF

PIPELINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -x "${PIPELINE}/scripts/retarget-py3-control.sh" ]]; then
  (cd "$(dirname "$TARGET")" && bash "${PIPELINE}/scripts/retarget-py3-control.sh" 2>/dev/null) || true
fi

git init -b main
git add -A
git commit -m "Initial ${TARGET_REPO} Debian packaging repository"

echo "Seeded ${TARGET} from ${SOURCE_REPO}"
echo "Next: cd ${TARGET} && git submodule update --init cpython"
