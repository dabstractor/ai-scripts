#!/usr/bin/env python3
"""Fix misaligned ASCII box diagrams in text files.

LLMs frequently emit box diagrams whose right edges and bottom borders
drift out of alignment.  This tool repairs them using a simple model of
how those errors happen:

  * The TOP border (``┌───┐``) and the LEFT corner column are written
    first and are almost always correct — they are authoritative.
  * Errors accumulate to the RIGHT (wrong padding before ``│``) and
    DOWNWARD (bottom borders with the wrong dash count, drifted corners,
    or missing entirely).
  * Content between boxes (arrows such as ``────▶``, plain spacing) is
    "elastic": dash runs stretch or shrink to keep the boxes aligned.

For every box the fixer computes a target geometry — left column from
the top-left corner, inner width from the top border (grown if any
content line is wider) — then rewrites each row of the box to match,
preserving the content verbatim.  A bottom border is synthesised when a
box is left open and a connector row (``│``/``▼``/``▲``) follows.

Anything the model cannot confidently identify as a box (junction
characters, double-line borders, malformed rows) is left untouched:
first, do no harm.
"""
import re
import sys
import unicodedata
from typing import Dict, List, Optional, Tuple

ANSI_RE = re.compile(r'\x1b\[[0-9;]*[A-Za-z]')
TOP_RE = re.compile(r'┌─*┐')
BOTTOM_RE = re.compile(r'└─*┘')

# How far (in columns) a box edge may drift from its expected position
# and still be recognised as belonging to that box.
DRIFT_TOLERANCE = 8
MAX_BOX_HEIGHT = 40
# A row consisting solely of these characters (plus whitespace) marks a
# vertical connector between stacked boxes.
CONNECTOR_CHARS = set('│▼▲')


def dwidth(s: str) -> int:
    """Display width of *s*: ANSI escapes are invisible, East-Asian wide
    characters occupy two cells, combining marks occupy none."""
    s = ANSI_RE.sub('', s)
    total = 0
    for ch in s:
        if unicodedata.combining(ch) or unicodedata.category(ch) == 'Cf':
            continue  # combining marks and format chars (ZWSP…) are 0-wide
        total += 2 if unicodedata.east_asian_width(ch) in ('W', 'F') else 1
    return total


class Box:
    def __init__(self, top_row: int, left: int, top_right: int):
        self.top_row = top_row
        self.left = left              # column of ┌ in the original text
        self.top_right = top_right    # column of ┐ in the original text
        # row -> (kind, left_token_col, right_token_col); kind is
        # 'content' or 'bottom'.  Token columns index the ORIGINAL line.
        self.rows: Dict[int, Tuple[str, int, int]] = {}
        self.bottom_row: Optional[int] = None
        self.insert_bottom_after: Optional[int] = None  # synthesise bottom
        self.width: int = 0           # final inner width
        self.final_left: int = 0      # final column of the left edge
        self.end_row: int = top_row   # cached last row (set when accepted)

    def last_row(self) -> int:
        return self.end_row


def _claimed(col: int, claims: List[Tuple[int, int, int]]) -> bool:
    return any(lo <= col <= hi for lo, hi, _ in claims)


def _anchored_center(c: int, claims: List[Tuple[int, int, int]]) -> int:
    """Expected column of this box's left edge on a row.  Errors
    accumulate left-to-right, so when a box to our left already claimed
    tokens on this row, anchor on where that box's tokens actually ended
    plus the original gap — the RELATIVE drift between neighbours stays
    small even when the absolute drift is large."""
    best = None
    for lo, hi, top_right in claims:
        if top_right < c and (best is None or top_right > best[1]):
            best = (hi, top_right)
    if best is None:
        return c
    return best[0] + (c - best[1])


def _find_token(line: str, chars: str, center: int,
                claims: List[Tuple[int, int, int]], min_pos: int = 0,
                first: bool = False) -> Optional[int]:
    """Unclaimed occurrence of any of *chars* within the drift-tolerance
    window around *center*.  By default the nearest match wins; with
    ``first=True`` the leftmost wins (a box's right edge is always the
    FIRST pipe after its content — a later pipe belongs to a neighbour)."""
    lo = max(min_pos, center - DRIFT_TOLERANCE)
    hi = min(center + DRIFT_TOLERANCE, len(line) - 1)
    best = None
    for i in range(lo, hi + 1):
        if line[i] in chars and not _claimed(i, claims):
            if first:
                return i
            if best is None or abs(i - center) < abs(best - center):
                best = i
    return best


