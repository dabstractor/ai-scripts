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
    # Boxes overlap if they share the same corners (exact duplicate)
    # OR if they have significantly overlapping areas
    return (box1['top'] == box2['top'] and
            box1['bottom'] == box2['bottom'] and
            box1['left'] == box2['left'] and
            box1['right_top'] == box2['right_top'])

def find_complete_box(lines: List[str], start_row: int, start_col: int) -> Optional[dict]:
    """Find complete box with improved boundary detection."""
    # Find top-right corner
    top_line = lines[start_row]
    top_right_col = top_line.find('┐', start_col)
    if top_right_col == -1:
        return None

    # Find bottom-left corner - look in a wider range and be more flexible
    bottom_row = None
    bottom_left_col = None

    for row in range(start_row + 1, len(lines)):
        line = lines[row]
        # First check the exact same column
        if start_col < len(line) and line[start_col] == '└':
            bottom_row = row
            bottom_left_col = start_col
            break
        # Then look in a wider range for the bottom-left corner
        for col in range(max(0, start_col), min(len(line), start_col + 15)):  # Search forward more
            if line[col] == '└':
                # Check if this could be a valid bottom-left for this box
                # by looking for a corresponding bottom-right corner
                potential_bottom_right = line.find('┘', col)
                if potential_bottom_right != -1:
                    # Calculate expected width based on top border
                    expected_width = top_right_col - start_col + 1
                    actual_width = potential_bottom_right - col + 1

                    # If widths are similar (within tolerance), accept this as the box
                    if abs(expected_width - actual_width) <= 10:  # Increased tolerance
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
            content_stripped = content.rstrip(' \t')
            content_width = len(content_stripped)
            max_content_width = max(max_content_width, content_width)

    # Use top border width as baseline
    top_width = box['right_top'] - box['left'] - 1
    bottom_width = box['right_bottom'] - box['left'] - 1

    return max(max_content_width, top_width, bottom_width)

def fix_diagram_improved(text: str) -> str:
    """Fix all boxes in a diagram with improved multi-box handling."""
    lines = text.split('\n')
    boxes = find_all_boxes(lines)

    if not boxes:
        return text

    # CORE FUNCTIONALITY: Simple single box fix
    if len(boxes) == 1:
        box = boxes[0]
        # Calculate correct width from top border (this is the authoritative source)
        top_width = box['right_top'] - box['left'] + 1

        # Process all lines of the single box to ensure consistency
        for line_num in range(box['top'], box['bottom'] + 1):
            if line_num >= len(lines):
                continue

            original_line = lines[line_num]

            if line_num == box['top']:
                # Top border - should already be correct, but validate
                expected_top = '┌' + '─' * (top_width - 2) + '┐'
                # Replace only the box portion, preserve everything else
                before = original_line[:box['left']]
                after = original_line[box['right_top'] + 1:]
                lines[line_num] = before + expected_top + after

            elif line_num == box['bottom']:
                # Bottom border - fix to match top width
                corrected_bottom = '└' + '─' * (top_width - 2) + '┘'
                # Find the original bottom border end position
                original_end = original_line.find('┘', box['left'])
                if original_end > box['left']:
                    # Replace the entire original bottom border
                    before = original_line[:box['left']]
                    after = original_line[original_end + 1:]
                    lines[line_num] = before + corrected_bottom + after
                else:
                    # Fallback: replace at expected position
                    before = original_line[:box['left']]
                    after = original_line[box['left'] + top_width:]
                    lines[line_num] = before + corrected_bottom + after

            else:
                # Content lines - ensure proper width
                # Extract original content between pipes
                left_pipe = original_line.find('│', box['left'])
                right_pipe = original_line.rfind('│', box['left'])

                if left_pipe != -1 and right_pipe != -1 and right_pipe > left_pipe:
                    content = original_line[left_pipe + 1:right_pipe]
                    # Pad or truncate content to fit the box width
                    content_width = top_width - 2
                    if len(content) < content_width:
                        content = content + ' ' * (content_width - len(content))
                    elif len(content) > content_width:
                        content = content[:content_width]

                    # Reconstruct the line with properly sized content
                    before = original_line[:box['left']]
                    after = original_line[right_pipe + 1:]
                    lines[line_num] = before + '│' + content + '│' + after

        # Return immediately for single boxes - skip complex multi-box logic
        return '\n'.join(lines)

    # Calculate individual box widths based on top borders (authoritative source)
    for box in boxes:
        # Use the top border width as the correct width for this box
        top_width = box['right_top'] - box['left'] + 1
        box['correct_width'] = top_width
        # Store the correct right position based on top border
        box['right_correct'] = box['right_top']

        # Validate and fix bottom border alignment issues
        if box['right_bottom'] - box['left'] + 1 != top_width:
            # Bottom border doesn't match top border width - need to fix during reconstruction
            box['bottom_needs_fix'] = True
        else:
            box['bottom_needs_fix'] = False

    # Process each line
    fixed_lines = []
    for line_num, original_line in enumerate(lines):
        boxes_on_line = [box for box in boxes if box['top'] <= line_num <= box['bottom']]

        if not boxes_on_line:
            fixed_lines.append(original_line)
            continue

        # Sort boxes by left position
        boxes_on_line.sort(key=lambda b: b['left'])

        # Reconstruct the line with individually corrected boxes
        result_line = reconstruct_line_corrected(original_line, boxes_on_line, line_num, lines)
        fixed_lines.append(result_line)

    return '\n'.join(fixed_lines)

