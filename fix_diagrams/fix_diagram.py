import sys
from typing import List, Tuple, Optional

def find_all_boxes(lines: List[str]) -> List[dict]:
    """Find all boxes with improved multi-box handling."""
    boxes = []

    for i, line in enumerate(lines):
        for j, char in enumerate(line):
            if char == '┌':
                box = find_complete_box(lines, i, j)
                if box:
                    # Check if this box overlaps with any existing box
                    if not boxes_overlap(box, boxes):
                        boxes.append(box)

    return boxes

def boxes_overlap(box1: dict, boxes: List[dict]) -> bool:
    """Check if a box overlaps with any existing boxes."""
    for box2 in boxes:
        if boxes_overlap_single(box1, box2):
            return True
    return False

def boxes_overlap_single(box1: dict, box2: dict) -> bool:
    """Check if two boxes overlap."""
    # Boxes overlap if they share any boundary points
    return (box1['top'] == box2['top'] and box1['bottom'] == box2['bottom'] and
            (abs(box1['left'] - box2['left']) < 5 or
             abs(box1['right_top'] - box2['right_top']) < 5))

def find_complete_box(lines: List[str], start_row: int, start_col: int) -> Optional[dict]:
    """Find complete box with improved boundary detection."""
    # Find top-right corner
    top_line = lines[start_row]
    top_right_col = top_line.find('┐', start_col)
    if top_right_col == -1:
        return None

    # Find bottom-left corner
    bottom_row = None
    bottom_left_col = None

    for row in range(start_row + 1, len(lines)):
        line = lines[row]
        if start_col < len(line) and line[start_col] == '└':
            bottom_row = row
            bottom_left_col = start_col
            break
        # Look nearby
        for col in range(max(0, start_col - 2), min(len(line), start_col + 3)):
            if line[col] == '└':
                bottom_row = row
                bottom_left_col = col
                break
        if bottom_row is not None:
            break

    if bottom_row is None:
        return None

    # Find bottom-right corner
    bottom_line = lines[bottom_row]
    bottom_right_col = bottom_line.find('┘', max(bottom_left_col, top_right_col))
    if bottom_right_col == -1:
        bottom_right_col = bottom_line.find('┘', bottom_left_col)
    if bottom_right_col == -1:
        return None

    return {
        'top': start_row,
        'bottom': bottom_row,
        'left': start_col,
        'right_top': top_right_col,
        'right_bottom': bottom_right_col
    }

def calculate_box_width_improved(box: dict, lines: List[str]) -> int:
    """Calculate width for a box based on its content."""
    max_content_width = 0

    # Check content lines
    for row in range(box['top'] + 1, box['bottom']):
        if row >= len(lines):
            continue

        line = lines[row]
        # Find content between pipes
        left_pipe = line.find('│', box['left'])
        right_pipe = line.rfind('│', box['left'])

        if left_pipe != -1 and right_pipe != -1 and right_pipe > left_pipe:
            content = line[left_pipe + 1:right_pipe]
            # Strip trailing spaces for width calculation
            content_stripped = content.rstrip()
            content_width = len(content_stripped)
            max_content_width = max(max_content_width, content_width)

    # Use top border width as baseline
    top_width = box['right_top'] - box['left'] - 1
    bottom_width = box['right_bottom'] - box['left'] - 1

    return max(max_content_width, top_width, bottom_width)

def fix_diagram_improved(text: str) -> str:
    """Fix all boxes in a diagram with improved multi-box handling."""
    lines = text.split('\\n')
    boxes = find_all_boxes(lines)

    if not boxes:
        return text

    # Calculate aligned widths
    for box in boxes:
        width = calculate_box_width_improved(box, lines)
        box['right_aligned'] = box['left'] + width + 1

    # Process each line
    fixed_lines = []
    for line_num, original_line in enumerate(lines):
        boxes_on_line = [box for box in boxes if box['top'] <= line_num <= box['bottom']]

        if not boxes_on_line:
            fixed_lines.append(original_line)
            continue

        # Sort boxes by left position
        boxes_on_line.sort(key=lambda b: b['left'])

        # Reconstruct the line with aligned boxes
        result_line = reconstruct_line(original_line, boxes_on_line, line_num, lines)
        fixed_lines.append(result_line)

    return '\\n'.join(fixed_lines)

def reconstruct_line(original_line: str, boxes_on_line: List[dict], line_num: int, all_lines: List[str]) -> str:
    """Reconstruct a line with properly aligned boxes."""
    result = ""
    last_pos = 0

    for box in boxes_on_line:
        # Add content before this box (preserve exactly)
        if last_pos < box['left']:
            before_content = original_line[last_pos:box['left']]
            result += before_content

        # Add the properly aligned box
        if line_num == box['top']:
            # Top border
            box_width = box['right_aligned'] - box['left'] + 1
            result += '┌' + '─' * (box_width - 2) + '┐'
        elif line_num == box['bottom']:
            # Bottom border
            box_width = box['right_aligned'] - box['left'] + 1
            result += '└' + '─' * (box_width - 2) + '┘'
        else:
            # Content line
            content = extract_content_improved(original_line, box)
            box_width = box['right_aligned'] - box['left'] + 1
            content_width = box_width - 2

            if len(content) < content_width:
                content += ' ' * (content_width - len(content))
            elif len(content) > content_width:
                content = content[:content_width]

            result += '│' + content + '│'

        # Update position to after this box
        last_pos = box['right_aligned'] + 1

    # Add any remaining content after last box
    if last_pos < len(original_line):
        remaining = original_line[last_pos:]
        # Preserve content if it looks meaningful
        if remaining.strip() and any(c not in '│─└┘┌┐' for c in remaining):
            result += remaining

    return result

def extract_content_improved(line: str, box: dict) -> str:
    """Extract content from a box line with improved detection."""
    left_col = box['left']

    # Find right border position
    right_col = -1
    pipe_positions = []
    for i, char in enumerate(line):
        if char == '│':
            pipe_positions.append(i)

    # Count pipes before left border
    pipes_before = sum(1 for pos in pipe_positions if pos <= left_col)

    # The right border should be the next pipe after left border
    if pipes_before < len(pipe_positions):
        right_col = pipe_positions[pipes_before]

    if right_col <= left_col:
        # Fallback: use expected position
        right_col = max(box['right_top'], box['right_bottom'])

    # Extract content
    if right_col > left_col + 1:
        content = line[left_col + 1:right_col]
    else:
        content = ""

    return content.rstrip('│─└┘┌┐')

def main():
    if len(sys.argv) != 2:
        print("Usage: python fix_diagram.py <filename>")
        sys.exit(1)

    filename = sys.argv[1]

    try:
        with open(filename, 'r', encoding='utf-8') as f:
            content = f.read()

        fixed_content = fix_diagram_improved(content)

        with open(filename, 'w', encoding='utf-8') as f:
            f.write(fixed_content)

        print(f"Successfully fixed diagrams in {filename}")

    except FileNotFoundError:
        print(f"Error: File '{filename}' not found")
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()