def _trace_box(lines: List[str], r: int, c: int, c2: int,
               claims: Dict[int, List[Tuple[int, int, int]]]) -> Optional[Box]:
    """Follow a box downward from its top border, matching each row's
    left/right edge tokens.  Returns None if the structure is too
    ambiguous to fix safely."""
    if '\t' in lines[r]:
        return None  # tab width is undefined — alignment is meaningless
    box = Box(r, c, c2)
    nested = False  # box contains an inner box (its pipes are not edges)
    row = r + 1
    while row < len(lines) and row - r <= MAX_BOX_HEIGHT:
        line = lines[row]
        if '\t' in line:
            return None
        row_claims = claims.get(row, [])
        left = _find_token(line, '│└', _anchored_center(c, row_claims),
                           row_claims)
        if left is None:
            return _end_unterminated(box, lines, row)
        # A row made only of connector characters (vertical arrows between
        # stacked boxes) can only be a content row if its pipe sits exactly
        # on the box's left edge; a drifted pipe there is a connector.
        non_ws = set(line) - set(' \t')
        if line[left] == '│' and left != c and non_ws <= CONNECTOR_CHARS:
            return _end_unterminated(box, lines, row)
        if line[left] == '└':
            m = BOTTOM_RE.match(line, left)
            if not m:
                return None
            box.rows[row] = ('bottom', left, m.end() - 1)
            box.bottom_row = row
            return box
        # Content row: the right pipe sits roughly one box-width to the
        # right of wherever the left pipe actually is.  Normally the FIRST
        # pipe after the content is the right edge (a later one belongs to
        # a neighbour), but once we know the box holds a nested box, its
        # inner pipes come first — match by position instead.
        center = left + (c2 - c)
        right = _find_token(line, '│', center, row_claims, min_pos=left + 1,
                            first=not nested)
        if right is None:
            # The box may have grown: accept the first unclaimed pipe
            # beyond the window as long as nothing box-like intervenes.
            # Growth only ever happens because the content is WIDE, so a
            # blank span means these pipes are vertical connectors, not
            # box edges.
            right = _far_right_pipe(line, left, center, row_claims)
            if right is not None and line[left + 1:right].strip() == '':
                right = None
            if right is None:
                # No right edge: this "left pipe" is probably a vertical
                # connector, so the box ended on the previous row.
                return _end_unterminated(box, lines, row)
        box.rows[row] = ('content', left, right)
        if TOP_RE.search(line, left + 1, right):
            nested = True  # an inner box's top border starts here
        row += 1
    return None


def _far_right_pipe(line: str, left: int, center: int,
                    claims: List[Tuple[int, int, int]]) -> Optional[int]:
    for i in range(center + DRIFT_TOLERANCE + 1, len(line)):
        if _claimed(i, claims):
            continue
        ch = line[i]
        if ch == '│':
            return i
        if ch in '┌┐└┘':
            return None  # another box starts first — bail
    return None


def _end_unterminated(box: Box, lines: List[str], row: int) -> Optional[Box]:
    """A box ran out of matching rows without a bottom border.  If it has
    content and the terminating row is a pure connector row, synthesise
    the missing bottom; otherwise leave the text alone."""
    if not any(kind == 'content' for kind, _, _ in box.rows.values()):
        return None
    line = lines[row] if row < len(lines) else ''
    chars = set(line) - set(' \t')
    if chars and chars <= CONNECTOR_CHARS:
        box.insert_bottom_after = row - 1
        return box
    return None


def _find_boxes(lines: List[str]) -> List[Box]:
    boxes: List[Box] = []
    claims: Dict[int, List[Tuple[int, int, int]]] = {}
    spans: Dict[int, List[Tuple[int, int]]] = {}  # row -> accepted box interiors
    for r, line in enumerate(lines):
        for m in TOP_RE.finditer(line):
            c, c2 = m.start(), m.end() - 1
            if any(lo < c < hi for lo, hi in spans.get(r, ())):
                continue  # nested inside an accepted box — treat as content
            if _claimed(c, claims.get(r, [])):
                continue
            box = _trace_box(lines, r, c, c2, claims)
            if box is None:
                continue
            box.end_row = max([box.top_row] + list(box.rows))
            boxes.append(box)
            claims.setdefault(r, []).append((c, c2, c2))
            for row, (_, lo, hi) in box.rows.items():
                claims.setdefault(row, []).append((lo, hi, c2))
            for row in range(box.top_row, box.end_row + 1):
                spans.setdefault(row, []).append((box.left, box.top_right))
    return boxes


