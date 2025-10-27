# Prepare Next Target Test

You have successfully completed a test fix and achieved improvement. Now prepare the next target test by updating the regression script and documentation.

## What to Update

### 1. Update Regression Script Defaults
Edit `regression_safe_test.sh` to update the default target:

```bash
# Find this line in regression_safe_test.sh:
DEFAULT_TARGET="arrows/test_12_bidirectional_arrow"

# Replace with the new target:
DEFAULT_TARGET="path/to/next/target/test"
```

### 2. Update Mission Documentation
Update `NEXT_AGENT_MISSION.md`:

- Change the primary target section to reflect the new test
- Update the specific issue description
- Adjust the expected vs actual behavior
- Update any test-specific implementation details

### 3. Consider Test Pattern Analysis
Analyze the new target to determine:

- Is this similar to previous successful patterns?
- Does it require new research or technical approaches?
- Are there related tests that might also be fixed?
- What's the expected difficulty level?

## Current Context

You just successfully completed: `{current_target}`

Look at the test results to identify the next logical target:
- Check which tests are still failing
- Prioritize tests that seem similar to patterns you've already solved
- Consider tests that might be fixed by the same logic changes

## Questions to Consider

1. **What was the key insight** that made the current fix successful?
2. **Can that insight be applied** to other failing tests?
3. **What's the next easiest target** that builds on current success?
4. **Do any tests require new research** or technical approaches?

## Validation

After updating defaults:

1. Test the regression script: `./regression_safe_test.sh`
2. Verify it targets the correct test
3. Confirm documentation is accurate
4. Run a quick test to ensure the new target is indeed failing (needs fixing)

## Goal

Set up the next agent for success by providing clear, accurate targeting and streamlined tooling for continued incremental improvement.