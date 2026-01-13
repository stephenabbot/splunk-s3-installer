#!/bin/bash
# scripts/deploy.sh - Deploy Splunk installer infrastructure and download latest installer

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

echo "🚀 DEPLOY SPLUNK INSTALLER INFRASTRUCTURE"
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

print_success "Prerequisites verified"
echo ""

# Run the update script which will create bucket and download installer
print_status "Creating infrastructure and downloading latest Splunk installer..."
if ./scripts/update-splunk-installer.sh; then
    print_success "Deployment complete!"
    echo ""
    print_status "Verifying deployment..."
    ./scripts/list-deployed-resources.sh
else
    print_error "Deployment failed"
    exit 1
fi
