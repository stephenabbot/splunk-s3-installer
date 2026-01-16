#!/bin/bash
# scripts/update-splunk-installer.sh - Download and manage Splunk installer in S3

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

echo "🚀 SPLUNK INSTALLER MANAGEMENT"
echo ""

# Source configuration
if [ ! -f "config.env" ]; then
    print_error "config.env file not found"
    exit 1
fi

source config.env

# Verify prerequisites first
print_status "Verifying prerequisites..."
if ! ./scripts/verify-prerequisites.sh; then
    print_error "Prerequisites check failed"
    exit 1
fi

# Get AWS account info and git metadata
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=${AWS_REGION:-us-east-1}
DEPLOYED_BY=$(aws sts get-caller-identity --query Arn --output text)

# Extract git repository information
GIT_REMOTE=$(git remote get-url origin 2>/dev/null || echo "")
if [[ "$GIT_REMOTE" =~ github\.com[:/]([^/]+)/([^/.]+) ]]; then
    PROJECT_NAME="${BASH_REMATCH[2]}"
    REPOSITORY="$GIT_REMOTE"
else
    PROJECT_NAME="splunk-s3-installer"
    REPOSITORY="unknown"
fi

# S3 bucket name
BUCKET_NAME="splunk-installer-${ACCOUNT_ID}-${REGION}"

print_status "Using S3 bucket: $BUCKET_NAME"
print_status "Project: $PROJECT_NAME"

# Check if bucket exists, create if not
if ! aws s3 ls "s3://$BUCKET_NAME" >/dev/null 2>&1; then
    print_status "Creating S3 bucket: $BUCKET_NAME"
    
    if [ "$REGION" = "us-east-1" ]; then
        aws s3 mb "s3://$BUCKET_NAME"
    else
        aws s3 mb "s3://$BUCKET_NAME" --region "$REGION"
    fi
    
    # Configure bucket encryption
    aws s3api put-bucket-encryption \
        --bucket "$BUCKET_NAME" \
        --server-side-encryption-configuration '{
            "Rules": [{
                "ApplyServerSideEncryptionByDefault": {
                    "SSEAlgorithm": "AES256"
                }
            }]
        }'
    
    # Block public access
    aws s3api put-public-access-block \
        --bucket "$BUCKET_NAME" \
        --public-access-block-configuration \
        "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
    
    # Apply bucket tags
    aws s3api put-bucket-tagging \
        --bucket "$BUCKET_NAME" \
        --tagging "TagSet=[
            {Key=Project,Value=$PROJECT_NAME},
            {Key=Repository,Value=$REPOSITORY},
            {Key=Environment,Value=$ENVIRONMENT},
            {Key=Owner,Value=$OWNER},
            {Key=CostCenter,Value=$COST_CENTER},
            {Key=ManagedBy,Value=splunk-s3-installer},
            {Key=DeployedBy,Value=$DEPLOYED_BY}
        ]"
    
    # Apply bucket policy for account-wide access
    aws s3api put-bucket-policy \
        --bucket "$BUCKET_NAME" \
        --policy "{
            \"Version\": \"2012-10-17\",
            \"Statement\": [{
                \"Effect\": \"Allow\",
                \"Principal\": {\"AWS\": \"arn:aws:iam::${ACCOUNT_ID}:root\"},
                \"Action\": \"s3:GetObject\",
                \"Resource\": \"arn:aws:s3:::${BUCKET_NAME}/*\"
            }]
        }"
    
    print_success "S3 bucket created and configured"
else
    print_success "S3 bucket exists"
fi

