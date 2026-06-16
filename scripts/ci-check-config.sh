#!/usr/bin/env bash
# Print whether expected GitHub Actions secrets/variables appear configured.
# Does not reveal secret values.
#
# Usage:
#   ./scripts/ci-check-config.sh [org-or-owner]
#   ./scripts/ci-check-config.sh --strict [org-or-owner]

set -euo pipefail

STRICT=0
OWNER="Dockershelf"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --strict)
            STRICT=1
            shift
            ;;
        *)
            OWNER="$1"
            shift
            ;;
    esac
done

REPOS=(python-pipeline py3.10 py3.11 py3.12 py3.13 py3.14)
REQUIRED_SECRET=DEPLOY_SSH_KEY
REQUIRED_VARS=(DEPLOY_HOST DEPLOY_USER DEPLOY_DIR DEPLOY_INCOMING)

EXPECTED_VARS=(
    "DEPLOY_HOST=apt.luisalejandro.org"
    "DEPLOY_USER=deploy"
    "DEPLOY_DIR=/var/www/debian"
    "DEPLOY_INCOMING=/var/www/debian/incoming"
)

has_secret() {
    local repo="$1" name="$2"
    gh secret list --repo "$OWNER/$repo" 2>/dev/null | awk '{print $1}' | grep -qx "$name"
}

has_variable() {
    local repo="$1" name="$2"
    gh variable list --repo "$OWNER/$repo" 2>/dev/null | awk '{print $1}' | grep -qx "$name"
}

check_repo() {
    local repo="$1"
    local repo_fail=0
    echo "## $OWNER/$repo"
    echo "secrets:"
    if gh secret list --repo "$OWNER/$repo" 2>/dev/null | awk '{print "  - " $1}'; then
        :
    else
        echo "  (unable to list)"
        repo_fail=1
    fi
    echo "variables:"
    if gh variable list --repo "$OWNER/$repo" 2>/dev/null | awk '{print "  - " $1 " = " $2}'; then
        :
    else
        echo "  (unable to list)"
        repo_fail=1
    fi

    if [[ "$STRICT" -eq 1 && "$repo_fail" -eq 0 ]]; then
        if ! has_secret "$repo" "$REQUIRED_SECRET"; then
            echo "  MISSING secret: $REQUIRED_SECRET"
            repo_fail=1
        fi
        local var
        for var in "${REQUIRED_VARS[@]}"; do
            if ! has_variable "$repo" "$var"; then
                echo "  MISSING variable: $var"
                repo_fail=1
            fi
        done
    fi
    echo
    return "$repo_fail"
}

failures=0
for repo in "${REPOS[@]}"; do
    if ! check_repo "$repo"; then
        failures=$((failures + 1))
    fi
done

cat <<'EOF'
Required before publish:
  DEPLOY_SSH_KEY (secret)
  DEPLOY_HOST, DEPLOY_USER, DEPLOY_DIR, DEPLOY_INCOMING (variables)

Optional:
  PY_REPO_PUSH_TOKEN — only if GITHUB_TOKEN cannot push (forks / tight org policy)
  DEBFULLNAME, DEBEMAIL — override default maintainer identity

GHCR: link dockershelf-python-builder/* packages to py3.* repos or make public.
EOF

echo "Recommended variable values for this deployment:"
for line in "${EXPECTED_VARS[@]}"; do
    echo "  $line"
done
echo
echo "Deploy guide: docs/deploy-setup.md"

if [[ "$STRICT" -eq 1 && "$failures" -gt 0 ]]; then
    echo "$failures repo(s) missing required deploy configuration" >&2
    exit 1
fi
