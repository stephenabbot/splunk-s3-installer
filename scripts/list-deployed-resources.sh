#!/bin/bash
# scripts/list-deployed-resources.sh - List all deployed resources

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
print_error() { echo -e "${RED}✗${NC} $1"; }

echo "📋 DEPLOYED RESOURCES"
echo ""

# Source configuration
if [ ! -f "config.env" ]; then
    print_error "config.env file not found"
    exit 1
fi

source config.env

# Get AWS account info and git metadata
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "unknown")
REGION=${AWS_REGION:-us-east-1}

# Extract git repository information
GIT_REMOTE=$(git remote get-url origin 2>/dev/null || echo "")
if [[ "$GIT_REMOTE" =~ github\.com[:/]([^/]+)/([^/.]+) ]]; then
    PROJECT_NAME="${BASH_REMATCH[2]}"
else
    PROJECT_NAME="splunk-s3-installer"
fi

echo "Account ID: $ACCOUNT_ID"
echo "Region: $REGION"
echo "Project: $PROJECT_NAME"
echo ""

# Find S3 buckets managed by this project
print_status "S3 Resources (managed by this project):"
found_buckets=false

# Get all buckets and check tags
for bucket in $(aws s3api list-buckets --query 'Buckets[].Name' --output text 2>/dev/null); do
    # Check if bucket has our management tag
    if aws s3api get-bucket-tagging --bucket "$bucket" --query 'TagSet[?Key==`ManagedBy`].Value' --output text 2>/dev/null | grep -q "splunk-s3-installer"; then
        found_buckets=true
        print_success "Bucket: $bucket"
        
        # List objects in bucket
        echo "  Objects:"
        aws s3 ls "s3://$bucket" --human-readable --summarize 2>/dev/null | while read line; do
            if [[ "$line" =~ ^[0-9] ]]; then
                echo "    $line"
            fi
        done
        
        # Get bucket size
        bucket_size=$(aws s3 ls "s3://$bucket" --recursive --human-readable --summarize 2>/dev/null | grep "Total Size" | awk '{print $3, $4}')
        if [ -n "$bucket_size" ]; then
            echo "  Total Size: $bucket_size"
        fi
        
        # Show bucket tags
        echo "  Tags:"
        aws s3api get-bucket-tagging --bucket "$bucket" --query 'TagSet[].[Key,Value]' --output text 2>/dev/null | while read key value; do
            echo "    $key: $value"
        done
    fi
done

if [ "$found_buckets" = false ]; then
    print_error "No S3 buckets found managed by this project"
fi

echo ""

# Find SSM parameters managed by this project
print_status "SSM Parameters (managed by this project):"
found_params=false

# Check our specific parameters
for param in "/splunk-s3-installer/installer-url" "/splunk-s3-installer/bucket-name"; do
    if value=$(aws ssm get-parameter --name "$param" --query 'Parameter.Value' --output text 2>/dev/null); then
        # Verify it has our management tag
        if aws ssm list-tags-for-resource --resource-type "Parameter" --resource-id "$param" --query 'TagList[?Key==`ManagedBy`].Value' --output text 2>/dev/null | grep -q "splunk-s3-installer"; then
            found_params=true
            print_success "$param = $value"
        fi
    fi
done

if [ "$found_params" = false ]; then
    print_error "No SSM parameters found managed by this project"
fi

echo ""

# Check current installer info
print_status "Current Installer Info:"
if installer_url=$(aws ssm get-parameter --name "/splunk-s3-installer/installer-url" --query 'Parameter.Value' --output text 2>/dev/null); then
    filename=$(basename "$installer_url")
    if [[ "$filename" =~ splunk-([0-9]+\.[0-9]+\.[0-9]+)-([a-f0-9]+)\.x86_64\.rpm ]]; then
        version="${BASH_REMATCH[1]}"
        build="${BASH_REMATCH[2]}"
        echo "  Version: $version"
        echo "  Build: $build"
        echo "  Filename: $filename"
    else
        echo "  Filename: $filename"
    fi
else
    print_error "No installer URL found in SSM"
fi

echo ""

# Usage instructions
print_status "Usage Instructions:"
echo "To use this installer in EC2 instances:"
echo ""
echo "# Get installer URL"
echo "INSTALLER_URL=\$(aws ssm get-parameter --name '/splunk-s3-installer/installer-url' --query 'Parameter.Value' --output text)"
echo ""
echo "# Download installer"
echo "aws s3 cp \"\$INSTALLER_URL\" /tmp/splunk-installer.rpm"
echo "sudo yum install -y /tmp/splunk-installer.rpm"
echo ""
echo "sudo systemctl start splunk"