# Function to get latest Splunk version from endoflife.date API
get_latest_splunk_version() {
    local api_response
    if ! api_response=$(curl -s "https://endoflife.date/api/splunk.json" 2>/dev/null); then
        return 1
    fi
    
    if [ -z "$api_response" ] || [ "$api_response" = "null" ]; then
        return 1
    fi
    
    # Parse JSON to get latest supported version (not EOL)
    local latest_version
    latest_version=$(echo "$api_response" | jq -r '
        map(select(.eol > now or (.eol | type) == "boolean" and .eol == false)) |
        sort_by(.cycle | split(".") | map(tonumber)) |
        reverse |
        .[0] |
        .latest // .cycle
    ' 2>/dev/null)
    
    if [ -z "$latest_version" ] || [ "$latest_version" = "null" ]; then
        return 1
    fi
    
    echo "$latest_version"
}

# Function to get current S3 installer version
get_current_s3_version() {
    # List objects in S3 bucket and extract version from filename
    local s3_objects
    s3_objects=$(aws s3 ls "s3://$BUCKET_NAME/rpm/" 2>/dev/null | grep -E "splunk-.*\.rpm$" || echo "")
    
    if [ -z "$s3_objects" ]; then
        echo "none"
        return 0
    fi
    
    # Extract version from filename
    local current_file
    current_file=$(echo "$s3_objects" | awk '{print $4}' | head -1)
    
    local current_version
    if [[ "$current_file" =~ splunk-([0-9]+\.[0-9]+\.[0-9]+)- ]]; then
        current_version="${BASH_REMATCH[1]}"
        echo "$current_version:rpm/$current_file"
    else
        echo "none"
    fi
}

# Function to compare versions (returns 0 if first version is newer, 1 if equal, 2 if older)
version_compare() {
    local version1="$1"
    local version2="$2"
    
    if [ "$version1" = "$version2" ]; then
        return 1  # Equal
    fi
    
    # Compare major.minor only (ignore patch)
    local v1_major_minor
    local v2_major_minor
    v1_major_minor=$(echo "$version1" | cut -d. -f1-2)
    v2_major_minor=$(echo "$version2" | cut -d. -f1-2)
    
    if [ "$v1_major_minor" = "$v2_major_minor" ]; then
        return 1  # Same major.minor, consider equal
    fi
    
    # Use sort -V to compare versions
    local newer
    newer=$(printf '%s\n%s\n' "$v1_major_minor" "$v2_major_minor" | sort -V | tail -1)
    
    if [ "$newer" = "$v1_major_minor" ]; then
        return 0  # version1 is newer
    else
        return 2  # version2 is newer
    fi
}

# Get latest version from API
print_status "Determining latest Splunk version..."
if LATEST_VERSION=$(get_latest_splunk_version); then
    print_success "Found latest supported version: $LATEST_VERSION"
else
    print_warning "Could not determine latest version from API"
    print_status "Using fallback version: 10.0.2"
    LATEST_VERSION="10.0.2"
fi

# Check current S3 version
print_status "Checking current S3 installer version..."
current_s3_info=$(get_current_s3_version)

if [ "$current_s3_info" = "none" ]; then
    print_status "No installer found in S3, download needed"
    NEEDS_UPDATE=true
    CURRENT_VERSION="none"
    CURRENT_FILE=""
else
    CURRENT_VERSION=$(echo "$current_s3_info" | cut -d: -f1)
    CURRENT_FILE=$(echo "$current_s3_info" | cut -d: -f2)
    print_success "Current S3 installer: $CURRENT_VERSION"
    
    # Compare versions
    if version_compare "$LATEST_VERSION" "$CURRENT_VERSION"; then
        case $? in
            0) # Latest is newer
                print_status "Newer version available: $LATEST_VERSION (current: $CURRENT_VERSION)"
                NEEDS_UPDATE=true
                ;;
            1) # Same version
                print_success "S3 installer is current (version $CURRENT_VERSION)"
                NEEDS_UPDATE=false
                ;;
            2) # Current is newer (shouldn't happen)
                print_success "S3 installer is newer than latest supported (version $CURRENT_VERSION)"
                NEEDS_UPDATE=false
                ;;
        esac
    fi
fi

