# fix_mermaid.py
# Claude hook: process mermaid charts in PRD to make them GitHub-compatible

import re
import sys
from pathlib import Path

MAX_LABEL_LENGTH = 50  # Max chars per node label to avoid parser issues

def escape_label(text):
    """Escape or replace characters that break GitHub Mermaid parser."""
    if not text:
        return ""
    text = text.replace("&", "and")
    text = text.replace("<", "(").replace(">", ")")
    text = text.replace('"', "'")
    text = text.replace("\n", " | ")
    return text

def split_long_label(label, max_length=MAX_LABEL_LENGTH):
    """Split very long labels into shorter segments with '|'-style separator."""
    if len(label) <= max_length:
        return label
    parts = []
    words = label.split()
    current = ""
    for word in words:
        if len(current) + len(word) + 1 <= max_length:
            current += (" " if current else "") + word
        else:
            parts.append(current)
            current = word
    if current:
        parts.append(current)
    return " | ".join(parts)

def fix_mermaid(content):
    """Take raw mermaid chart and return GitHub-compatible version."""
    node_pattern = re.compile(r'(\w+)\[(.*?)\]')
    def replace_node(match):
        node_id = match.group(1)
        label = match.group(2)
        label = escape_label(label)
        label = split_long_label(label)
        return f"{node_id}[{label}]"
    fixed_content = node_pattern.sub(replace_node, content)
    return fixed_content

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python fix_mermaid.py <input_file> [<output_file>]")
        sys.exit(1)

    input_file = Path(sys.argv[1])
    if not input_file.exists():
        print(f"Error: {input_file} does not exist.")
        sys.exit(1)

    output_file = Path(sys.argv[2]) if len(sys.argv) >= 3 else Path(input_file.stem + "_fixed.md")

    content = input_file.read_text()
    fixed = fix_mermaid(content)
    output_file.write_text(fixed)

    print(f"Fixed Mermaid charts written to {output_file}")

