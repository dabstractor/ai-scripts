#!/usr/bin/env python3
"""Test suite for the diagram fixer.

Four independent oracles, so no single source of truth can silently rot:

1. GOLDEN     fix(input) == expected, for every pair in test_data/.
2. PROPERTIES for every golden case:
                 - idempotence:   fix(fix(input)) == fix(input)
                 - fixed point:   fix(expected) == expected
                 - preservation:  no visible character (outside the
                   box-drawing set) is created or destroyed
                 - lint:          the output has no more box-geometry
                   violations than the input (never make things worse)
3. FUZZ       seeded generator builds random *clean* diagrams, applies
              LLM-style corruptions (bad bottom widths, right-edge
              padding drift, elastic-gap jitter, dropped bottoms), and
              requires the fixer to recover the clean text EXACTLY.
4. UNIT       targeted regressions for tricky behaviours.

Run:  python3 run_tests.py [--fuzz N] [--verbose]
"""
import argparse
import difflib
import random
import sys
from collections import Counter
from pathlib import Path

from fix_diagram import fix_text, dwidth
from diagram_lint import lint_text

BOX_CHARS = set('┌┐└┘─│')


# ---------------------------------------------------------------- helpers

def show_diff(expected: str, actual: str, limit: int = 24) -> str:
    diff = list(difflib.unified_diff(
        expected.split('\n'), actual.split('\n'),
        'expected', 'actual', lineterm=''))
    if len(diff) > limit:
        diff = diff[:limit] + [f'... ({len(diff) - limit} more diff lines)']
    return '\n'.join('      ' + d for d in diff)


def visible_chars(text: str) -> Counter:
    return Counter(c for c in text if not c.isspace() and c not in BOX_CHARS)


# ---------------------------------------------------------------- golden

def discover_golden(test_dir: Path):
    for inp in sorted(test_dir.rglob('*_input.md')):
        exp = Path(str(inp).replace('_input.md', '_expected.md'))
        if exp.exists():
            name = str(inp.relative_to(test_dir)).replace('_input.md', '')
            yield name, inp.read_text(), exp.read_text()


def run_golden(cases, verbose):
    failures = []
    for name, inp, expected in cases:
        actual = fix_text(inp)
        if actual == expected:
            if verbose:
                print(f'  ✅ {name}')
        else:
            failures.append(name)
            print(f'  ❌ {name}')
            print(show_diff(expected, actual))
    return failures


# ---------------------------------------------------------------- properties

def run_properties(cases, verbose):
    failures = []
    for name, inp, expected in cases:
        actual = fix_text(inp)
        problems = []
        if fix_text(actual) != actual:
            problems.append('not idempotent: fix(fix(x)) != fix(x)')
        if fix_text(expected) != expected:
            problems.append('expected file is not a fixed point of fix()')
        if visible_chars(actual) != visible_chars(inp):
            delta = visible_chars(actual) - visible_chars(inp)
            lost = visible_chars(inp) - visible_chars(actual)
            problems.append(f'content changed: gained {dict(delta)}, '
                            f'lost {dict(lost)}')
        if len(lint_text(actual)) > len(lint_text(inp)):
            problems.append('output has MORE lint violations than input')
        if problems:
            failures.append(name)
            print(f'  ❌ {name}')
            for p in problems:
                print(f'      {p}')
        elif verbose:
            print(f'  ✅ {name}')
    return failures


# ---------------------------------------------------------------- fuzzer

WORDS = ['Auth', 'Cache', 'Client', 'Server', 'Database', 'Queue', 'API',
         'Gateway', 'Worker', 'Storage', 'Layer', 'Service', 'Router',
         'Broker', 'Engine', 'Proxy', 'Handler', 'Module', 'Core', 'UI',
         '数据库', 'キャッシュ', '服务器层', 'ワーカー']  # wide chars


def _gen_group(rng):
    """One horizontal row of boxes: returns a structure dict."""
    n_boxes = rng.randint(1, 3)
    height = rng.randint(1, 3)
    boxes = []
    for _ in range(n_boxes):
        labels = [rng.choice(WORDS) for _ in range(height)]
        lpad = rng.randint(1, 3)
        inner = lpad + max(dwidth(l) for l in labels) + rng.randint(1, 4)
        boxes.append({'labels': labels, 'inner': inner, 'lpad': lpad})
    gaps = []
    for _ in range(n_boxes - 1):
        width = rng.randint(3, 8)
        arrow = rng.random() < 0.5 and width >= 4
        gaps.append({'width': width, 'arrow': arrow,
                     'arrow_row': rng.randrange(height)})
    return {'boxes': boxes, 'gaps': gaps, 'height': height,
            'indent': rng.choice([0, 0, 2, 4])}