def reconstruct_line_corrected(original_line: str, boxes_on_line: List[dict], line_num: int, all_lines: List[str]) -> str:
    """Reconstruct a line with individually corrected boxes, preserving content between them."""
    result = ""
    last_pos = 0

    for box in boxes_on_line:
        # Add content before this box (preserve exactly - includes spaces, arrows, etc.)
        if last_pos < box['left']:
            before_content = original_line[last_pos:box['left']]
            result += before_content

        # Add the corrected box based on its top border width
        if line_num == box['top']:
            # Top border - use the existing top border (it's authoritative)
            result += original_line[box['left']:box['right_top'] + 1]
        elif line_num == box['bottom']:
            # Bottom border - always fix to match top width for consistency
            top_width = box['correct_width']
            corrected_bottom = '└' + '─' * (top_width - 2) + '┘'
            result += corrected_bottom
        else:
            # Content line - extract and preserve content exactly as it appears
            content = extract_content_preserved(original_line, box, all_lines, line_num)
            top_width = box['correct_width']
            content_width = top_width - 2

            # For single boxes, preserve original content exactly
            # Don't add extra padding - just use the extracted content as-is
            if len(content) > content_width:
                content = content[:content_width]  # Only truncate if too long
            # Only truncate if content is significantly longer than the box can handle
            if len(content) > content_width + 5:  # Allow some flexibility
                content = content[:content_width]

            result += '│' + content + '│'

        # Update position to after this box's correct right position
        last_pos = box['right_correct'] + 1

    # Add any remaining content after last box (this preserves arrows, spaces, etc.)
    if last_pos < len(original_line):
        remaining = original_line[last_pos:]

        # Check if this is a bottom border line - if so, filter out border characters
        is_bottom_border_line = any(line_num == box['bottom'] for box in boxes_on_line)
        if is_bottom_border_line:
            # Only preserve spaces and connectors, not malformed border characters
            remaining = ''.join(c for c in remaining if c not in '└─┘')

        result += remaining

    return result

def reconstruct_line(original_line: str, boxes_on_line: List[dict], line_num: int, all_lines: List[str]) -> str:
    """Legacy function - kept for compatibility."""
    return reconstruct_line_corrected(original_line, boxes_on_line, line_num, all_lines)

def extract_content_preserved(line: str, box: dict, all_lines: List[str], line_num: int) -> str:
    """Extract content from a box line while preserving original content exactly."""
    left_col = box['left']

    # Find all pipe positions in the line
    pipe_positions = []
    for i, char in enumerate(line):
        if char == '│':
            pipe_positions.append(i)

    # Find the pipes that bound this specific box
    left_pipe = -1
    right_pipe = -1

    for i, pipe_pos in enumerate(pipe_positions):
        if pipe_pos >= left_col:
            # Find the first pipe at or after left_col, and the next pipe after that
            if i == len(pipe_positions) - 1:
                # Last pipe in the line
                left_pipe = pipe_pos
                break
            elif i < len(pipe_positions) - 1:
                next_pipe_pos = pipe_positions[i + 1]
                if next_pipe_pos > pipe_pos:
                    left_pipe = pipe_pos
                    right_pipe = next_pipe_pos
                    break

    # Extract content between the found pipes
    if left_pipe != -1 and right_pipe != -1 and right_pipe > left_pipe:
        content = line[left_pipe + 1:right_pipe]
    else:
        content = ""

    # Return content exactly as found between the pipes
    return content

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