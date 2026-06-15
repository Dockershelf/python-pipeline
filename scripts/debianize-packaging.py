#!/usr/bin/env python3
"""Debian-only packaging cleanup for py3.* debiandirs (Tier C)."""
from __future__ import annotations

import argparse
import re
import shutil
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
OPENSSL_CNF = SCRIPT_DIR / 'files' / 'openssl.cnf'

RULES_MARKERS = (
    'distribution := $(shell lsb_release -is)',
    'ifeq ($(distribution),Ubuntu)',
    'ifeq ($(derivative),Ubuntu)',
)

TEST_COMMON_NEW_HEADER = """\
export LOCPATH=$(pwd)/locales
sh $debian_dir/locale-gen

export LANG=C.UTF-8

export DEB_PYTHON_INSTALL_LAYOUT=deb_system

TESTOPTS="-j 1 -w -uall,-network,-urlfetch,-gui"

# test_dbm: Fails from time to time ...
#TESTEXCLUSIONS="$TESTEXCLUSIONS test_dbm"

# test_ensurepip: not yet installed, http://bugs.debian.org/732703
# ... and then test_venv fails too
TESTEXCLUSIONS="$TESTEXCLUSIONS test_ensurepip test_venv "

# test_lib2to3: see https://bugs.python.org/issue34286
TESTEXCLUSIONS="$TESTEXCLUSIONS test_lib2to3"

# test_tcl: see https://bugs.python.org/issue34178
TESTEXCLUSIONS="$TESTEXCLUSIONS test_tcl"

# FIXME: flaky/slow test?
TESTEXCLUSIONS="$TESTEXCLUSIONS test_asyncio"

# FIXME: testWithTimeoutTriggeredSend: timeout not raised by _sendfile_use_sendfile
TESTEXCLUSIONS="$TESTEXCLUSIONS test_socket"

# test_ssl assumes OpenSSL SECLEVEL=1
export OPENSSL_CONF=$debian_dir/openssl.cnf

# FIXME: test_ttk_guionly times out on many buildds
TESTEXCLUSIONS="$TESTEXCLUSIONS test_ttk_guionly"

# FIXME: test_ttk_textonly started failing in 3.9.1 rc1
TESTEXCLUSIONS="$TESTEXCLUSIONS test_ttk_textonly"

# FIXME: test_multiprocessing_fork times out sometimes. See #1000188
TESTEXCLUSIONS="$TESTEXCLUSIONS test_multiprocessing_fork"
"""


