#!/usr/bin/env bash
# Debian-only packaging cleanup for py3.* debiandirs (Tier C).
set -euo pipefail
exec python3 "$(cd "$(dirname "$0")" && pwd)/debianize-packaging.py" "$@"
