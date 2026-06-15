#!/usr/bin/env bash
# Update Maintainer and Vcs-* in py3.* debiandirs control.in and control.
set -euo pipefail

PIPELINE="$(cd "$(dirname "$0")/.." && pwd)"
WORKSPACE="$(cd "$PIPELINE/.." && pwd)"
ORG="${DOCKERSHELF_GITHUB_ORG:-Dockershelf}"

NAME="${DEBFULLNAME:-$(git config user.name)}"
EMAIL="${DEBEMAIL:-$(git config user.email)}"
MAINTAINER="Maintainer: ${NAME} <${EMAIL}>"

update_file() {
  local file=$1 repo=$2
  local browser="Vcs-Browser: https://github.com/${ORG}/${repo}"
  local git_url="Vcs-Git: https://github.com/${ORG}/${repo}.git"

  sed -i '' \
    -e "s|^Maintainer:.*|${MAINTAINER}|" \
    -e "s|^Vcs-Browser:.*|${browser}|" \
    -e "s|^Vcs-Git:.*|${git_url}|" \
    "$file"
}

for dir in "$WORKSPACE"/py3.*; do
  [ -d "$dir/debiandirs" ] || continue
  repo="$(basename "$dir")"
  for suite in trixie unstable; do
    for base in control.in control; do
      file="$dir/debiandirs/$suite/$base"
      if [ -f "$file" ]; then
        update_file "$file" "$repo"
        echo "updated $file"
      fi
    done
  done
done

echo "Maintainer: ${MAINTAINER}"