def debianize_rules(text: str) -> str:
    original = text

    if 'distribution := $(shell lsb_release -is)' in text:
        text = re.sub(
            r'^dh_compat2 := .*\n',
            '',
            text,
            count=1,
            flags=re.MULTILINE,
        )

        text = re.sub(
            r'^distribution := \$\(shell lsb_release -is\)\n'
            r'^distrelease  := \$\(shell lsb_release -cs\)\n'
            r'^derivative\s+:= \$\(shell \\\n'
            r'\tif dpkg-vendor --derives-from Ubuntu; then echo Ubuntu; \\\n'
            r'\telif dpkg-vendor --derives-from Debian; then echo Debian; \\\n'
            r'\telse echo Unknown; fi\)\n',
            '',
            text,
            count=1,
            flags=re.MULTILINE,
        )

        text = re.sub(
            r'^ifeq \(\$\(distribution\),Ubuntu\)\n'
            r'(?:.*\n)*?'
            r'^else\n'
            r'^[ \t]+PY_MINPRIO = \$\(PY_PRIO\)\n'
            r'^endif\n',
            'PY_MINPRIO = $(PY_PRIO)\n',
            text,
            count=1,
            flags=re.MULTILINE,
        )

        text = re.sub(
            r'^ifeq \(,\$\(filter \$\(distrelease\),lenny etch squeeze wheezy lucid maverick natty oneiric\)\)\n'
            r'^[ \t]+bd_qual = :any\n'
            r'^endif\n'
            r'^ifeq \(,\$\(filter \$\(distrelease\),lenny etch squeeze wheezy lucid maverick natty oneiric\)\)\n'
            r'^[ \t]+ma_filter = cat\n'
            r'^else\n'
            r'^[ \t]+ma_filter = grep -v \'\^Multi-Arch:\'\n'
            r'^endif\n'
            r'^ifeq \(,\$\(filter \$\(distrelease\),lenny etch squeeze wheezy lucid maverick natty oneiric precise quantal raring saucy trusty\)\)\n'
            r'^[ \t]+bd_dpkgdev = dpkg-dev \(>= 1\.17\.11\),\n'
            r'^endif\n',
            'bd_qual = :any\n'
            'ma_filter = cat\n'
            'bd_dpkgdev = dpkg-dev (>= 1.17.11),\n',
            text,
            count=1,
            flags=re.MULTILINE,
        )

        text = re.sub(
            r'^ifeq \(\$\(distribution\),Ubuntu\)\n'
            r'^\tifneq \(,\$\(findstring ubuntu, \$\(PKGVERSION\)\)\)\n'
            r'^\tm=\'Ubuntu Core Developers <ubuntu-devel-discuss@lists\.ubuntu\.com>\'; \\\n'
            r'^\tsed -i "/\^Maintainer:/s/\\(.*\\)/Maintainer: \$\$m\\nXSBC-Original-\\1/" \\\n'
            r'^\t  debian/control\.tmp\n'
            r'^\tendif\n'
            r'^endif\n',
            '',
            text,
            count=1,
            flags=re.MULTILINE,
        )

        while 'ifeq ($(distribution),Ubuntu)' in text:
            text2 = re.sub(
                r'^ifeq \(\$\(distribution\),Ubuntu\)\n'
                r'(?:.*\n)*?'
                r'^endif\n',
                '',
                text,
                count=1,
                flags=re.MULTILINE,
            )
            if text2 == text:
                break
            text = text2

    if 'bd_qual = :any' not in text and 'distribution :=' not in text:
        # Already stripped distro vars; ensure modern defaults exist.
        insert_after = 'PY_MINPRIO = $(PY_PRIO)\n'
        if insert_after in text and 'bd_qual = :any' not in text:
            text = text.replace(
                insert_after,
                insert_after
                + 'bd_qual = :any\n'
                + 'ma_filter = cat\n'
                + 'bd_dpkgdev = dpkg-dev (>= 1.17.11),\n',
                1,
            )

    if '$(distrelease)' in text:
        text = re.sub(
            r'^ifeq \(,\$\(filter \$\(distrelease\),lenny etch squeeze wheezy lucid maverick natty oneiric\)\)\n'
            r'^[ \t]+bd_qual = :any\n'
            r'^endif\n'
            r'^ifeq \(,\$\(filter \$\(distrelease\),lenny etch squeeze wheezy lucid maverick natty oneiric\)\)\n'
            r'^[ \t]+ma_filter = cat\n'
            r'^else\n'
            r'^[ \t]+ma_filter = grep -v \'\^Multi-Arch:\'\n'
            r'^endif\n'
            r'^ifeq \(,\$\(filter \$\(distrelease\),lenny etch squeeze wheezy lucid maverick natty oneiric precise quantal raring saucy trusty\)\)\n'
            r'^[ \t]+bd_dpkgdev = dpkg-dev \(>= 1\.17\.11\),\n'
            r'^endif\n',
            'bd_qual = :any\n'
            'ma_filter = cat\n'
            'bd_dpkgdev = dpkg-dev (>= 1.17.11),\n',
            text,
            count=1,
            flags=re.MULTILINE,
        )
        if '$(distrelease)' in text:
            raise ValueError('distrelease conditionals remain after debianize')

    text = re.sub(
        r'^ifeq \(\$\(derivative\),Ubuntu\)\n'
        r'^[ \t]+arch_substvars =\n'
        r'^else ifeq \(\$\(derivative\),Debian\)\n'
        r'^[ \t]+arch_substvars = # .*$\n'
        r'^endif\n',
        '',
        text,
        count=1,
        flags=re.MULTILINE,
    )

    while 'ifeq ($(derivative),Ubuntu)' in text:
        text2 = re.sub(
            r'^ifeq \(\$\(derivative\),Ubuntu\)\n'
            r'(?:.*\n)*?'
            r'^endif\n',
            '',
            text,
            count=1,
            flags=re.MULTILINE,
        )
        if text2 == text:
            break
        text = text2

    if 'ifeq ($(distribution),Ubuntu)' in text or 'ifeq ($(derivative),Ubuntu)' in text:
        raise ValueError('Ubuntu ifeq blocks remain after debianize')

    return text if text != original else original


def debianize_test_common(text: str) -> str:
    if 'dpkg-vendor --derives-from Ubuntu' not in text:
        return TEST_COMMON_NEW_HEADER + '\n'
    return TEST_COMMON_NEW_HEADER + '\n'


def install_openssl_cnf(dest: Path, dry_run: bool) -> None:
    if dry_run:
        print(f'would install {dest}')
        return
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(OPENSSL_CNF, dest)


def process_py_dir(py_dir: Path, *, dry_run: bool) -> list[str]:
    touched: list[str] = []
    debiandirs = py_dir / 'debiandirs'
    if not debiandirs.is_dir():
        return touched

    for suite_dir in sorted(debiandirs.iterdir()):
        if not suite_dir.is_dir():
            continue
        suite = suite_dir.name

        openssl_dest = suite_dir / 'openssl.cnf'
        install_openssl_cnf(openssl_dest, dry_run)
        touched.append(str(openssl_dest))

        rules = suite_dir / 'rules'
        if rules.is_file():
            new_rules = debianize_rules(rules.read_text())
            if new_rules != rules.read_text():
                if dry_run:
                    print(f'would debianize {rules}')
                else:
                    rules.write_text(new_rules)
                touched.append(str(rules))

        test_common = suite_dir / 'tests' / 'test-common.sh'
        if test_common.is_file():
            new_tc = debianize_test_common(test_common.read_text())
            if new_tc != test_common.read_text():
                if dry_run:
                    print(f'would debianize {test_common}')
                else:
                    test_common.write_text(new_tc)
                touched.append(str(test_common))

    return touched


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('workspace', type=Path, nargs='?', default=Path('..'))
    args = parser.parse_args()

    workspace = args.workspace.resolve()
    all_touched: list[str] = []

    for py_dir in sorted(workspace.glob('py3.*')):
        try:
            touched = process_py_dir(py_dir, dry_run=args.dry_run)
            all_touched.extend(touched)
        except ValueError as exc:
            print(f'ERROR {py_dir}: {exc}', file=sys.stderr)
            return 1

    print(f'{"would touch" if args.dry_run else "touched"} {len(all_touched)} paths')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
