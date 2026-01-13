# Session Transfer Instructions

## CRITICAL: Context Overflow Recovery Protocol

This document provides instructions for AI agents taking over after context window overflow events.

## Project Implementation Status

**Project**: Splunk S3 Installer Management System
**Current State**: Implementation complete, testing and bug fixes needed

## Required Actions

### 1. Verification Only Operations
- Use AWS SDK calls to verify S3 bucket configuration
- Use URL calls to test Splunk advisory parsing
- Check SSM parameter existence and values
- Verify script file permissions and executability

### 2. Script Testing Protocol
Execute scripts in this order to verify functionality:

```bash
# Test prerequisite verification
./scripts/verify-prerequisites.sh

# Test main installer management
./scripts/update-splunk-installer.sh

# Test resource listing
./scripts/list-deployed-resources.sh

# Test cleanup (optional)
echo "DESTROY" | ./scripts/destroy.sh
```

### 3. Problem Identification and Fixes

**Known Issues to Check:**
- SSM parameter creation with `--tags` and `--overwrite` flags conflict
- Version comparison logic when advisory parsing fails
- Credential validation for Splunk authentication
- S3 bucket tagging format consistency

**Fix Approach:**
- Identify specific error messages from script execution
- Locate problematic code sections in scripts
- Apply minimal fixes to resolve AWS CLI validation errors
- Test fixes with script re-execution

### 4. Documentation References

Read these files for context:
- `docs/script-logic-flow.md` - Implementation logic and workflow
- `config.env` - Configuration values and credentials
- `ai_setup/00_mandatory_initialization.md` - Authorization requirements

## Implementation Constraints

- **NO NEW FEATURES** - Only fix existing functionality
- **USE EXISTING SCRIPTS** - Do not rewrite, only debug and fix
- **MINIMAL CHANGES** - Apply smallest possible fixes
- **TEST DRIVEN** - Verify each fix with script execution

## Success Criteria

1. All scripts execute without errors
2. S3 bucket and SSM parameters created successfully
3. Version detection and comparison logic works correctly
4. Resource cleanup functions properly
5. Idempotent operations (multiple runs produce same result)

## Authorization Required

Before making any changes:
1. Confirm understanding of current implementation
2. Get explicit authorization to proceed with fixes
3. Report findings and proposed solutions before implementation
