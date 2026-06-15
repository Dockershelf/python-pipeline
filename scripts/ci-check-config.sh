#!/usr/bin/env bash
# Print whether expected GitHub Actions secrets/variables appear configured.
# Does not reveal secret values.
#
# Usage: ./scripts/ci-check-config.sh [org-or-owner]

set -euo pipefail

OWNER="${1:-Dockershelf}"
REPOS=(python-pipeline py3.10 py3.11 py3.12 py3.13 py3.14)

check_repo() {
    local repo="$1"
    echo "## $OWNER/$repo"
    echo "secrets:"
    gh secret list --repo "$OWNER/$repo" 2>/dev/null | awk '{print "  - " $1}' || echo "  (unable to list)"
    echo "variables:"
    gh variable list --repo "$OWNER/$repo" 2>/dev/null | awk '{print "  - " $1 " = " $2}' || echo "  (unable to list)"
    echo
}

for repo in "${REPOS[@]}"; do
    check_repo "$repo"
done

cat <<'EOF'
Required before publish:
  DEPLOY_SSH_KEY (secret)
  DEPLOY_HOST, DEPLOY_USER, DEPLOY_DIR, DEPLOY_INCOMING (variables)

Optional:
  PY_REPO_PUSH_TOKEN — only if GITHUB_TOKEN cannot push (forks / tight org policy)
  DEBFULLNAME, DEBEMAIL — override default maintainer identity

GHCR: link dockershelf-builder/* packages to py3.* repos or make public.
EOF