def _render_group(group, jitter=None):
    """Render a group to lines.  With jitter (an rng), emit an
    LLM-corrupted version; otherwise emit the clean ground truth."""
    boxes, gaps, height = group['boxes'], group['gaps'], group['height']
    indent = ' ' * group['indent']
    j = jitter

    def gapw(i, row_kind):
        w = gaps[i]['width']
        if j and row_kind != 'top':
            w = max(1, w + j.randint(-2, 2))
        return w

    lines = []
    top = indent
    for i, b in enumerate(boxes):
        top += '┌' + '─' * b['inner'] + '┐'
        if i < len(gaps):
            top += ' ' * gaps[i]['width']
    lines.append(top)

    for row in range(height):
        line = indent
        for i, b in enumerate(boxes):
            text = ' ' * b['lpad'] + b['labels'][row]
            pad = b['inner'] - dwidth(text)
            if j:
                pad = max(0, pad + j.randint(-2, 3))
            line += '│' + text + ' ' * pad + '│'
            if i < len(gaps):
                g = gaps[i]
                w = gapw(i, 'content')
                if g['arrow'] and g['arrow_row'] == row:
                    line += '─' * (w - 1) + '▶'
                else:
                    line += ' ' * w
        lines.append(line)

    bottom = indent
    for i, b in enumerate(boxes):
        inner = b['inner']
        if j:
            inner = max(1, inner + j.randint(-3, 5))
        bottom += '└' + '─' * inner + '┘'
        if i < len(gaps):
            bottom += ' ' * gapw(i, 'bottom')
    lines.append(bottom)
    return lines


def _clean_bottom(group):
    indent = ' ' * group['indent']
    line = indent
    for i, b in enumerate(group['boxes']):
        line += '└' + '─' * b['inner'] + '┘'
        if i < len(group['gaps']):
            line += ' ' * group['gaps'][i]['width']
    return line


