# Splunk Installer Download Implementation Logic

## Download Strategy

### Source Management

The project uses the endoflife.date API to determine the latest supported Splunk version without requiring Splunk account authentication. This approach minimizes the risk of account flagging from excessive downloads while ensuring access to current version information.

### Version Detection Logic

- Query `https://endoflife.date/api/splunk.json` for current Splunk version information
- Filter for currently supported versions (not EOL) 
- Compare latest supported version with S3-hosted version using major.minor comparison only
- Ignore patch-level updates to maintain stability
- Fallback to hardcoded version (10.0.2) if API is unavailable

### Download URL Construction

Direct download URLs are constructed using known build numbers for each version:

- **Current format**: `https://download.splunk.com/products/splunk/releases/{version}/linux/splunk-{version}-{build}-linux-amd64.tgz`
- **Example**: `https://download.splunk.com/products/splunk/releases/10.0.2/linux/splunk-10.0.2-e2d18b4767e9-linux-amd64.tgz`

Known build numbers are maintained in the update script:
- 10.0.2: `e2d18b4767e9`
- Additional versions added as needed

## Implementation Requirements

### Download Process

1. **Version Check**: Query endoflife.date API for latest supported version
2. **Comparison**: Compare with current S3 version (major.minor only)
3. **User Confirmation**: Prompt user before downloading newer version
4. **Download**: Use curl with progress display to download to cache directory
5. **Validation**: Verify file exists, is not empty, and is valid gzip archive
6. **Upload**: Upload validated installer to S3 bucket
7. **Parameters**: Update SSM parameters with new installer URL and version
8. **Cleanup**: Remove local cache file after successful upload

### Download Validation

- Verify downloaded file exists and is not empty
- Check file type using `file` command to ensure it's a gzip archive
- Validate file size is reasonable (>1GB for Splunk installer)
- No checksum validation currently implemented

### Error Handling

- Graceful handling of endoflife.date API failures with fallback version
- Clear error messages for download failures with actionable guidance
- Retry logic not implemented - manual retry required
- Network timeout handling through curl default settings
- Cleanup of partial downloads on failure

### File Management

- Download to configurable cache directory (`/tmp/splunk-installer-cache` by default)
- Atomic operations - download to temp location, then upload to S3
- Clean up local files after successful S3 upload
- No resume capability for interrupted downloads

## Consumer Integration

### AWS CLI Usage Pattern

Projects consuming the S3-hosted installer use this pattern:

```bash
# Discover installer URL from SSM Parameter Store
INSTALLER_URL=$(aws ssm get-parameter --name "/splunk-s3-installer/installer-url" --query 'Parameter.Value' --output text)

# Download installer from S3 (fast, no external download)
aws s3 cp "$INSTALLER_URL" /tmp/splunk-installer.tgz

# Verify download integrity
if [ -f /tmp/splunk-installer.tgz ] && [ -s /tmp/splunk-installer.tgz ]; then
    if file /tmp/splunk-installer.tgz | grep -q "gzip compressed"; then
        echo "SUCCESS: Splunk installer downloaded and validated"
    else
        echo "ERROR: Downloaded file is not a valid gzip archive"
        exit 1
    fi
else
    echo "ERROR: Downloaded file is missing or empty"
    exit 1
fi
```

### Performance Characteristics

- **S3 to EC2 Transfer**: Optimized for same-region transfers (typically 100+ MB/s)
- **No External Dependencies**: Once in S3, no external downloads required
- **Consistent Availability**: S3 provides high availability for installer access
- **Cost Optimization**: Single download to S3, multiple fast transfers to EC2 instances

### Integration Points

- **EC2 User Data Scripts**: Can use the download pattern for instance initialization
- **Lambda Functions**: Can download installer for processing (within 15-minute timeout)
- **Local Development**: Scripts can access installer for testing
- **CI/CD Pipelines**: Can download installer for validation or deployment

## Version Management Strategy

### Target Version Selection

- **Current Target**: Splunk 10.0.2 (supported until July 2027)
- **Strategy**: Target versions with long support windows for stability
- **Update Trigger**: Only update when current version approaches EOL
- **Manual Control**: User confirmation required for all version changes

### Build Number Management

Build numbers are maintained in the update script and must be updated when new versions are targeted:

```bash
get_build_number() {
    local version="$1"
    case "$version" in
        "10.0.2") echo "e2d18b4767e9" ;;
        "10.0.1") echo "c7126eee4e6b" ;;
        # Add new versions as needed
        *) echo "" ;;
    esac
}
```

### Update Process

1. **Automated Detection**: Script checks endoflife.date API for newer supported versions
2. **User Notification**: Display current vs. available version with support status
3. **Manual Confirmation**: User must explicitly approve version updates
4. **Atomic Update**: Download, validate, upload, and update parameters in sequence
5. **Rollback Capability**: Previous version remains in S3 until overwritten

## Logging and Monitoring

### Operation Logging

- All operations logged to stdout with colored status indicators
- Download progress displayed using curl's built-in progress bar
- File size and validation results logged for troubleshooting
- SSM parameter updates logged with success/failure status

### Resource Tracking

- S3 bucket and objects tracked through management tags
- SSM parameters tracked through management tags
- Resource listing available through `list-deployed-resources.sh` script
- No automated monitoring or alerting configured

### Error Reporting

- Structured error messages with clear descriptions
- Actionable guidance provided for common failure scenarios
- No integration with external monitoring systems
- Manual troubleshooting required for failures
