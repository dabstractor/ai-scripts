import sys
from typing import List, Tuple

def find_boxes(lines: List[str]) -> List[dict]:
    """Find all boxes in the diagram by detecting corner characters."""
    boxes = []
    
    for i, line in enumerate(lines):
        # Find top-left corners (┌)
        for j, char in enumerate(line):
            if char == '┌':
                box = find_box_boundaries(lines, i, j)
                if box:
                    boxes.append(box)
    
    return boxes

def find_box_boundaries(lines: List[str], start_row: int, start_col: int) -> dict:
    """Given a top-left corner, find the complete box boundaries."""
    # Find top-right corner on the same line
    top_line = lines[start_row]
    top_right_col = top_line.find('┐', start_col)
    if top_right_col == -1:
        return None
    
    # Find bottom-left corner in the same column as top-left
    bottom_row = None
    for i in range(start_row + 1, len(lines)):
        if start_col < len(lines[i]) and lines[i][start_col] == '└':
            bottom_row = i
            break
    
    if bottom_row is None:
        return None
    
    # Find bottom-right corner on bottom line
    bottom_right_col = lines[bottom_row].find('┘', start_col)
    if bottom_right_col == -1:
        return None
    
    return {
        'top': start_row,
        'bottom': bottom_row,
        'left': start_col,
        'right_top': top_right_col,
        'right_bottom': bottom_right_col
    }

def get_boxes_on_line(boxes: List[dict], line_num: int) -> List[dict]:
    """Get all boxes that include this line number."""
    boxes_on_line = []
    for box in boxes:
        if box['top'] <= line_num <= box['bottom']:
            boxes_on_line.append(box)
    return sorted(boxes_on_line, key=lambda b: b['left'])

def fix_diagram(text: str) -> str:
    """Fix all boxes in a diagram."""
    lines = text.split('\n')
    boxes = find_boxes(lines)
    
    # Calculate alignment for each box (right column should be the max of top and bottom)
    for box in boxes:
        box['right_aligned'] = max(box['right_top'], box['right_bottom'])
        box['shift'] = box['right_aligned'] - box['right_top']
    
    # Process each line
    fixed_lines = []
    for line_num, line in enumerate(lines):
        boxes_on_line = get_boxes_on_line(boxes, line_num)
        
        if not boxes_on_line:
            # No boxes on this line, keep it as is
            fixed_lines.append(line)
            continue
        
        # Build the line segment by segment
        new_line = ""
        pos = 0
        
        for box in boxes_on_line:
            left_col = box['left']
            right_col = box['right_aligned']
            box_width = right_col - left_col + 1
            
            # Add content before the box
            if pos < left_col:
                new_line += line[pos:left_col]
            
            # Determine what part of the box this line represents
            if line_num == box['top']:
                # Top border
                new_line += '┌' + '─' * (box_width - 2) + '┐'
            elif line_num == box['bottom']:
                # Bottom border
                new_line += '└' + '─' * (box_width - 2) + '┘'
            else:
                # Content line
                content_start = left_col + 1
                original_right = box['right_top'] if line_num == box['top'] else max(box['right_top'], box['right_bottom'])
                
                # Find the original right wall position for this line
                original_right_pos = box['right_top']
                for i in range(left_col, min(len(line), left_col + box_width)):
                    if line[i] == '│' and i > left_col:
                        original_right_pos = i
                        break
                
                content_end = original_right_pos
                content = line[content_start:content_end] if content_start < len(line) else ''
                content = content.ljust(box_width - 2)
                new_line += '│' + content + '│'
            
            # Update position to after the aligned right wall
            pos = max(pos, box['right_top'] + 1 + box['shift'])
        
        # Add any remaining content after the last box
        if pos < len(line):
            new_line += line[pos:]
        
        fixed_lines.append(new_line)
    
    return '\n'.join(fixed_lines)

def main():
    if len(sys.argv) != 2:
        print("Usage: python fix_diagram.py <filename>")
        sys.exit(1)
    
    filename = sys.argv[1]
    
    try:
        with open(filename, 'r', encoding='utf-8') as f:
            content = f.read()
        
        fixed_content = fix_diagram(content)
        
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
