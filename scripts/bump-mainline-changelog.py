#!/usr/bin/env python3
"""Prepend a packaging-only mainline changelog entry (avoids dch on legacy format)."""
from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from email.utils import format_datetime
from pathlib import Path

VERSION_RE = re.compile(r'^(.*)-1\+([a-z]+)(\d+)$')
HEADING_RE = re.compile(r'^\S+\s+\(([^)]+)\)\s+(\S+);')


def git_identity() -> tuple[str, str]:
    name = os.environ.get('DEBFULLNAME') or subprocess.check_output(
        ('git', 'config', 'user.name'), text=True,
    ).strip()
    email = os.environ.get('DEBEMAIL') or subprocess.check_output(
        ('git', 'config', 'user.email'), text=True,
    ).strip()
    return name, email


def parse_head_version(path: Path) -> tuple[str, str, int]:
    first = path.read_text().splitlines()[0]
    match = HEADING_RE.match(first)
    if not match:
        raise SystemExit(f'bad heading in {path}: {first!r}')
    version = match.group(1).strip()
    dist = match.group(2)
    parsed = VERSION_RE.fullmatch(version)
    if not parsed:
        raise SystemExit(f'unexpected version in {path}: {version!r}')
    return parsed.group(1), parsed.group(2), int(parsed.group(3))


def bump(path: Path, dist: str, message: str, name: str, email: str) -> None:
    upstream, suite, counter = parse_head_version(path)
    if suite != dist:
        counter = 1
    else:
        counter += 1

    source = path.read_text().splitlines()[0].split()[0]
    new_version = f'{upstream}-1+{dist}{counter}'
    date = format_datetime(datetime.now(timezone.utc))
    entry = '\n'.join([
        f'{source} ({new_version}) {dist}; urgency=medium',
        '',
        f'  * {message}',
        '',
        f' -- {name} <{email}>  {date}',
        '',
    ])
    path.write_text(entry + path.read_text())
    print(f'{path}: {new_version}')


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('-m', '--message', required=True)
    parser.add_argument('--only', choices=('trixie', 'unstable'))
    parser.add_argument('workspace', type=Path, nargs='?', default=Path('..'))
    args = parser.parse_args()

    name, email = git_identity()
    workspace = args.workspace.resolve()
    dists = [args.only] if args.only else ('trixie', 'unstable')

    for py_dir in sorted(workspace.glob('py3.*')):
        if not (py_dir / 'changelogs' / 'mainline').is_dir():
            continue
        for dist in dists:
            path = py_dir / 'changelogs' / 'mainline' / dist
            if path.is_file():
                bump(path, dist, args.message, name, email)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