def _compute_layout(boxes: List[Box], lines: List[str]) -> None:
    for box in boxes:
        width = box.top_right - box.left - 1
        for row, (kind, lo, hi) in box.rows.items():
            if kind == 'content':
                width = max(width, dwidth(lines[row][lo + 1:hi].rstrip()))
        box.width = width
        # Target column in DISPLAY space: text left of the box may hold
        # zero-width (ANSI) or double-width (CJK) characters.
        box.final_left = dwidth(lines[box.top_row][:box.left])

    # If a box grew wider than its top border, shift row-sharing boxes to
    # its right so they don't collide, preserving the original gap.
    by_row: Dict[int, List[Box]] = {}
    for b in boxes:
        for row in range(b.top_row, b.end_row + 1):
            by_row.setdefault(row, []).append(b)
    ordered = sorted(boxes, key=lambda b: (b.left, b.top_row))
    for b2 in ordered:
        neighbours = set()
        for row in range(b2.top_row, b2.end_row + 1):
            neighbours.update(b for b in by_row[row] if b.left < b2.left)
        for b1 in neighbours:
            gap = b2.left - b1.top_right - 1
            if gap < 0:
                continue
            b1_right = b1.final_left + b1.width + 1
            b2.final_left = max(b2.final_left, b1_right + 1 + gap)


def _fit_gap(gap: str, target: int) -> str:
    """Re-render the text between two boxes at *target* display width.
    Dash runs (arrows/connectors) are elastic; pure whitespace is
    replaced; anything ambiguous (tabs) is preserved verbatim."""
    current = dwidth(gap)
    if target < 0 or current == target or '\t' in gap:
        return gap
    if gap.strip() == '':
        return ' ' * target
    delta = target - current
    dash_runs = list(re.finditer(r'─+', gap))
    if dash_runs:
        run = max(dash_runs, key=lambda m: len(m.group()))
        new_len = len(run.group()) + delta
        if new_len >= 1:
            return gap[:run.start()] + '─' * new_len + gap[run.end():]
    space_runs = list(re.finditer(r' +', gap))
    if space_runs:
        run = max(space_runs, key=lambda m: len(m.group()))
        new_len = len(run.group()) + delta
        if new_len >= 0:
            return gap[:run.start()] + ' ' * new_len + gap[run.end():]
    if delta > 0:
        return gap + ' ' * delta
    return gap


def _render(lines: List[str], boxes: List[Box]) -> List[str]:
    by_line: Dict[int, List[Tuple[Box, str, int, int]]] = {}
    inserts: Dict[int, List[Box]] = {}
    for box in boxes:
        by_line.setdefault(box.top_row, []).append(
            (box, 'top', box.left, box.top_right))
        for row, (kind, lo, hi) in box.rows.items():
            by_line.setdefault(row, []).append((box, kind, lo, hi))
        if box.insert_bottom_after is not None:
            inserts.setdefault(box.insert_bottom_after, []).append(box)

    out: List[str] = []
    for i, line in enumerate(lines):
        if i in by_line:
            entries = sorted(by_line[i], key=lambda e: e[2])
            rebuilt = ''
            cursor = 0
            for box, kind, lo, hi in entries:
                gap = line[cursor:lo]
                rebuilt += _fit_gap(gap, box.final_left - dwidth(rebuilt))
                if kind == 'top':
                    rebuilt += '┌' + '─' * box.width + '┐'
                elif kind == 'bottom':
                    rebuilt += '└' + '─' * box.width + '┘'
                else:
                    content = line[lo + 1:hi].rstrip()
                    pad = box.width - dwidth(content)
                    rebuilt += '│' + content + ' ' * pad + '│'
                cursor = hi + 1
            rebuilt += line[cursor:]
            out.append(rebuilt)
        else:
            out.append(line)
        if i in inserts:
            synth = ''
            for b in sorted(inserts[i], key=lambda x: x.final_left):
                synth += ' ' * (b.final_left - dwidth(synth))
                synth += '└' + '─' * b.width + '┘'
            out.append(synth)
    return out


def fix_text(text: str) -> str:
    """Fix all repairable box diagrams in *text*."""
    lines = text.split('\n')
    boxes = _find_boxes(lines)
    if not boxes:
        return text
    _compute_layout(boxes, lines)
    return '\n'.join(_render(lines, boxes))


# Backwards-compatible alias (older callers import this name).
fix_diagram_improved = fix_text


def main() -> None:
    if len(sys.argv) != 2:
        print("Usage: python fix_diagram.py <filename>")
        sys.exit(1)
    filename = sys.argv[1]
    try:
        with open(filename, 'r', encoding='utf-8') as f:
            content = f.read()
        fixed = fix_text(content)
        if fixed != content:
            with open(filename, 'w', encoding='utf-8') as f:
                f.write(fixed)
        print(f"Successfully fixed diagrams in {filename}")
    except FileNotFoundError:
        print(f"Error: File '{filename}' not found")
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
