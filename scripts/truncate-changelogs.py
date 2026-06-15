#!/usr/bin/env python3
"""Truncate py3.* changelogs to suite-matching entries only (Tier D)."""
from __future__ import annotations

import argparse
import re
import sys
import tempfile
from pathlib import Path

HEADING_RE = re.compile(r'^(\S+)\s+\(([^)]+)\)\s+(\S+);\s*(.*)$')


def parse_entries(text: str) -> list[dict]:
    lines = text.splitlines(keepends=True)
    entries: list[dict] = []
    i = 0
    while i < len(lines):
        line = lines[i]
        match = HEADING_RE.match(line.rstrip('\n'))
        if not match:
            i += 1
            continue
        start = i
        i += 1
        while i < len(lines) and not HEADING_RE.match(lines[i].rstrip('\n')):
            i += 1
        block = ''.join(lines[start:i])
        entries.append({
            'source': match.group(1),
            'version': match.group(2),
            'dist': match.group(3),
            'rest': match.group(4),
            'text': block,
        })
    return entries


def rewrite_entry(entry: dict, *, source: str, suite: str) -> str:
    heading = f'{source} ({entry["version"]}) {suite}; {entry["rest"]}\n'
    body = entry['text'][entry['text'].index('\n') + 1:]
    return heading + body


def truncate_file(path: Path, *, source: str, suite: str, dry_run: bool) -> tuple[int, int]:
    original = path.read_text()
    entries = parse_entries(original)
    kept = [e for e in entries if e['dist'] == suite]
    if not kept:
        raise SystemExit(f'no {suite} entries in {path}')

    new_text = ''.join(
        rewrite_entry(e, source=source, suite=suite) for e in kept
    )
    if not new_text.endswith('\n'):
        new_text += '\n'

    if dry_run:
        print(f'{path}: {len(entries)} -> {len(kept)} entries')
        return len(entries), len(kept)

    with tempfile.NamedTemporaryFile('w', delete=False, dir=path.parent) as tmp:
        tmp.write(new_text)
        tmp_path = Path(tmp.name)
    tmp_path.replace(path)
    print(f'{path}: {len(entries)} -> {len(kept)} entries')
    return len(entries), len(kept)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('workspace', type=Path, nargs='?', default=Path('..'))
    args = parser.parse_args()

    workspace = args.workspace.resolve()
    total_before = 0
    total_after = 0

    for py_dir in sorted(workspace.glob('py3.*')):
        ver = py_dir.name.replace('py3.', '')
        source = f'python3.{ver}'
        for track in ('mainline', 'nightly'):
            track_dir = py_dir / 'changelogs' / track
            if not track_dir.is_dir():
                continue
            for path in sorted(track_dir.iterdir()):
                if not path.is_file():
                    continue
                suite = path.name
                before, after = truncate_file(
                    path,
                    source=source,
                    suite=suite,
                    dry_run=args.dry_run,
                )
                total_before += before
                total_after += after

    print(f'total entries: {total_before} -> {total_after}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