# Get build number for version
get_build_number() {
    local version="$1"
    case "$version" in
        "10.0.2") echo "e2d18b4767e9" ;;
        "10.0.1") echo "c7126eee4e6b" ;;
        "10.0.0") echo "1234567890ab" ;;  # Placeholder
        "9.4.7")  echo "a1a6394cc5ae" ;;  # Placeholder - need real build
        *) echo "" ;;
    esac
}

BUILD_NUMBER=$(get_build_number "$LATEST_VERSION")
if [ -z "$BUILD_NUMBER" ]; then
    print_error "Unknown build number for version $LATEST_VERSION"
    print_status "Please update get_build_number function in script"
    exit 1
fi

INSTALLER_FILENAME="splunk-${LATEST_VERSION}-${BUILD_NUMBER}.x86_64.rpm"
DOWNLOAD_URL="https://download.splunk.com/products/splunk/releases/${LATEST_VERSION}/linux/${INSTALLER_FILENAME}"

if [ "$NEEDS_UPDATE" = true ]; then
    print_status "Update needed - will download Splunk $LATEST_VERSION"
    
    # Show confirmation prompt
    echo ""
    echo "📋 UPDATE SUMMARY"
    echo "================="
    if [ "$CURRENT_VERSION" != "none" ]; then
        echo "Current: $CURRENT_VERSION"
    else
        echo "Current: No installer in S3"
    fi
    echo "Latest:  $LATEST_VERSION"
    echo "File:    $INSTALLER_FILENAME"
    echo ""
    
    read -p "Proceed with download and upload? [y/N]: " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "Update cancelled by user"
        exit 0
    fi
    
    S3_OBJECT_KEY="rpm/$INSTALLER_FILENAME"
    LOCAL_FILE="$CACHE_DIR/$INSTALLER_FILENAME"
    
    # Create cache directory
    mkdir -p "$CACHE_DIR"
    
    print_status "Downloading Splunk installer: $INSTALLER_FILENAME"
    print_status "URL: $DOWNLOAD_URL"
    
    # Download with progress
    if curl -L --progress-bar -o "$LOCAL_FILE" "$DOWNLOAD_URL"; then
        print_success "Downloaded installer: $INSTALLER_FILENAME"
    else
        print_error "Failed to download installer from: $DOWNLOAD_URL"
        print_status "This may be due to the specific version not being available"
        exit 1
    fi
    
    # Validate downloaded file
    if [ ! -f "$LOCAL_FILE" ] || [ ! -s "$LOCAL_FILE" ]; then
        print_error "Downloaded file is missing or empty"
        exit 1
    fi
    
    if ! file "$LOCAL_FILE" | grep -q "RPM"; then
        print_error "Downloaded file is not a valid RPM package"
        exit 1
    fi
    
    file_size=$(wc -c < "$LOCAL_FILE")
    print_success "Download validated, size: $file_size bytes"
    
    # Upload to S3
    print_status "Uploading to S3..."
    if aws s3 cp "$LOCAL_FILE" "s3://$BUCKET_NAME/$S3_OBJECT_KEY"; then
        print_success "Uploaded to S3: s3://$BUCKET_NAME/$S3_OBJECT_KEY"
    else
        print_error "Failed to upload to S3"
        exit 1
    fi
    
    # Clean up local file
    rm -f "$LOCAL_FILE"
    
    # Update SSM parameters
    print_status "Updating SSM parameters..."
    
    S3_URL="s3://$BUCKET_NAME/$S3_OBJECT_KEY"
    
    # Create/update installer URL parameter (without tags on update)
    aws ssm put-parameter \
        --name "/splunk-s3-installer/installer-url" \
        --value "$S3_URL" \
        --type "String" \
        --overwrite
    
    # Add tags separately (works with existing parameters)
    aws ssm add-tags-to-resource \
        --resource-type "Parameter" \
        --resource-id "/splunk-s3-installer/installer-url" \
        --tags Key=ManagedBy,Value=splunk-s3-installer Key=Project,Value=$PROJECT_NAME
    
    # Create/update version parameter (without tags on update)
    aws ssm put-parameter \
        --name "/splunk-s3-installer/version" \
        --value "$LATEST_VERSION" \
        --type "String" \
        --overwrite
    
    # Add tags separately (works with existing parameters)
    aws ssm add-tags-to-resource \
        --resource-type "Parameter" \
        --resource-id "/splunk-s3-installer/version" \
        --tags Key=ManagedBy,Value=splunk-s3-installer Key=Project,Value=$PROJECT_NAME
    
    print_success "SSM parameters updated"
