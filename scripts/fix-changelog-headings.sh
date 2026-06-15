#!/usr/bin/env bash
# Remove stray space before ')' in Debian changelog heading lines.
# dch rejects headings like:  pkg (1.0-1+dist1 ) trixie;
# Correct form:              pkg (1.0-1+dist1) trixie;
#
# Usage: ./scripts/fix-changelog-headings.sh /path/to/py3.14

set -euo pipefail

PY_REPO_DIR="${1:-}"
if [[ -z "$PY_REPO_DIR" ]]; then
    echo "usage: $0 /path/to/py3.XX" >&2
    exit 1
fi

if [[ ! -d "$PY_REPO_DIR/changelogs" ]]; then
    echo "no changelogs/ in $PY_REPO_DIR" >&2
    exit 1
fi

find "$PY_REPO_DIR/changelogs" -type f ! -name '.*' -print0 |
    while IFS= read -r -d '' file; do
        perl -pi -e 's/ \) (trixie|unstable);/) $1;/g' "$file"
    done

echo "fixed changelog headings under $PY_REPO_DIR/changelogs"
