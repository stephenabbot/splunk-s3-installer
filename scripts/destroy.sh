#!/bin/bash
# scripts/destroy.sh - Safely destroy all Splunk installer resources

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

echo "🚨 DESTROY SPLUNK INSTALLER RESOURCES 🚨"
echo ""

# Source configuration
if [ ! -f "config.env" ]; then
    print_error "config.env file not found"
    exit 1
fi

source config.env

# Get AWS account info and git metadata
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=${AWS_REGION:-us-east-1}

# Extract git repository information
GIT_REMOTE=$(git remote get-url origin 2>/dev/null || echo "")
if [[ "$GIT_REMOTE" =~ github\.com[:/]([^/]+)/([^/.]+) ]]; then
    PROJECT_NAME="${BASH_REMATCH[2]}"
else
    PROJECT_NAME="splunk-s3-installer"
fi

echo -e "${YELLOW}⚠${NC} This will PERMANENTLY DELETE all resources managed by this project:"
echo "  • S3 buckets tagged with ManagedBy=splunk-s3-installer"
echo "  • All Splunk installer files"
echo "  • SSM parameters tagged with ManagedBy=splunk-s3-installer"
echo "  • Local cache files"
echo ""
echo -e "${RED}✗${NC} THIS ACTION CANNOT BE UNDONE!"
echo ""

# Confirmation prompt
if [ "${1:-}" = "--force" ]; then
    print_warning "Force mode enabled - skipping confirmation"
else
    read -p "Type 'DESTROY' to confirm destruction: " confirmation
    if [ "$confirmation" != "DESTROY" ]; then
        echo "Destruction cancelled."
        exit 0
    fi
fi

echo ""
print_status "Beginning resource destruction..."

# Delete SSM parameters by tag
print_status "Deleting SSM parameters..."
for param in "/splunk-s3-installer/installer-url" "/splunk-s3-installer/bucket-name"; do
    if aws ssm delete-parameter --name "$param" >/dev/null 2>&1; then
        print_success "Deleted parameter: $param"
    else
        print_warning "Parameter not found or already deleted: $param"
    fi
done

# Delete S3 buckets by tag
print_status "Deleting S3 buckets managed by this project..."
for bucket in $(aws s3api list-buckets --query 'Buckets[].Name' --output text 2>/dev/null); do
    # Check if bucket has our management tag
    if aws s3api get-bucket-tagging --bucket "$bucket" --query 'TagSet[?Key==`ManagedBy`].Value' --output text 2>/dev/null | grep -q "splunk-s3-installer"; then
        print_status "Found managed bucket: $bucket"
        
        # Delete all objects first
        if aws s3 rm "s3://$bucket" --recursive >/dev/null 2>&1; then
            print_success "Deleted all objects from bucket: $bucket"
        fi
        
        # Delete the bucket
        if aws s3 rb "s3://$bucket" >/dev/null 2>&1; then
            print_success "Deleted S3 bucket: $bucket"
        else
            print_error "Failed to delete S3 bucket: $bucket"
        fi
    fi
done

# Clean up local cache
if [ -d "${CACHE_DIR:-/tmp/splunk-installer-cache}" ]; then
    print_status "Cleaning up local cache..."
    rm -rf "${CACHE_DIR:-/tmp/splunk-installer-cache}"
    print_success "Local cache cleaned"
fi

echo ""
print_success "🗑️ DESTRUCTION COMPLETE"
echo ""
print_status "Verifying all resources were destroyed..."
echo ""

# Run list-deployed-resources to verify cleanup
./scripts/list-deployed-resources.sh

echo ""
print_status "If any resources are still listed above, they may need manual cleanup."
print_status "You can run ./scripts/update-splunk-installer.sh to recreate them when needed."
