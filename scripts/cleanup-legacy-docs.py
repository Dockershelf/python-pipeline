#!/usr/bin/env python3
"""Remove remaining legacy deadsnakes/Ubuntu doc artifacts in py3.* repos."""
from __future__ import annotations

import argparse
import re
from pathlib import Path

DBG_UBUNTU_SECTION = re.compile(
    r'\nDebian and Ubuntu specific changes to the debug interpreter\n'
    r'-{59}\n'
    r'The python2\.4 and python2\.5 packages in Ubuntu feisty are modified to\n'
    r'first look for extension modules under a different name\.\n\n'
    r'  normal build: foo\.so\n'
    r'  debug build:  foo_d\.so foo\.so\n\n'
    r'This naming schema allows installation of the extension modules into\n'
    r'the same path \(The naming is directly taken from the Windows builds\n'
    r'which already uses this naming scheme\)\.\n\n'
    r'See https://wiki\.ubuntu\.com/PyDbgBuilds for more information\.\n',
    re.MULTILINE,
)

PYMINDEPS_COMMENT = (
    '    # XXX: pathlib actually depends on ntpath: deadsnakes/issues#176\n'
)
PYMINDEPS_REPLACEMENT = (
    '    # XXX: pathlib actually depends on ntpath (packaging depgraph workaround)\n'
)


def cleanup_dbg_readme(path: Path, dry_run: bool) -> bool:
    text = path.read_text()
    new_text, count = DBG_UBUNTU_SECTION.subn('\n', text)
    if count == 0:
        return False
    if not dry_run:
        path.write_text(new_text)
    print(f'{"would update" if dry_run else "updated"} {path}')
    return True


def cleanup_pymindeps(path: Path, dry_run: bool) -> bool:
    text = path.read_text()
    if PYMINDEPS_COMMENT not in text:
        return False
    if not dry_run:
        path.write_text(text.replace(PYMINDEPS_COMMENT, PYMINDEPS_REPLACEMENT))
    print(f'{"would update" if dry_run else "updated"} {path}')
    return True


def cleanup_readme_venv(path: Path, dry_run: bool) -> bool:
    text = path.read_text()
    old = 'Then rebuild and upload python3.4.'
    new = 'Then rebuild and publish packages.'
    if old not in text:
        return False
    if not dry_run:
        path.write_text(text.replace(old, new))
    print(f'{"would update" if dry_run else "updated"} {path}')
    return True


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('workspace', type=Path, nargs='?', default=Path('..'))
    args = parser.parse_args()

    workspace = args.workspace.resolve()
    touched = 0

    for py_dir in sorted(workspace.glob('py3.*')):
        debiandirs = py_dir / 'debiandirs'
        if not debiandirs.is_dir():
            continue
        for suite_dir in sorted(debiandirs.iterdir()):
            if not suite_dir.is_dir():
                continue
            faq = suite_dir / 'FAQ.html'
            if faq.is_file():
                if args.dry_run:
                    print(f'would delete {faq}')
                else:
                    faq.unlink()
                    print(f'deleted {faq}')
                touched += 1

            dbg_readme = suite_dir / 'PVER-dbg.README.Debian.in'
            if dbg_readme.is_file() and cleanup_dbg_readme(dbg_readme, args.dry_run):
                touched += 1

            readme_venv = suite_dir / 'README.venv'
            if readme_venv.is_file() and cleanup_readme_venv(readme_venv, args.dry_run):
                touched += 1

            for pymindeps in suite_dir.glob('pymindeps.py'):
                if cleanup_pymindeps(pymindeps, args.dry_run):
                    touched += 1

        github = py_dir / '.github'
        if github.is_dir() and not any(github.iterdir()):
            if args.dry_run:
                print(f'would rmdir {github}')
            else:
                github.rmdir()
                print(f'removed {github}')
            touched += 1

    print(f'{"would touch" if args.dry_run else "touched"} {touched} items')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
