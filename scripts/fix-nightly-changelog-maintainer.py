#!/usr/bin/env python3
"""Replace the first deadsnakes maintainer line in nightly changelogs."""
from __future__ import annotations

import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from email.utils import format_datetime
from pathlib import Path

DEADSNakes_LINE = re.compile(r'^ -- Anthony Sottile \(deadsnakes\).*')


def git_identity() -> tuple[str, str]:
    name = os.environ.get('DEBFULLNAME') or subprocess.check_output(
        ('git', 'config', 'user.name'), text=True,
    ).strip()
    email = os.environ.get('DEBEMAIL') or subprocess.check_output(
        ('git', 'config', 'user.email'), text=True,
    ).strip()
    return name, email


def fix_file(path: Path, name: str, email: str) -> None:
    lines = path.read_text().splitlines(keepends=True)
    date = format_datetime(datetime.now(timezone.utc))
    new_line = f' -- {name} <{email}>  {date}\n'
    for i, line in enumerate(lines):
        if DEADSNakes_LINE.match(line.rstrip('\n')):
            lines[i] = new_line
            path.write_text(''.join(lines))
            print(f'updated {path}')
            return
    raise SystemExit(f'no deadsnakes maintainer line in {path}')


def main() -> int:
    workspace = Path(sys.argv[1] if len(sys.argv) > 1 else '..').resolve()
    name, email = git_identity()
    for py_dir in sorted(workspace.glob('py3.*')):
        nightly = py_dir / 'changelogs' / 'nightly'
        if not nightly.is_dir():
            continue
        for path in sorted(nightly.iterdir()):
            if path.is_file():
                fix_file(path, name, email)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
