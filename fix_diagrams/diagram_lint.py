#!/usr/bin/env python3
"""Lint box diagrams: verify every single-line-style box is well formed.

Used both as a test oracle (the fixer's output must lint clean) and as a
standalone auditing tool for golden files:

    python3 diagram_lint.py file.md [file2.md ...]

A clean box: ``┌`` and ``┐`` joined by ``─`` on the top row; every row
below has ``│`` at both edge columns (by display width) until a bottom
row with ``└``/``┘`` joined by ``─``.  Boxes using junction characters
(``┬┼├┤┴``), double-line or rounded styles are out of scope and are
skipped, as are lines containing tabs (alignment is undefined).
"""
import re
import sys
from typing import List, Tuple

from fix_diagram import ANSI_RE, dwidth

JUNCTIONS = set('┬┴├┤┼')


def lint_text(text: str) -> List[Tuple[int, int, str]]:
    """Return a list of (line_no, col, reason) violations, 1-based lines."""
    lines = text.split('\n')
    problems = []
    for r, line in enumerate(lines):
        c = -1
        while True:
            c = line.find('┌', c + 1)
            if c == -1:
                break
            reason = _check_box(lines, r, c)
            if reason:
                problems.append((r + 1, c, reason))
    return problems


def _col_at_width(line: str, width: int) -> str:
    """Character at display-width offset *width*, or '' if none/split."""
    line = ANSI_RE.sub('', line)
    w = 0
    for ch in line:
        if w == width:
            return ch
        w += dwidth(ch)
        if w > width:
            return ''  # falls inside a wide character
    return ''


def _check_box(lines: List[str], r: int, c: int):
    line = lines[r]
    if '\t' in line:
        return None  # tabs make column alignment undefined; skip
    c2 = line.find('┐', c)
    if c2 == -1:
        return 'no ┐ on top row'
    seg = line[c + 1:c2]
    if set(seg) & JUNCTIONS:
        return None  # split box — out of scope
    if seg and set(seg) != {'─'}:
        return f'top border not all ─: {seg!r}'
    left_w = dwidth(line[:c])
    right_w = dwidth(line[:c2])
    row = r + 1
    while row < len(lines):
        cur = lines[row]
        if '\t' in cur:
            return None
        lc = _col_at_width(cur, left_w)
        rc = _col_at_width(cur, right_w)
        if lc in JUNCTIONS or rc in JUNCTIONS:
            return None  # split box — out of scope
        if lc == '└':
            if rc != '┘':
                return (f'row {row + 1}: └ at width {left_w} but '
                        f'{rc!r} at width {right_w}')
            return None
        if lc != '│':
            return f'row {row + 1}: expected │ or └ at width {left_w}, found {lc!r}'
        if rc != '│':
            return f'row {row + 1}: expected │ at width {right_w}, found {rc!r}'
        row += 1
    return 'no bottom border before end of file'


def main() -> int:
    bad = 0
    for path in sys.argv[1:]:
        with open(path, encoding='utf-8') as f:
            problems = lint_text(f.read())
        for line_no, col, reason in problems:
            print(f'{path}:{line_no}:{col}: {reason}')
            bad += 1
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
