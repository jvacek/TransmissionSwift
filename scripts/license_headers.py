#!/usr/bin/env python3

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

"""Check (or with --fix, add) the MPL-2.0 per-file license notice.

MPL-2.0 is copyleft per file, so each source file carries its own notice
(Exhibit A). The notice sits below a shebang or a swift-tools-version line,
which must stay first.

Usage:
    scripts/license_headers.py [--fix] [file ...]
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

NOTICE = (
    "This Source Code Form is subject to the terms of the Mozilla Public",
    "License, v. 2.0. If a copy of the MPL was not distributed with this",
    "file, You can obtain one at https://mozilla.org/MPL/2.0/.",
)
MARKER = NOTICE[0]
PREFIX = {".swift": "// ", ".sh": "# ", ".py": "# "}
GLOBS = ("*.swift", "*.sh", "*.py")
MUST_STAY_FIRST = ("#!", "// swift-tools-version:")


def notice_block(suffix: str) -> str:
    prefix = PREFIX[suffix]
    return "".join(f"{prefix}{line}\n" for line in NOTICE)


def head_length(text: str) -> int:
    """Length of the line that must stay first, plus its newline, or 0."""
    if text.startswith(MUST_STAY_FIRST):
        return text.index("\n") + 1
    return 0


def has_notice(text: str) -> bool:
    return any(MARKER in line for line in text.splitlines()[:5])


def with_notice(text: str, suffix: str) -> str:
    head = head_length(text)
    return (
        text[:head]
        + ("\n" if head else "")
        + notice_block(suffix)
        + "\n"
        + text[head:].lstrip("\n")
    )


def default_files() -> list[Path]:
    out = subprocess.run(
        ["git", "ls-files", "-z", "--", *GLOBS],
        check=True,
        capture_output=True,
    ).stdout
    return [Path(p) for p in out.decode().split("\0") if p]


def main(argv: list[str]) -> int:
    fix = "--fix" in argv
    paths = [Path(a) for a in argv if a != "--fix"] or default_files()
    missing = []
    for path in paths:
        if path.suffix not in PREFIX:
            continue
        text = path.read_text()
        if has_notice(text):
            continue
        missing.append(path)
        if fix:
            path.write_text(with_notice(text, path.suffix))
    if not missing:
        return 0
    if fix:
        print(f"Added the MPL notice to {len(missing)} file(s).", file=sys.stderr)
        return 0
    print("Missing the MPL-2.0 notice:", file=sys.stderr)
    for path in missing:
        print(f"  {path}", file=sys.stderr)
    print("Run `python3 scripts/license_headers.py --fix` to add it.", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
