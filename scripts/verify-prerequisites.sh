#!/bin/bash
# scripts/verify-prerequisites.sh - Verify deployment prerequisites

set -euo pipefail

# Change to project root directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$PROJECT_ROOT"

# Disable AWS CLI pager
export AWS_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() { echo -e "${BLUE}ℹ${NC} $1"; }
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }

echo "🔍 VERIFYING PREREQUISITES"
echo ""

# Source configuration
if [ ! -f "config.env" ]; then
    print_error "config.env file not found"
    exit 1
fi

source config.env

# Track test results
tests_passed=0
tests_failed=0
test_names=()
test_results=()

# Test function
run_test() {
    local test_name="$1"
    local test_command="$2"
    
    print_status "Testing $test_name..."
    
    if eval "$test_command" >/dev/null 2>&1; then
        print_success "$test_name"
        test_names+=("$test_name")
        test_results+=("✓")
        ((tests_passed++))
    else
        print_error "$test_name failed"
        test_names+=("$test_name")
        test_results+=("✗")
        ((tests_failed++))
    fi
}

# Check required tools
print_status "Checking required tools..."
REQUIRED_TOOLS=("aws" "curl" "jq" "file")
for tool in "${REQUIRED_TOOLS[@]}"; do
    if command -v "$tool" &> /dev/null; then
        print_success "$tool available"
        test_names+=("$tool")
        test_results+=("✓")
        ((tests_passed++))
    else
        print_error "$tool not found"
        test_names+=("$tool")
        test_results+=("✗")
        ((tests_failed++))
    fi
done

# Test AWS credentials
run_test "AWS credentials" "aws sts get-caller-identity"

# Test AWS permissions
run_test "S3 list buckets" "aws s3 ls"
run_test "SSM get parameter (test)" "aws ssm get-parameters --names '/test' || true"

# Create cache directory
if mkdir -p "$CACHE_DIR" 2>/dev/null; then
    print_success "Cache directory accessible: $CACHE_DIR"
    test_names+=("Cache directory")
    test_results+=("✓")
    ((tests_passed++))
else
    print_error "Cannot create cache directory: $CACHE_DIR"
    test_names+=("Cache directory")
    test_results+=("✗")
    ((tests_failed++))
fi

echo ""
echo "📋 PREREQUISITE SUMMARY"
echo "======================="

# Display results table
for i in "${!test_names[@]}"; do
    printf "%-25s %s\n" "${test_names[$i]}" "${test_results[$i]}"
done

echo ""
echo "Tests passed: $tests_passed"
echo "Tests failed: $tests_failed"

if [ $tests_failed -eq 0 ]; then
    print_success "All prerequisites verified"
    exit 0
else
    print_error "Some prerequisites failed"
    exit 1
fi