def gen_case(rng):
    """Return (clean_text, corrupt_text)."""
    n_groups = rng.randint(1, 3)
    clean, corrupt = [], []
    for gi in range(n_groups):
        group = _gen_group(rng)
        c_lines = _render_group(group)
        k_lines = _render_group(group, jitter=rng)
        # Ground truth never has trailing whitespace on box rows.
        c_lines = [l.rstrip() for l in c_lines]
        k_lines = [l.rstrip() for l in k_lines]
        has_connector = gi < n_groups - 1
        if has_connector and rng.random() < 0.3:
            # Drop the whole bottom border line; the fixer must
            # synthesise it (a connector row follows).
            k_lines = k_lines[:-1]
        clean.extend(c_lines)
        corrupt.extend(k_lines)
        if has_connector:
            first = group['boxes'][0]
            col = group['indent'] + 1 + min(first['inner'] - 1,
                                            max(1, first['inner'] // 2))
            connector = [' ' * col + '│', ' ' * col + '▼']
            clean.extend(connector)
            corrupt.extend(connector)
    header = ['# Generated diagram', '', '```']
    footer = ['```', '']
    return ('\n'.join(header + clean + footer),
            '\n'.join(header + corrupt + footer))


def run_fuzz(n_cases, verbose):
    failures = 0
    for seed in range(n_cases):
        rng = random.Random(seed)
        clean, corrupt = gen_case(rng)
        actual = fix_text(corrupt)
        if actual != clean:
            failures += 1
            if failures <= 5:
                print(f'  ❌ fuzz seed {seed}')
                print('      --- corrupt input ---')
                for l in corrupt.split('\n'):
                    print(f'      {l!r}')
                print(show_diff(clean, actual))
        elif verbose:
            print(f'  ✅ fuzz seed {seed}')
    return failures


# ---------------------------------------------------------------- units

UNIT_CASES = [
    ('leaves prose alone',
     'Just some text\nwith no diagrams │ maybe a stray pipe\n',
     'Just some text\nwith no diagrams │ maybe a stray pipe\n'),
    ('single box bottom too long',
     '┌─────┐\n│ Hi  │\n└────────┘\n',
     '┌─────┐\n│ Hi  │\n└─────┘\n'),
    ('single box bottom too short',
     '┌─────┐\n│ Hi  │\n└──┘\n',
     '┌─────┐\n│ Hi  │\n└─────┘\n'),
    ('content wider than top border grows the box',
     '┌────┐\n│ long content │\n└────┘\n',
     '┌─────────────┐\n│ long content│\n└─────────────┘\n'),
    ('right pipe drift is re-padded',
     '┌────────┐\n│ Hi    │\n└────────┘\n',
     '┌────────┐\n│ Hi     │\n└────────┘\n'),
    ('arrow gap stretches to keep boxes aligned',
     '┌───┐    ┌───┐\n│ A │──▶│ B │\n└───┘    └───┘\n',
     '┌───┐    ┌───┐\n│ A │───▶│ B │\n└───┘    └───┘\n'),
    ('unterminated box before prose is untouched',
     '┌─────┐\n│ Hi  │\n\nplain text\n',
     '┌─────┐\n│ Hi  │\n\nplain text\n'),
    ('missing bottom inserted before connector',
     '┌─────┐\n│ Hi  │\n   │\n   ▼\n┌─────┐\n│ Lo  │\n└─────┘\n',
     '┌─────┐\n│ Hi  │\n└─────┘\n   │\n   ▼\n┌─────┐\n│ Lo  │\n└─────┘\n'),
    ('wide (CJK) content pads by display width',
     '┌──────────┐\n│ 数据库    │\n└──────────┘\n',
     '┌──────────┐\n│ 数据库   │\n└──────────┘\n'),
    ('indented box keeps indentation',
     '    ┌─────┐\n    │ Hi  │\n    └───────┘\n',
     '    ┌─────┐\n    │ Hi  │\n    └─────┘\n'),
    ('clean nested boxes are a fixed point',
     '┌────────┐\n│ ┌────┐ │\n│ │ ab │ │\n│ └────┘ │\n└────────┘\n',
     '┌────────┐\n│ ┌────┐ │\n│ │ ab │ │\n│ └────┘ │\n└────────┘\n'),
    ('shared connector row closes both open boxes',
     '┌───┐  ┌───┐\n│ a │  │ b │\n  │      │\n  ▼      ▼\n',
     '┌───┐  ┌───┐\n│ a │  │ b │\n└───┘  └───┘\n  │      │\n  ▼      ▼\n'),
]


def run_units(verbose):
    failures = []
    for name, inp, expected in UNIT_CASES:
        actual = fix_text(inp)
        if actual == expected:
            if verbose:
                print(f'  ✅ {name}')
        else:
            failures.append(name)
            print(f'  ❌ {name}')
            print(show_diff(expected, actual))
    return failures


# ---------------------------------------------------------------- main

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--fuzz', type=int, default=300,
                    help='number of fuzz cases (default 300)')
    ap.add_argument('--verbose', action='store_true')
    args = ap.parse_args()

    test_dir = Path(__file__).parent / 'test_data'
    cases = list(discover_golden(test_dir))

    print(f'GOLDEN ({len(cases)} cases)')
    golden_fail = run_golden(cases, args.verbose)

    print(f'PROPERTIES ({len(cases)} cases)')
    prop_fail = run_properties(cases, args.verbose)

    print(f'UNIT ({len(UNIT_CASES)} cases)')
    unit_fail = run_units(args.verbose)

    print(f'FUZZ ({args.fuzz} cases)')
    fuzz_fail = run_fuzz(args.fuzz, args.verbose)

    print()
    print('=' * 60)
    ok = not (golden_fail or prop_fail or unit_fail or fuzz_fail)
    print(f'golden: {len(cases) - len(golden_fail)}/{len(cases)}   '
          f'properties: {len(cases) - len(prop_fail)}/{len(cases)}   '
          f'unit: {len(UNIT_CASES) - len(unit_fail)}/{len(UNIT_CASES)}   '
          f'fuzz: {args.fuzz - fuzz_fail}/{args.fuzz}')
    print('🎉 all tests passed' if ok else '❌ FAILURES')
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
