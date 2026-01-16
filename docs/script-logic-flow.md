# Script Logic Flow Documentation

## Overview

This document outlines the logical flow and dependencies for the Splunk S3 Installer management scripts, ensuring consistent implementation and troubleshooting.

## Authentication Model

### Local AWS Credentials

- **Primary Authentication**: Uses local AWS credentials (AWS CLI profile or environment variables)
- **No OIDC/Role Assumption**: Direct use of configured AWS credentials
- **Account Detection**: `aws sts get-caller-identity` used to determine account ID for resource naming
- **Fallback Strategy**: No fallback - requires valid AWS credentials to operate

### Credential Requirements

- AWS CLI configured with valid credentials
- Permissions required:
  - S3: CreateBucket, PutObject, GetObject, ListBucket, PutBucketPolicy, PutBucketTagging
  - SSM: PutParameter, GetParameter, AddTagsToResource, ListTagsForResource
  - STS: GetCallerIdentity

## Script Dependencies

### Configuration Management

- **config.env**: Source of truth for static configuration values
  - AWS_REGION: Target AWS region (default: us-east-1)
  - OWNER, COST_CENTER, ENVIRONMENT: Resource tagging values
  - CACHE_DIR: Local temporary directory for downloads
  - DOWNLOADS_DIR: Directory for manual installer downloads (unused in current implementation)
- **Independent sourcing**: Each script sources config.env directly
- **No parameter passing**: Scripts are self-contained with direct configuration access

### Script Call Chain

```
deploy.sh
├── verify-prerequisites.sh (validates tools and credentials)
└── update-splunk-installer.sh (creates bucket, downloads installer, updates parameters)

update-splunk-installer.sh (standalone)
├── verify-prerequisites.sh (validates environment)
├── endoflife.date API call (version detection)
├── S3 operations (bucket creation, file upload)
└── SSM parameter updates (with tagging)

destroy.sh (standalone)
├── config.env sourcing
├── S3 bucket cleanup (by management tags)
├── SSM parameter cleanup (by name)
└── local cache cleanup

list-deployed-resources.sh (standalone)
├── config.env sourcing
├── S3 resource enumeration (by management tags)
├── SSM parameter enumeration (by management tags)
└── installer metadata display
```

## Core Logic Flow

### Version Detection Process

1. **API Query**: Call `https://endoflife.date/api/splunk.json`
2. **Response Parsing**: Extract latest supported version using jq
3. **Version Comparison**: Compare major.minor with current S3 version
4. **User Confirmation**: Prompt before downloading newer version
5. **Fallback**: Use hardcoded version (10.0.2) if API fails

### Download and Upload Process

1. **Build Number Lookup**: Get known build number for target version
2. **URL Construction**: Build download URL using version and build number
3. **Local Download**: Download to cache directory with progress display
4. **Validation**: Verify file exists, not empty, and is gzip archive
5. **S3 Upload**: Upload validated file to S3 bucket
6. **Parameter Updates**: Update SSM parameters with new URL and version
7. **Tagging**: Apply management tags to SSM parameters
8. **Cleanup**: Remove local cache file

### Resource Management

1. **Bucket Creation**: Create S3 bucket with encryption and public access blocking
2. **Policy Application**: Apply account-wide access policy
3. **Tagging**: Apply management tags for resource tracking
4. **Parameter Creation**: Create SSM parameters for service discovery
5. **Tag Application**: Apply management tags to parameters for cleanup tracking

## Error Handling Strategy

### API Failures

- **endoflife.date unavailable**: Fall back to hardcoded version (10.0.2)
- **Invalid JSON response**: Log warning and use fallback version
- **Network timeouts**: No retry logic - manual re-execution required

### Download Failures

- **URL not found**: Clear error message with version/build information
- **Network issues**: Curl error messages passed through to user
- **Validation failures**: Specific error for file type or size issues
- **S3 upload failures**: AWS CLI error messages displayed

### Resource Conflicts

- **Bucket exists**: Continue with existing bucket (idempotent operation)
- **Parameter exists**: Overwrite with new values (update operation)
- **Tag conflicts**: Add tags separately to avoid API limitations

## Operational Patterns

### Idempotent Operations

- **Bucket creation**: Safe to run multiple times
- **Parameter updates**: Overwrite existing values
- **Tag application**: Add/update tags without conflicts
- **File uploads**: Overwrite existing installer files

### Manual Confirmation Points

- **Version updates**: User must confirm before downloading newer version
- **Destruction**: User must type 'DESTROY' to confirm resource deletion
- **No automated updates**: All version changes require explicit user approval

### Resource Cleanup

- **Management tags**: All resources tagged with `ManagedBy=splunk-s3-installer`
- **Tag-based cleanup**: Destroy script uses tags to identify managed resources
- **Complete cleanup**: Removes S3 objects, buckets, SSM parameters, and local cache
- **Force mode**: `--force` flag bypasses confirmation prompts

## Troubleshooting Guide

### Common Issues

1. **Prerequisites failure**: Check AWS CLI installation and credentials
2. **API timeout**: Retry operation or check network connectivity
3. **Download failure**: Verify version/build number combination exists
4. **Upload failure**: Check S3 permissions and bucket accessibility
5. **Parameter creation failure**: Verify SSM permissions

### Diagnostic Commands

```bash
# Check AWS credentials
aws sts get-caller-identity

# Verify S3 access
aws s3 ls

# Check SSM permissions
aws ssm get-parameters --names '/test'

# Test endoflife.date API
curl -s "https://endoflife.date/api/splunk.json" | jq '.[0]'

# Verify installer URL
curl -I "https://download.splunk.com/products/splunk/releases/10.0.2/linux/splunk-10.0.2-e2d18b4767e9.x86_64.rpm"
```

### Recovery Procedures

1. **Partial deployment**: Run `destroy.sh --force` then `deploy.sh`
2. **Corrupted parameters**: Delete manually then re-run update script
3. **Missing tags**: Use `list-deployed-resources.sh` to identify untagged resources
4. **Cache issues**: Clear `/tmp/splunk-installer-cache` directory manually
