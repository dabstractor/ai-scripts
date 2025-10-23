#!/usr/bin/env python3
"""
Simple test runner for diagram alignment utility.
Run with: python3 run_tests.py
"""

import os
import sys
import subprocess
from pathlib import Path
from typing import List


def discover_tests(test_dir: Path) -> List[dict]:
    """Discover all test cases in the test_data directory."""
    tests = []

    for test_file in test_dir.rglob("*_input.md"):
        # Extract test name and path
        rel_path = test_file.relative_to(test_dir)
        test_name = str(rel_path).replace("_input.md", "")

        # Check if expected file exists
        expected_file = test_dir / f"{test_name}_expected.md"
        if expected_file.exists():
            tests.append({
                "name": test_name,
                "input": str(test_file),
                "expected": str(expected_file)
            })

    return sorted(tests, key=lambda x: x['name'])

def run_test(test_info: dict) -> bool:
    """Run a single test case."""
    print(f"Running: {test_info['name']}")

    # Copy input to temporary location for processing
    import tempfile
    import shutil

    with tempfile.NamedTemporaryFile(mode='w', suffix='.md', delete=False) as temp_file:
        with open(test_info['input'], 'r') as f:
            temp_file.write(f.read())
        temp_path = temp_file.name

    try:
        # Run the fix_diagram script
        result = subprocess.run([
            sys.executable, 'fix_diagram.py', temp_path
        ], capture_output=True, text=True)

        if result.returncode != 0:
            print(f"  ❌ FAILED: Script error - {result.stderr}")
            return False

        # Read the actual output
        with open(temp_path, 'r') as f:
            actual_output = f.read()

        # Read the expected output
        with open(test_info['expected'], 'r') as f:
            expected_output = f.read()

        if actual_output == expected_output:
            print(f"  ✅ PASSED")
            return True
        else:
            print(f"  ❌ FAILED: Output mismatch")
            # Show first few lines of diff for debugging
            actual_lines = actual_output.split('\n')[:10]
            expected_lines = expected_output.split('\n')[:10]
            print(f"    Expected: {expected_lines}")
            print(f"    Actual:   {actual_lines}")
            return False

    except FileNotFoundError as e:
        print(f"  ❌ FAILED: File not found - {e}")
        return False
    finally:
        # Clean up temporary file
        Path(temp_path).unlink(missing_ok=True)

def main():
    """Run all tests."""
    print("Diagram Alignment Test Suite")
    print("=" * 50)

    # Check if fix_diagram.py exists
    if not Path("fix_diagram.py").exists():
        print("Error: fix_diagram.py not found in current directory")
        sys.exit(1)

    # Discover all tests
    test_dir = Path("test_data")
    if not test_dir.exists():
        print("Error: test_data directory not found")
        sys.exit(1)

    tests = discover_tests(test_dir)

    if not tests:
        print("No tests found in test_data directory")
        return

    print(f"Found {len(tests)} test cases")
    print()

    # Run tests and track results
    passed = 0
    failed = 0

    for test in tests:
        if run_test(test):
            passed += 1
        else:
            failed += 1

    # Summary
    print()
    print("=" * 50)
    print(f"Test Results: {passed} passed, {failed} failed out of {len(tests)} tests")

    if failed == 0:
        print("🎉 All tests passed!")
        return 0
    else:
        print("❌ Some tests failed")
        return 1

if __name__ == "__main__":
    sys.exit(main())