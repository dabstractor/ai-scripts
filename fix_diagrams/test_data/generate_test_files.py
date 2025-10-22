#!/usr/bin/env python3
"""
Generate all test input and expected output files for the 50 test cases.
This script creates comprehensive test data covering all scenarios.
"""

import os
from pathlib import Path

# Test data templates
TEST_TEMPLATES = {
    # Basic tests
    "basic/test_01_single_box": {
        "input": """# Single Box Test

```
┌─────────────┐
│   Content   │
└────────────────┘
```""",
        "expected": """# Single Box Test

```
┌─────────────┐
│   Content   │
└─────────────┘
```"""
    },

    "basic/test_02_multiline_content": {
        "input": """# Multi-line Content Box Test

```
┌──────────────────┐
│ First line      │
│ Second line     │
│ Third line      │
└────────────────────┘
```""",
        "expected": """# Multi-line Content Box Test

```
┌──────────────────┐
│ First line      │
│ Second line     │
│ Third line      │
└──────────────────┘
```"""
    },

    "basic/test_03_different_widths": {
        "input": """# Different Box Widths Test

```
┌─────────┐     ┌─────────────────────┐
│ Small   │     │   Much larger box   │
└──────────────┘     └────────────────────┘
```""",
        "expected": """# Different Box Widths Test

```
┌─────────┐     ┌─────────────────────┐
│ Small   │     │   Much larger box   │
└─────────┘     └─────────────────────┘
```"""
    },

    # Complex layout tests
    "complex/test_04_horizontal_arrangement": {
        "input": """# Horizontal Box Arrangement Test

```
┌─────────┐────▶┌─────────────┐────▶┌──────────────┐
│   App   │     │  Service   │     │  Database    │
│ Server  │     │  Layer     │     │   Server     │
└─────────────┘     └─────────────────┘     └───────────────┘
```""",
        "expected": """# Horizontal Box Arrangement Test

```
┌─────────┐────▶┌─────────────┐────▶┌──────────────┐
│   App   │     │  Service   │     │  Database    │
│ Server  │     │  Layer     │     │   Server     │
└─────────┘     └─────────────┘     └──────────────┘
```"""
    },

    "complex/test_05_vertical_arrangement": {
        "input": """# Vertical Box Arrangement Test

```
┌──────────────┐
│   Frontend   │
│   React App  │
       │
       ▼
┌─────────────────────┐
│    Backend         │
│   Node.js API      │
       │
       ▼
┌─────────────────┐
│   Database      │
│  PostgreSQL     │
└─────────────────┘
```""",
        "expected": """# Vertical Box Arrangement Test

```
┌──────────────┐
│   Frontend   │
│   React App  │
└──────────────┘
       │
       ▼
┌─────────────────┐
│    Backend      │
│  Node.js API    │
└─────────────────┘
       │
       ▼
┌─────────────────┐
│   Database      │
│  PostgreSQL     │
└─────────────────┘
```"""
    },

    "complex/test_06_grid_layout": {
        "input": """# Grid Layout Test

```
┌─────────┐     ┌─────────────┐
│ Box A   │────▶│   Box B    │
│ Top     │     │   Top      │
└─────────────┘     └─────────────────┘
         │                        │
         ▼                        ▼
┌─────────────────┐     ┌──────────────┐
│   Box C         │────▶│   Box D      │
│   Bottom        │     │   Bottom     │
└─────────────────────┘     └────────────────┘
```""",
        "expected": """# Grid Layout Test

```
┌─────────┐     ┌─────────────┐
│ Box A   │────▶│   Box B    │
│ Top     │     │   Top      │
└─────────┘     └─────────────┘
         │                        │
         ▼                        ▼
┌─────────────────┐     ┌──────────────┐
│   Box C         │────▶│   Box D      │
│   Bottom        │     │   Bottom     │
└─────────────────┘     └──────────────┘
```"""
    },

    # Content preservation tests
    "content/test_07_special_chars": {
        "input": """# Content with Special Characters Test

```
┌─────────────────────────────┐
│ This box contains: │─┌┐└┘ │
│ Special Unicode box chars   │
│ Like these: ┌─┐ └─┘        │
└────────────────────────┘
```""",
        "expected": """# Content with Special Characters Test

```
┌─────────────────────────────┐
│ This box contains: │─┌┐└┘ │
│ Special Unicode box chars   │
│ Like these: ┌─┐ └─┘        │
└─────────────────────────────┘
```"""
    },

    "content/test_08_empty_box": {
        "input": """# Empty Box Test

```
┌─────┐
│     │
└─────────┘
```""",
        "expected": """# Empty Box Test

```
┌─────┐
│     │
└─────┘
```"""
    },

    "content/test_09_unicode_content": {
        "input": """# Unicode Content Test

```
┌──────────────────────────┐
│   Hello World! 🌍        │
│   Café résumé naïve      │
│   中文测试               │
│   العربية               │
└─────────────────────────┘
```""",
        "expected": """# Unicode Content Test

```
┌──────────────────────────┐
│   Hello World! 🌍        │
│   Café résumé naïve      │
│   中文测试               │
│   العربية               │
└──────────────────────────┘
```"""
    },

    # Arrow and connector tests
    "arrows/test_10_right_arrow": {
        "input": """# Right Arrow Preservation Test

```
┌─────────┐────▶┌─────────────┐
│ Source  │     │  Target     │
│ System  │     │  System     │
└─────────────┘     └─────────────────┘
```""",
        "expected": """# Right Arrow Preservation Test

```
┌─────────┐────▶┌─────────────┐
│ Source  │     │  Target     │
│ System  │     │  System     │
└─────────┘     └─────────────┘
```"""
    },

    "arrows/test_11_left_arrow": {
        "input": """# Left Arrow Preservation Test

```
┌─────────────┐◀────┌─────────┐
│   Source    │     │  Target │
│   System    │     │  System │
└─────────────────┘     └──────────────┘
```""",
        "expected": """# Left Arrow Preservation Test

```
┌─────────────┐◀────┌─────────┐
│   Source    │     │  Target │
│   System    │     │  System │
└─────────────┘     └─────────┘
```"""
    },

    "arrows/test_12_bidirectional_arrow": {
        "input": """# Bidirectional Arrow Test

```
┌─────────────┐◀──▶┌─────────────┐
│  Service A  │     │  Service B  │
│  Processing │     │  Processing │
└─────────────────┘     └─────────────────┘
```""",
        "expected": """# Bidirectional Arrow Test

```
┌─────────────┐◀──▶┌─────────────┐
│  Service A  │     │  Service B  │
│  Processing │     │  Processing │
└─────────────┘     └─────────────┘
```"""
    },

    "arrows/test_13_vertical_arrow": {
        "input": """# Vertical Arrow Test

```
┌──────────────┐
│   Client     │
│   Layer      │
       │
       ▼
┌─────────────────┐
│   Server       │
│   Layer        │
       ▲
       │
┌─────────────────┐
│   Database     │
│   Layer        │
└─────────────────┘
```""",
        "expected": """# Vertical Arrow Test

```
┌──────────────┐
│   Client     │
│   Layer      │
└──────────────┘
       │
       ▼
┌─────────────────┐
│   Server       │
│   Layer        │
└─────────────────┘
       ▲
       │
┌─────────────────┐
│   Database     │
│   Layer        │
└─────────────────┘
```"""
    },

    # Edge cases
    "edge_cases/test_15_mixed_content": {
        "input": """# Mixed Content Types Test

This is regular text.

```
┌─────────┐
│ Box in  │
│ diagram │
└────────────┘
```

More regular text here.

```python
def code_function():
    print("This is code")
    # Not a box: ┌─┐
```

Another diagram:

```
┌──────────────┐
│ Another box  │
└─────────────────┘
```""",
        "expected": """# Mixed Content Types Test

This is regular text.

```
┌─────────┐
│ Box in  │
│ diagram │
└─────────┘
```

More regular text here.

```python
def code_function():
    print("This is code")
    # Not a box: ┌─┐
```

Another diagram:

```
┌──────────────┐
│ Another box  │
└──────────────┘
```"""
    },

    # Whitespace tests
    "whitespace/test_19_indentation": {
        "input": """# Indentation Preservation Test

This document has indented diagrams:

    ```
    ┌─────────────┐
    │ Indented    │
    │ Box         │
    └────────────────┘
    ```

And another one:

        ```
        ┌──────────┐
        │ More     │
        │ Indented │
        └────────────────┘
        ```""",
        "expected": """# Indentation Preservation Test

This document has indented diagrams:

    ```
    ┌─────────────┐
    │ Indented    │
    │ Box         │
    └─────────────┘
    ```

And another one:

        ```
        ┌──────────┐
        │ More     │
        │ Indented │
        └──────────┘
        ```"""
    },

    # Real-world content
    "real_world/test_36_urls_emails": {
        "input": """# URL/Email in Content Test

```
┌─────────────────────────────┐
│ Contact: user@example.com   │
│ Website: https://site.com   │
│ Path: /usr/local/bin/script │
└────────────────────────┘
```""",
        "expected": """# URL/Email in Content Test

```
┌─────────────────────────────┐
│ Contact: user@example.com   │
│ Website: https://site.com   │
│ Path: /usr/local/bin/script │
└─────────────────────────────┘
```"""
    },

    "real_world/test_41_markdown_export": {
        "input": """# Markdown Export Test

## Architecture Diagram

```
┌──────────────┐     ┌─────────────┐
│   Frontend   │────▶│    API      │
│   React.js   │     │  Gateway    │
└─────────────────┘     └─────────────────┘
```

This diagram should render properly in GitHub, GitLab, etc.
```""",
        "expected": """# Markdown Export Test

## Architecture Diagram

```
┌──────────────┐     ┌─────────────┐
│   Frontend   │────▶│    API      │
│   React.js   │     │  Gateway    │
└──────────────┘     └─────────────┘
```

This diagram should render properly in GitHub, GitLab, etc.
```"""
    },

    # Integration tests
    "integration/test_35_code_comments": {
        "input": """// System Architecture
/*
┌─────────────┐     ┌─────────────┐
│   Module A  │────▶│   Module B  │
│   Handler   │     │   Handler   │
└─────────────────┘     └─────────────────┘
*/

# Python comment style diagram:
# ┌──────────────┐
# │   Config     │
# │   Section    │
# └──────────────┘
""",
        "expected": """// System Architecture
/*
┌─────────────┐     ┌─────────────┐
│   Module A  │────▶│   Module B  │
│   Handler   │     │   Handler   │
└─────────────┘     └─────────────┘
*/

# Python comment style diagram:
# ┌──────────────┐
# │   Config     │
# │   Section    │
# └──────────────┘
"""
    },

    # Additional edge cases
    "edge_cases/test_14_nested_diagrams": {
        "input": """# Nested Diagrams Test

First diagram:
```
┌─────────┐
│ Box A   │
└─────────────┘
```

Some text between diagrams.

Second diagram:
```
┌─────────────┐     ┌─────────────┐
│ Box B       │────▶│   Box C     │
└─────────────────┘     └─────────────────┘
```
""",
        "expected": """# Nested Diagrams Test

First diagram:
```
┌─────────┐
│ Box A   │
└─────────┘
```

Some text between diagrams.

Second diagram:
```
┌─────────────┐     ┌─────────────┐
│ Box B       │────▶│   Box C     │
└─────────────┘     └─────────────┘
```
"""
    },

    "edge_cases/test_16_incomplete_box": {
        "input": """# Incomplete Box Test

```
┌─────────┐
│ Missing │
│ bottom │

┌──────────┐
│ No sides │
└──────────┘

Top only: ┌─────────┐
```""",
        "expected": """# Incomplete Box Test

```
┌─────────┐
│ Missing │
│ bottom │

┌──────────┐
│ No sides │
└──────────┘

Top only: ┌─────────┐
```
"""
    },

    "edge_cases/test_17_overlapping_boxes": {
        "input": """# Overlapping Boxes Test

```
┌─────────┐     ┌─────────────┐
│ Box A   │────▶│   Box B     │
│ ┌─────┐ │     │ ┌─────┐     │
│ │ C   │ │     │ │  D  │     │
│ └─────┘ │     │ └─────┘     │
└─────────────────┘     └─────────────────┘
```""",
        "expected": """# Overlapping Boxes Test

```
┌─────────┐     ┌─────────────┐
│ Box A   │────▶│   Box B     │
│ ┌─────┐ │     │ ┌─────┐     │
│ │ C   │ │     │ │  D  │     │
│ └─────┘ │     │ └─────┘     │
└─────────┘     └─────────────┘
```
"""
    },

    # Whitespace tests
    "whitespace/test_18_trailing_whitespace": {
        "input": """# Trailing Whitespace Preservation Test

```
┌─────────────┐
│ Content     │
│ with spaces │
└─────────────────┘
```""",
        "expected": """# Trailing Whitespace Preservation Test

```
┌─────────────┐
│ Content     │
│ with spaces │
└─────────────┘
```
"""
    },

    "whitespace/test_20_tab_handling": {
        "input": """# Tab vs Space Handling Test

```
┌─────────────┐
│	Tabbed	content	│
│	spaces	and	tabs	│
└─────────────────┘
```""",
        "expected": """# Tab vs Space Handling Test

```
┌─────────────┐
│	Tabbed	content	│
│	spaces	and	tabs	│
└─────────────┘
```
"""
    },

    # Performance tests
    "performance/test_22_multiple_small_diagrams": {
        "input": """# Multiple Small Diagrams Test

Diagram 1:
```
┌─────┐
│ A   │
└─────────┘
```

Diagram 2:
```
┌─────┐────▶┌─────┐
│ B   │     │ C   │
└─────────────┘     └─────────────────┘
```

Diagram 3:
```
┌─────┐
│ D   │
│     │
└─────────────┘
```

Diagram 4:
```
┌─────┐     ┌─────┐
│ E   │────▶│ F   │
└─────────────────┘     └─────────────────┘
```

Diagram 5:
```
┌─────┐────▶┌─────┐────▶┌─────┐
│ G   │     │ H   │     │ I   │
└─────────────┘     └─────────────────┘     └─────────────────┘
```
""",
        "expected": """# Multiple Small Diagrams Test

Diagram 1:
```
┌─────┐
│ A   │
└─────┘
```

Diagram 2:
```
┌─────┐────▶┌─────┐
│ B   │     │ C   │
└─────┘     └─────┘
```

Diagram 3:
```
┌─────┐
│ D   │
│     │
└─────┘
```

Diagram 4:
```
┌─────┐     ┌─────┐
│ E   │────▶│ F   │
└─────┘     └─────┘
```

Diagram 5:
```
┌─────┐────▶┌─────┐────▶┌─────┐
│ G   │     │ H   │     │ I   │
└─────┘     └─────┘     └─────┘
```
"""
    },

    # Error handling tests
    "error_handling/test_23_corrupted_unicode": {
        "input": """# Corrupted Box Characters Test

```
┌─────────┐
│ Content │
└─────┘
┌────────┐
│ Bad box│
└──────┘
```""",
        "expected": """# Corrupted Box Characters Test

```
┌─────────┐
│ Content │
└─────────┘
┌────────┐
│ Bad box│
└────────┘
```
"""
    },

    "error_handling/test_24_memory_limit": {
        "input": """# Memory Limit Test

```
┌""" + "─" * 1000 + """┐
│""" + " " * 998 + """│
│""" + "x" * 998 + """│
└""" + "─" * 1000 + """┘
```""",
        "expected": """# Memory Limit Test

```
┌""" + "─" * 1000 + """┐
│""" + " " * 998 + """│
│""" + "x" * 998 + """│
└""" + "─" * 1000 + """┘
```
"""
    },

    "error_handling/test_25_concurrent_processing": {
        "input": """# Concurrent Processing Test

```
┌─────────────┐
│ Process 1   │
└─────────────────┘
```

```
┌─────────────┐
│ Process 2   │
└─────────────────┘
```

```
┌─────────────┐
│ Process 3   │
└─────────────────┘
```
""",
        "expected": """# Concurrent Processing Test

```
┌─────────────┐
│ Process 1   │
└─────────────┘
```

```
┌─────────────┐
│ Process 2   │
└─────────────┘
```

```
┌─────────────┐
│ Process 3   │
└─────────────┘
```
"""
    },

    # Whitespace sensitivity
    "regression/test_27_whitespace_sensitivity": {
        "input": """# Whitespace Sensitivity Test

Version A:
```
┌─────┐   ┌─────┐
│ A   │──▶│ B   │
└─────────┘   └─────────┘
```

Version B:
```
┌─────┐     ┌─────┐
│ A   │────▶│ B   │
└─────────────────┘     └─────────────────┘
```

Version C:
```
┌─────┐ ┌─────┐
│ A   │▶│ B   │
└─────────┘└─────────┘
```
""",
        "expected": """# Whitespace Sensitivity Test

Version A:
```
┌─────┐   ┌─────┐
│ A   │──▶│ B   │
└─────┘   └─────┘
```

Version B:
```
┌─────┐     ┌─────┐
│ A   │────▶│ B   │
└─────┘     └─────┘
```

Version C:
```
┌─────┐ ┌─────┐
│ A   │▶│ B   │
└─────┘ └─────┘
```
"""
    },

    # Mixed styles
    "mixed_styles/test_29_double_single_border_mix": {
        "input": """# Double and Single Border Mix Test

```
┌─────────┐     ╔═══════════╗
│ Single  │────▶║  Double   ║
│ Border  │     ║  Border   ║
└─────────────────┘     ╚═══════════╝
```""",
        "expected": """# Double and Single Border Mix Test

```
┌─────────┐     ╔═══════════╗
│ Single  │────▶║  Double   ║
│ Border  │     ║  Border   ║
└─────────┘     ╚═══════════╝
```
"""
    },

    # Specialized diagram types
    "specialized/test_30_flowchart_layout": {
        "input": """# Flowchart Layout Test

```
     ┌───────┐
     │ Start │
     └───────┘
        │
        ▼
   ┌─────────┐
   │Decision │
   │   ?     │
   └─────────┘
  ▲         ▼
  │     ┌──────────┐
  │     │  Process │
  │     └──────────┘
  │         │
  └─────────┘
        │
        ▼
     ┌───────┐
     │  End  │
     └───────┘
```""",
        "expected": """# Flowchart Layout Test

```
     ┌───────┐
     │ Start │
     └───────┘
        │
        ▼
   ┌─────────┐
   │Decision │
   │   ?     │
   └─────────┘
  ▲         ▼
  │     ┌──────────┐
  │     │  Process │
  │     └──────────┘
  │         │
  └─────────┘
        │
        ▼
     ┌───────┐
     │  End  │
     └───────┘
```
"""
    },

    "specialized/test_31_tree_structure": {
        "input": """# Tree Structure Test

```
        ┌─────────┐
        │  Root   │
        └─────────┘
      ┌────┴────┐
   ┌─────┐  ┌─────┐
   │Child│  │Child│
   │  1  │  │  2  │
   └─────┘  └─────┘
 ┌───┴───┐       │
┌─────┐ ┌─────┐  ┌─────┐
│Leaf │ │Leaf │  │Leaf │
│  A  │ │  B  │  │  C  │
└─────┘ └─────┘  └─────┘
```""",
        "expected": """# Tree Structure Test

```
        ┌─────────┐
        │  Root   │
        └─────────┘
      ┌────┴────┐
   ┌─────┐  ┌─────┐
   │Child│  │Child│
   │  1  │  │  2  │
   └─────┘  └─────┘
 ┌───┴───┐       │
┌─────┐ ┌─────┐  ┌─────┐
│Leaf │ │Leaf │  │Leaf │
│  A  │ │  B  │  │  C  │
└─────┘ └─────┘  └─────┘
```
"""
    },

    "specialized/test_32_state_machine": {
        "input": """# State Machine Diagram Test

```
┌─────────┐     transition     ┌─────────┐
│  State  │─────────────────▶│  State  │
│   A     │                  │   B     │
└─────────┘                  └─────────┘
      ▲                            │
      │        transition          │
      └────────────────────────────┘

┌─────────┐
│  State  │
│   C     │
└─────────┘
```""",
        "expected": """# State Machine Diagram Test

```
┌─────────┐     transition     ┌─────────┐
│  State  │─────────────────▶│  State  │
│   A     │                  │   B     │
└─────────┘                  └─────────┘
      ▲                            │
      │        transition          │
      └────────────────────────────┘

┌─────────┐
│  State  │
│   C     │
└─────────┘
```
"""
    },

    # Documentation integration
    "integration/test_33_git_diff": {
        "input": """# Git Diff Integration Test

diff --git a/diagram.md b/diagram.md
index abc123..def456 100644
--- a/diagram.md
+++ b/diagram.md
@@ -1,8 +1,8 @@
 # System Diagram

 ```
-┌─────────┐
-│   Old   │
-└─────────────────┘
+┌─────────────┐
+│   New       │
+└─────────────────────┘
 ```

 This is the updated diagram.
""",
        "expected": """# Git Diff Integration Test

diff --git a/diagram.md b/diagram.md
index abc123..def456 100644
--- a/diagram.md
+++ b/diagram.md
@@ -1,8 +1,8 @@
 # System Diagram

 ```
-┌─────────┐
-│   Old   │
-└─────────────────┘
+┌─────────────┐
+│   New       │
+└─────────────────────┘
 ```

 This is the updated diagram.
"""
"""
    },

    "integration/test_34_table_hybrid": {
        "input": """# Table Hybrid Test

Text content here.

```
┌─────────────┐     ┌─────────────┐
│   Table     │────▶│   Data      │
│  Structure  │     │  Flow       │
└─────────────────┘     └─────────────────┘
```

More text content.
""",
        "expected": """# Table Hybrid Test

Text content here.

```
┌─────────────┐     ┌─────────────┐
│   Table     │────▶│   Data      │
│  Structure  │     │  Flow       │
└─────────────┘     └─────────────┘
```

More text content.
"""
"""
    },

    # Real-world scenarios
    "real_world/test_37_mathematical_formulas": {
        "input": """# Mathematical Formulas Test

```
┌─────────────────────────────┐
│        E = mc²              │
│     ┌───┐   ┌───┐           │
│     │ x │ = │ y │           │
│     └───┘   └───┘           │
│     ∫ f(x) dx = F(x) + C    │
│           π ≈ 3.14159       │
└─────────────────────────────┘
```""",
        "expected": """# Mathematical Formulas Test

```
┌─────────────────────────────┐
│        E = mc²              │
│     ┌───┐   ┌───┐           │
│     │ x │ = │ y │           │
│     └───┘   └───┘           │
│     ∫ f(x) dx = F(x) + C    │
│           π ≈ 3.14159       │
└─────────────────────────────┘
```
"""
    },

    "real_world/test_38_multi_language": {
        "input": """# Multi-language Content Test

```
┌─────────────────────────────┐
│   English: Hello World      │
│   French: Bonjour le monde │
│   Arabic: مرحبا بالعالم     │
│   Hebrew: שלום עולם         │
│   Chinese: 你好世界          │
│   Japanese: こんにちは世界    │
│   RTL: טקסט מימין לשמאל   │
│   LTR: Left to Right text   │
└─────────────────────────────┘
```""",
        "expected": """# Multi-language Content Test

```
┌─────────────────────────────┐
│   English: Hello World      │
│   French: Bonjour le monde │
│   Arabic: مرحبا بالعالم     │
│   Hebrew: שלום עולם         │
│   Chinese: 你好世界          │
│   Japanese: こんにちは世界    │
│   RTL: טקסט מימין לשמאל   │
│   LTR: Left to Right text   │
└─────────────────────────────┘
```
"""
    },

    # Tool integration
    "tool_integration/test_39_ide_plugin": {
        "input": """# IDE Plugin Integration Test

// VSCode style diagram:
/*
┌─────────────────┐
│   Editor        │
│   Pane          │
└─────────────────┘
*/

// IntelliJ style:
/*
┌─────────────────┐
│   Project       │
│   View          │
└─────────────────┘
*/

// Terminal output:
$ cat diagram.txt
┌─────────────┐
│ Terminal    │
│ Output      │
└─────────────────┘
""",
        "expected": """# IDE Plugin Integration Test

// VSCode style diagram:
/*
┌─────────────────┐
│   Editor        │
│   Pane          │
└─────────────────┘
*/

// IntelliJ style:
/*
┌─────────────────┐
│   Project       │
│   View          │
└─────────────────┘
*/

// Terminal output:
$ cat diagram.txt
┌─────────────┐
│ Terminal    │
│ Output      │
└─────────────┘
"""
"""
    },

    "tool_integration/test_40_copy_paste_terminal": {
        "input": """# Copy-Paste from Terminal Test

$ ./show_architecture.sh
Architecture:
┌─────────────┐     ┌─────────────┐
│   Service   │────▶│   Service   │
│   Alpha     │     │   Beta      │
└─────────────────┘     └─────────────────┘
[Process completed]

$ docker ps
CONTAINER ID   IMAGE
┌─────────────┐
│   Running   │
│ Container   │
└─────────────────┘
""",
        "expected": """# Copy-Paste from Terminal Test

$ ./show_architecture.sh
Architecture:
┌─────────────┐     ┌─────────────┐
│   Service   │────▶│   Service   │
│   Alpha     │     │   Beta      │
└─────────────┘     └─────────────┘
[Process completed]

$ docker ps
CONTAINER ID   IMAGE
┌─────────────┐
│   Running   │
│ Container   │
└─────────────┘
"""
"""
    },

    # Advanced layout patterns
    "advanced_layout/test_42_overlapping_connections": {
        "input": """# Overlapping Connection Lines Test

```
┌─────┐           ┌─────┐
│ A   │─────────▶│ C   │
└─────┘           └─────┘
    │               ▲
    │               │
    ▼               │
┌─────┐           │
│ B   │───────────┘
└─────┘

┌─────┐     ┌─────┐     ┌─────┐
│ D   │────▶│ E   │────▶│ F   │
└─────┘     └─────┘     └─────┘
    │         │ ▲       │
    │         │ │       │
    └─────────┘ └───────┘
```""",
        "expected": """# Overlapping Connection Lines Test

```
┌─────┐           ┌─────┐
│ A   │─────────▶│ C   │
└─────┘           └─────┘
    │               ▲
    │               │
    ▼               │
┌─────┐           │
│ B   │───────────┘
└─────┘

┌─────┐     ┌─────┐     ┌─────┐
│ D   │────▶│ E   │────▶│ F   │
└─────┘     └─────┘     └─────┘
    │         │ ▲       │
    │         │ │       │
    └─────────┘ └───────┘
```
"""
    },

    "advanced_layout/test_43_variable_width_characters": {
        "input": """# Variable Width Characters Test

```
┌─────────────────────────────┐
│ Normal: ABC                 │
│ Wide: ＡＢＣ                 │
│ Mixed: ABCＡＢＣ             │
│ Emoji: 🌍🚀💻               │
│ Symbols: ◆●■▲              │
└─────────────────────────────┘
```""",
        "expected": """# Variable Width Characters Test

```
┌─────────────────────────────┐
│ Normal: ABC                 │
│ Wide: ＡＢＣ                 │
│ Mixed: ABCＡＢＣ             │
│ Emoji: 🌍🚀💻               │
│ Symbols: ◆●■▲              │
└─────────────────────────────┘
```
"""
    },

    "advanced_layout/test_44_diagonal_hybrid": {
        "input": """# Diagonal/Hybrid Layout Test

```
    ┌─────┐
    │ A   │
    └─────┘
     ↘     ↙
      ┌─────┐
      │ B   │
      └─────┘
     ↙     ↘
┌─────┐     ┌─────┐
│ C   │────▶│ D   │
└─────┘     └─────┘
     ↖     ↗
      ┌─────┐
      │ E   │
      └─────┘
```""",
        "expected": """# Diagonal/Hybrid Layout Test

```
    ┌─────┐
    │ A   │
    └─────┘
     ↘     ↙
      ┌─────┐
      │ B   │
      └─────┘
     ↙     ↘
┌─────┐     ┌─────┐
│ C   │────▶│ D   │
└─────┘     └─────┘
     ↖     ↗
      ┌─────┐
      │ E   │
      └─────┘
```
"""
    },

    # Collaborative workflow
    "collaborative/test_45_version_control_merge": {
        "input": """# Version Control Merge Test

## Original Diagram
```
┌─────────┐
│ Service │
│ Alpha   │
└─────────────────┘
```

## Branch A Changes
```
┌─────────────┐
│   Service   │
│   Alpha     │
└─────────────────┘
```

## Branch B Changes
```
┌─────────┐     ┌─────────┐
│ Service │────▶│ Service │
│ Alpha   │     │ Beta    │
└─────────────────┘     └─────────────────┘
```

## Merged Result (needs fixing)
```
┌─────────┐     ┌─────────────┐
│ Service │────▶│   Service   │
│ Alpha   │     │   Alpha     │
└─────────────────┘     └─────────────────────┘
```""",
        "expected": """# Version Control Merge Test

## Original Diagram
```
┌─────────┐
│ Service │
│ Alpha   │
└─────────┘
```

## Branch A Changes
```
┌─────────────┐
│   Service   │
│   Alpha     │
└─────────────┘
```

## Branch B Changes
```
┌─────────┐     ┌─────────┐
│ Service │────▶│ Service │
│ Alpha   │     │ Beta    │
└─────────┘     └─────────┘
```

## Merged Result (needs fixing)
```
┌─────────┐     ┌─────────────┐
│ Service │────▶│   Service   │
│ Alpha   │     │   Alpha     │
└─────────┘     └─────────────┘
```
"""
"""

    },

    "collaborative/test_46_multi_contributor": {
        "input": """# Multi-contributor Style Test

## Contributor A Style
```
┌───────────┐
│ Component │
│     A     │
└─────────────────┘
```

## Contributor B Style
```
┌─────────────────┐
│   Component B   │
└─────────────────┘
```

## Contributor C Style
```
┌─────┐
│ C   │
└──────────────┘
```

## Mixed Contributors Diagram
```
┌───────────┐     ┌─────────────────┐     ┌─────┐
│ Component │────▶│   Component B   │────▶│ C   │
│     A     │     └─────────────────────┘     └────────────────┘
└─────────────────┘
```""",
        "expected": """# Multi-contributor Style Test

## Contributor A Style
```
┌───────────┐
│ Component │
│     A     │
└───────────┘
```

## Contributor B Style
```
┌─────────────────┐
│   Component B   │
└─────────────────┘
```

## Contributor C Style
```
┌─────┐
│ C   │
└─────┘
```

## Mixed Contributors Diagram
```
┌───────────┐     ┌─────────────────┐     ┌─────┐
│ Component │────▶│   Component B   │────▶│ C   │
│     A     │     └─────────────────┘     └─────┘
└───────────┘
```
"""
"""

    },

    # Accessibility and standards
    "accessibility/test_47_screen_reader": {
        "input": """# Screen Reader Compatibility Test

## Accessible Diagram
```
┌─────────────────────────────┐
│   Start Process              │
│   [Button: Click to start]  │
└─────────────────────────────┘
           │
           ▼
┌─────────────────────────────┐
│   Processing...              │
│   [Status: In progress]      │
└─────────────────────────────┘
```

## Alternative Text Reference
Diagram shows: Start Process button leads to Processing status.
""",
        "expected": """# Screen Reader Compatibility Test

## Accessible Diagram
```
┌─────────────────────────────┐
│   Start Process              │
│   [Button: Click to start]  │
└─────────────────────────────┘
           │
           ▼
┌─────────────────────────────┐
│   Processing...              │
│   [Status: In progress]      │
└─────────────────────────────┘
```

## Alternative Text Reference
Diagram shows: Start Process button leads to Processing status.
"""
"""
    },

    "accessibility/test_48_ansi_codes": {
        "input": """# ANSI Color Codes Integration Test

## Colored Terminal Output
```\x1b[31m
┌─────────────────┐
│   \x1b[1mERROR\x1b[0m       │
│   \x1b[31mFailed\x1b[0m     │
└─────────────────┘
\x1b[0m
```

## Success Message
```\x1b[32m
┌─────────────────┐
│   \x1b[1mSUCCESS\x1b[0m     │
│   \x1b[32mComplete\x1b[0m   │
└─────────────────┘
\x1b[0m
```

## Warning
```\x1b[33m
┌─────────────────┐
│   \x1b[1mWARNING\x1b[0m     │
│   \x1b[33mCaution\x1b[0m    │
└─────────────────┘
\x1b[0m
```
""",
        "expected": """# ANSI Color Codes Integration Test

## Colored Terminal Output
```\x1b[31m
┌─────────────────┐
│   \x1b[1mERROR\x1b[0m       │
│   \x1b[31mFailed\x1b[0m     │
└─────────────────┘
\x1b[0m
```

## Success Message
```\x1b[32m
┌─────────────────┐
│   \x1b[1mSUCCESS\x1b[0m     │
│   \x1b[32mComplete\x1b[0m   │
└─────────────────┘
\x1b[0m
```

## Warning
```\x1b[33m
┌─────────────────┐
│   \x1b[1mWARNING\x1b[0m     │
│   \x1b[33mCaution\x1b[0m    │
└─────────────────┘
\x1b[0m
```
"""
"""

    },

    # Performance edge cases
    "performance_edge/test_49_streaming_large_file": {
        "input": """# Streaming/Large File Processing Test

""" + "```\n┌─────────┐\n│ Block " + "\n".join([f"│ Line {i:03d}" for i in range(1000)]) + "\n│ End     \n└─────────┘\n```""",
        "expected": """# Streaming/Large File Processing Test

""" + "```\n┌─────────┐\n│ Block " + "\n".join([f"│ Line {i:03d}" for i in range(1000)]) + "\n│ End     \n└─────────┘\n```"""
    },

    "performance_edge/test_50_real_time_editing": {
        "input": """# Real-time Editing Test

## Initial State
```
┌─────────┐
│ Box A   │
└─────────────────┘
```

## Concurrent Edit 1 (while processing)
```
┌─────────────┐
│   Box A     │
└─────────────────────┘
```

## Concurrent Edit 2 (while processing)
```
┌─────────────┐     ┌─────────────┐
│   Box A     │────▶│   Box B     │
└─────────────────────┘     └─────────────────────┘
```

## Final Expected State
```
┌─────────────┐     ┌─────────────┐
│   Box A     │────▶│   Box B     │
└─────────────┘     └─────────────┘
```
""",
        "expected": """# Real-time Editing Test

## Initial State
```
┌─────────┐
│ Box A   │
└─────────┘
```

## Concurrent Edit 1 (while processing)
```
┌─────────────┐
│   Box A     │
└─────────────┘
```

## Concurrent Edit 2 (while processing)
```
┌─────────────┐     ┌─────────────┐
│   Box A     │────▶│   Box B     │
└─────────────┘     └─────────────┘
```

## Final Expected State
```
┌─────────────┐     ┌─────────────┐
│   Box A     │────▶│   Box B     │
└─────────────┘     └─────────────┘
```
"""
"""

    }
}

def create_test_files():
    """Create all test input and expected output files."""
    base_path = Path(".")

    print("Generating test files...")

    for test_name, data in TEST_TEMPLATES.items():
        # Create directory if it doesn't exist
        test_dir = base_path / test_name.rsplit("/", 1)[0]
        test_dir.mkdir(parents=True, exist_ok=True)

        # Write input file
        input_path = base_path / f"{test_name}_input.md"
        with open(input_path, 'w', encoding='utf-8') as f:
            f.write(data["input"])

        # Write expected file
        expected_path = base_path / f"{test_name}_expected.md"
        with open(expected_path, 'w', encoding='utf-8') as f:
            f.write(data["expected"])

        print(f"Created: {test_name}")

    print(f"\nGenerated {len(TEST_TEMPLATES)} test case pairs.")
    print("Each test has an _input.md and _expected.md file.")

if __name__ == "__main__":
    create_test_files()