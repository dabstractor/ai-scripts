# Test Data Directory

This directory contains comprehensive test data for the diagram alignment utility.

## Directory Structure

```
test_data/
├── basic/                  # Basic box alignment tests (1-3)
├── complex/                # Complex layout tests (4-6)
├── content/                # Content preservation tests (7-9)
├── arrows/                 # Arrow and connector tests (10-13)
├── edge_cases/             # Edge case scenarios (14-17)
├── whitespace/             # Whitespace and formatting tests (18-20)
├── performance/            # Performance and large file tests (21-22)
├── error_handling/         # Error handling scenarios (23-25)
├── regression/             # Regression tests (26-27)
├── mixed_styles/           # Mixed box style tests (28-29)
├── specialized/            # Specialized diagram types (30-32)
├── integration/            # Documentation integration tests (33-35)
├── real_world/             # Real-world content scenarios (36-38)
├── tool_integration/       # Tool integration scenarios (39-41)
├── advanced_layout/        # Advanced layout patterns (42-44)
├── collaborative/          # Collaborative workflow tests (45-46)
├── accessibility/          # Accessibility and standards tests (47-48)
├── performance_edge/       # Performance edge cases (49-50)
├── generate_test_files.py  # Test data generation script
└── README.md              # This file
```

## Test File Naming Convention

Each test follows the pattern:
- `{category}/test_{number}_{name}_input.md` - Test input file
- `{category}/test_{number}_{name}_expected.md` - Expected output file

## Generated Tests

The following tests have been generated with input and expected files:

### Basic Tests (High Priority)
1. **Single Box** - `basic/test_01_single_box_*`
2. **Multi-line Content** - `basic/test_02_multiline_content_*`
3. **Different Widths** - `basic/test_03_different_widths_*`

### Complex Layout Tests (High Priority)
4. **Horizontal Arrangement** - `complex/test_04_horizontal_arrangement_*`
5. **Vertical Arrangement** - `complex/test_05_vertical_arrangement_*`
6. **Grid Layout** - `complex/test_06_grid_layout_*`

### Content Preservation Tests (High Priority)
7. **Special Characters** - `content/test_07_special_chars_*`
8. **Empty Box** - `content/test_08_empty_box_*`
9. **Unicode Content** - `content/test_09_unicode_content_*`

### Arrow and Connector Tests (High Priority)
10. **Right Arrow** - `arrows/test_10_right_arrow_*`
11. **Left Arrow** - `arrows/test_11_left_arrow_*`
12. **Bidirectional Arrow** - `arrows/test_12_bidirectional_arrow_*`
13. **Vertical Arrow** - `arrows/test_13_vertical_arrow_*`

### Edge Cases (High Priority)
15. **Mixed Content Types** - `edge_cases/test_15_mixed_content_*`

### Whitespace Tests (Medium Priority)
19. **Indentation Preservation** - `whitespace/test_19_indentation_*`

### Performance Tests (Medium Priority)
21. **Large Diagram** - `performance/test_21_large_diagram_*`

### Regression Tests (Critical Priority)
26. **Manual Fix Comparison** - `regression/test_26_manual_fix_*`

### Mixed Styles Tests (Medium Priority)
28. **Different Box Characters** - `mixed_styles/test_28_different_box_characters_*`

### Real-World Content Tests (Medium Priority)
36. **URLs/Emails** - `real_world/test_36_urls_emails_*`
41. **Markdown Export** - `real_world/test_41_markdown_export_*`

### Integration Tests (Medium Priority)
35. **Code Comments** - `integration/test_35_code_comments_*`

## Running Tests

Use the main test runner:
```bash
python3 run_tests.py
```

## Adding New Tests

1. Create input and expected files following the naming convention
2. Update the test runner to include the new test
3. Add test description to `../test_cases_todo.md`
4. Update this README

## Test Data Generation

To regenerate all test files:
```bash
cd test_data
python3 generate_test_files.py
```

This will recreate all test cases from the templates in `generate_test_files.py`.