else
    # No update needed, but ensure SSM parameters are current
    S3_OBJECT_KEY="$CURRENT_FILE"
    S3_URL="s3://$BUCKET_NAME/$S3_OBJECT_KEY"
    
    # Check if SSM parameters exist and are correct
    current_url=$(aws ssm get-parameter --name "/splunk-s3-installer/installer-url" --query 'Parameter.Value' --output text 2>/dev/null || echo "")
    if [ "$current_url" != "$S3_URL" ]; then
        print_status "Updating SSM parameters to match current installer..."
        
        aws ssm put-parameter \
            --name "/splunk-s3-installer/installer-url" \
            --value "$S3_URL" \
            --type "String" \
            --overwrite
        
        # Add tags separately
        aws ssm add-tags-to-resource \
            --resource-type "Parameter" \
            --resource-id "/splunk-s3-installer/installer-url" \
            --tags Key=ManagedBy,Value=splunk-s3-installer Key=Project,Value=$PROJECT_NAME
        
        aws ssm put-parameter \
            --name "/splunk-s3-installer/version" \
            --value "$CURRENT_VERSION" \
            --type "String" \
            --overwrite
        
        # Add tags separately
        aws ssm add-tags-to-resource \
            --resource-type "Parameter" \
            --resource-id "/splunk-s3-installer/version" \
            --tags Key=ManagedBy,Value=splunk-s3-installer Key=Project,Value=$PROJECT_NAME
            --tags "Key=Project,Value=$PROJECT_NAME" "Key=Repository,Value=$REPOSITORY" "Key=Environment,Value=$ENVIRONMENT" "Key=Owner,Value=$OWNER" "Key=CostCenter,Value=$COST_CENTER" "Key=ManagedBy,Value=splunk-s3-installer" "Key=DeployedBy,Value=$DEPLOYED_BY"
        
        print_success "SSM parameters updated"
    fi
fi

echo ""
if [ "$NEEDS_UPDATE" = true ]; then
    print_success "Splunk installer update complete!"
    echo ""
    echo "📋 SUMMARY"
    echo "=========="
    echo "Action: Downloaded and uploaded new installer"
    echo "Version: $LATEST_VERSION (build: $BUILD_NUMBER)"
    echo "Installer: $INSTALLER_FILENAME"
    echo "S3 URL: s3://$BUCKET_NAME/$S3_OBJECT_KEY"
    echo "Bucket: $BUCKET_NAME"
else
    print_success "Splunk installer management complete!"
    echo ""
    echo "📋 SUMMARY"
    echo "=========="
    echo "Action: No update needed"
    echo "Current Version: $CURRENT_VERSION"
    echo "Installer: $CURRENT_FILE"
    echo "S3 URL: s3://$BUCKET_NAME/$S3_OBJECT_KEY"
    echo "Bucket: $BUCKET_NAME"
fi
echo ""
echo "🔗 CONSUMING PROJECTS CAN USE:"
echo "INSTALLER_URL=\$(aws ssm get-parameter --name '/splunk-s3-installer/installer-url' --query 'Parameter.Value' --output text)"
echo "aws s3 cp \"\$INSTALLER_URL\" /tmp/splunk-installer.rpm"
echo "sudo yum install -y /tmp/splunk-installer.rpm"
