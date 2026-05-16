#!/usr/bin/env python3
"""One-shot helper: strip the `const` modifier from constructor calls that now
reference runtime-mutable AppColors fields (bgBase, textPrimary, etc.).

Run from `flutter-app/`:

    python tools/strip_const_for_runtime_colors.py

It is idempotent — re-running on an already-fixed tree is a no-op.
"""

from __future__ import annotations

import re
from pathlib import Path

# AppColors fields that became `static Color` (mutable) — cannot be `const`.
RUNTIME_FIELDS = (
    "bgBase",
    "bgSurface",
    "bgRaised",
    "bgHover",
    "borderDim",
    "borderMed",
    "textPrimary",
    "textSecondary",
    "textTertiary",
)
PAT_RUNTIME = re.compile(
    r"\bAppColors\.(?:" + "|".join(RUNTIME_FIELDS) + r")\b"
)

# Match: `const` then whitespace then a Capitalised identifier (or _Capital) then `(`.
PAT_CONST_CALL = re.compile(r"\bconst\s+(?=[A-Z_][\w.]*\s*\()")


def find_matching_paren(src: str, open_idx: int) -> int:
    """Return index of the `)` that matches the `(` at open_idx, ignoring
    parens inside string literals and comments. Returns -1 if not found.
    """
    assert src[open_idx] == "("
    depth = 0
    i = open_idx
    n = len(src)
    while i < n:
        c = src[i]
        # Skip strings (single/double, with raw + triple variants handled naively).
        if c == "'" or c == '"':
            quote = c
            # Triple-quoted?
            if src.startswith(quote * 3, i):
                end = src.find(quote * 3, i + 3)
                i = (end + 3) if end != -1 else n
                continue
            # Single-line string with escape handling.
            i += 1
            while i < n and src[i] != quote:
                if src[i] == "\\" and i + 1 < n:
                    i += 2
                    continue
                if src[i] == "\n":
                    break
                i += 1
            i += 1
            continue
        # Skip line comments.
        if c == "/" and i + 1 < n and src[i + 1] == "/":
            nl = src.find("\n", i)
            i = nl if nl != -1 else n
            continue
        # Skip block comments.
        if c == "/" and i + 1 < n and src[i + 1] == "*":
            end = src.find("*/", i + 2)
            i = (end + 2) if end != -1 else n
            continue
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return -1


def strip_one_pass(src: str) -> tuple[str, int]:
    """Strip every `const Foo(...)` whose body references a runtime AppColors
    field. Returns (new_src, n_removed).
    """
    removed = 0
    out: list[str] = []
    i = 0
    n = len(src)
    while i < n:
        m = PAT_CONST_CALL.search(src, i)
        if not m:
            out.append(src[i:])
            break
        # Append up to the match.
        out.append(src[i : m.start()])
        # Find the `(` that follows the identifier.
        paren_idx = src.find("(", m.end())
        if paren_idx == -1:
            out.append(src[m.start():])
            break
        close_idx = find_matching_paren(src, paren_idx)
        if close_idx == -1:
            out.append(src[m.start():])
            break
        body = src[m.end() : close_idx + 1]
        if PAT_RUNTIME.search(body):
            # Drop the `const ` token (preserve the trailing whitespace
            # consumed by the regex — we already stripped it via m.end()).
            out.append(src[m.end() : close_idx + 1])
            removed += 1
        else:
            out.append(src[m.start() : close_idx + 1])
        i = close_idx + 1
    return "".join(out), removed


def fix_file(path: Path) -> int:
    src = path.read_text(encoding="utf-8")
    total = 0
    # Iterate until fixed point — nested const calls can require multiple
    # passes (outer `const` only becomes invalid after inner one is fixed).
    while True:
        src, n = strip_one_pass(src)
        if n == 0:
            break
        total += n
    if total > 0:
        path.write_text(src, encoding="utf-8")
    return total


def main() -> None:
    root = Path(__file__).resolve().parent.parent / "lib"
    total_files = 0
    total_removed = 0
    for path in sorted(root.rglob("*.dart")):
        n = fix_file(path)
        if n:
            total_files += 1
            total_removed += n
            print(f"  {path.relative_to(root.parent)}: -{n} const")
    print(f"done — stripped {total_removed} const in {total_files} files")


if __name__ == "__main__":
    main()
