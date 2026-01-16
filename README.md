# Splunk S3 Installer Management

https://github.com/stephenabbot/splunk-s3-installer.git

## Problem This Project Solves

**Slow Splunk Deployments**: Downloading Splunk Enterprise installers directly from Splunk's servers during EC2 instance provisioning is slow (often 5-15 minutes for 1.7GB), unreliable, and risks account flagging from excessive downloads. This creates bottlenecks in automated deployments and ephemeral Splunk instance creation.

**Version Management Complexity**: Determining the latest supported Splunk version requires either logging into Splunk.com or maintaining manual version tracking, making automated infrastructure deployments difficult to keep current.

**Account Security Risks**: Frequent downloads from Splunk's servers for testing and deployment can trigger account restrictions, disrupting development workflows.

## How This Project Solves The Problem

**Fast S3-Hosted Distribution**: Downloads the Splunk installer once to a dedicated S3 bucket, enabling fast (100+ MB/s) transfers to EC2 instances within the same AWS region. This reduces deployment time from minutes to seconds.

**Automated Version Detection**: Uses the endoflife.date API to detect the latest supported Splunk versions without requiring Splunk account authentication, enabling automated version awareness while avoiding account access risks.

**Service Discovery**: Publishes the S3 installer location to AWS Systems Manager Parameter Store, allowing consuming projects to dynamically discover and download the installer without hardcoded URLs.

**Risk Mitigation**: Downloads each version only once, stores it persistently in S3, and targets stable versions with long support windows (currently Splunk 10.0.2 until July 2027) to minimize both download frequency and version churn.

## Resources Created and Managed

### AWS S3 Resources

- **S3 Bucket**: `splunk-installer-{account-id}-{region}`
  - Encryption: AES256 server-side encryption
  - Public Access: Completely blocked
  - Access Policy: Account-wide access for any AWS resource in the account
  - Management Tags: `ManagedBy=splunk-s3-installer` for automated cleanup

- **Splunk Installer Object**: `rpm/splunk-{version}-{build}.x86_64.rpm`
  - Current: `rpm/splunk-10.0.2-e2d18b4767e9.x86_64.rpm` (~1.7GB)
  - Storage Class: Standard (no lifecycle policies implemented)
  - Format: RPM package for Amazon Linux 2 / RHEL-based systems

### AWS Systems Manager Parameters

- **`/splunk-s3-installer/installer-url`**: Complete S3 URL for the installer
  - Value: `s3://splunk-installer-{account-id}-{region}/rpm/splunk-{version}-{build}.x86_64.rpm`
  - Type: String
  - Management Tags: `ManagedBy=splunk-s3-installer`

- **`/splunk-s3-installer/version`**: Current installer version
  - Value: `10.0.2`
  - Type: String  
  - Management Tags: `ManagedBy=splunk-s3-installer`

### Local Resources

- **Cache Directory**: `/tmp/splunk-installer-cache`
  - Temporary storage during download and upload process
  - Automatically cleaned up after successful operations

## Implementation Reasoning and Architecture

### Design Philosophy

**Simplicity Over Complexity**: The solution uses bash scripts and AWS CLI rather than complex infrastructure-as-code frameworks. This approach provides transparency, easy troubleshooting, and minimal dependencies while solving the core problem effectively.

**Manual Control Over Automation**: All version updates require explicit user confirmation rather than automatic updates. This prevents unexpected version changes in production environments while still providing automated version detection.

**Account-Wide Access**: The S3 bucket policy allows any resource in the AWS account to access the installer, providing maximum flexibility for consuming projects without complex IAM role management.

### Version Management Strategy

**Long-Term Stability Focus**: Targets versions with extended support windows (2+ years) rather than always-latest versions. This reduces maintenance overhead and provides stability for production deployments.

**API-Based Detection**: Uses endoflife.date API instead of scraping Splunk's website or requiring authentication. This provides reliable version information without account access risks.

**Known Build Numbers**: Maintains a lookup table of version-to-build-number mappings in the script. Build numbers must be discovered manually from Splunk's download page but enable reliable direct downloads without authentication.

### Download Implementation

**Direct Download Strategy**: Constructs download URLs using the pattern:
```
https://download.splunk.com/products/splunk/releases/{version}/linux/splunk-{version}-{build}.x86_64.rpm
```

This approach bypasses authentication requirements while ensuring reliable access to specific versions.

**Progressive Validation**: Downloads to local cache, validates file integrity (existence, size, gzip format), uploads to S3, updates parameters, then cleans up. Each step is verified before proceeding to the next.

**Error Handling**: Provides clear error messages with actionable guidance. Falls back to known-good versions if API calls fail. No automatic retry logic - manual re-execution required for transient failures.

### Resource Management

**Tag-Based Management**: All AWS resources receive `ManagedBy=splunk-s3-installer` tags, enabling automated discovery and cleanup. The destroy script uses these tags to identify and remove all managed resources.

**Idempotent Operations**: All scripts can be run multiple times safely. Bucket creation, parameter updates, and file uploads are designed to handle existing resources gracefully.

**Separate Tagging**: AWS SSM parameters don't support tags during creation with overwrite, so tags are applied in separate API calls after parameter creation/updates.

## Project Structure

### Core Scripts

- **`scripts/deploy.sh`** - Initial deployment script that creates infrastructure and downloads the latest installer
- **`scripts/update-splunk-installer.sh`** - Main management script that checks for updates and manages the installer
- **`scripts/destroy.sh`** - Cleanup script that removes all managed resources (supports `--force` flag)
- **`scripts/verify-prerequisites.sh`** - Validates required tools and AWS credentials
- **`scripts/list-deployed-resources.sh`** - Shows current deployment status and resource information

### Configuration

- **`config.env`** - Static configuration values (AWS region, resource tags, cache directory)

### Documentation

- **`functional-requirements.md`** - Detailed functional requirements and specifications
- **`download-implementation.md`** - Technical implementation details for the download process
- **`docs/script-logic-flow.md`** - Script dependencies, error handling, and troubleshooting guide
- **`docs/splunk-download-url-analysis.md`** - Analysis of Splunk download URL patterns and authentication
- **`docs/Download_wget_urls.md`** - Working wget commands and URL patterns

### AI Setup Documentation

- **`ai_setup/`** - Directory containing AI agent protocols and communication standards for project maintenance

## Usage Examples

### Initial Deployment

```bash
# Deploy infrastructure and download latest installer
./scripts/deploy.sh
```

### Check for Updates

```bash
# Check for newer versions and update if available
./scripts/update-splunk-installer.sh
```

### Consumer Usage (EC2 Instances)

```bash
# Get installer URL from Parameter Store
INSTALLER_URL=$(aws ssm get-parameter --name '/splunk-s3-installer/installer-url' --query 'Parameter.Value' --output text)

# Download installer from S3 (fast, no external download)
aws s3 cp "$INSTALLER_URL" /tmp/splunk-installer.rpm

# Install Splunk using yum
sudo yum install -y /tmp/splunk-installer.rpm

# Start Splunk
sudo systemctl start splunk
```

### Resource Cleanup

```bash
# Interactive cleanup with confirmation
./scripts/destroy.sh

# Automated cleanup (for scripts)
./scripts/destroy.sh --force
```

### Status Checking

```bash
# Show all deployed resources and current status
./scripts/list-deployed-resources.sh
```

## Technical Requirements

### Prerequisites

- AWS CLI configured with valid credentials
- Required tools: `curl`, `jq`, `file`
- AWS permissions: S3 (bucket management, object operations), SSM (parameter management), STS (identity)

### AWS Permissions Required

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:CreateBucket",
        "s3:PutObject",
        "s3:GetObject", 
        "s3:ListBucket",
        "s3:DeleteObject",
        "s3:DeleteBucket",
        "s3:PutBucketPolicy",
        "s3:PutBucketTagging",
        "s3:PutBucketEncryption",
        "s3:PutPublicAccessBlock"
      ],
      "Resource": [
        "arn:aws:s3:::splunk-installer-*",
        "arn:aws:s3:::splunk-installer-*/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "ssm:PutParameter",
        "ssm:GetParameter",
        "ssm:DeleteParameter",
        "ssm:AddTagsToResource",
        "ssm:ListTagsForResource"
      ],
      "Resource": "arn:aws:ssm:*:*:parameter/splunk-s3-installer/*"
    },
    {
      "Effect": "Allow",
      "Action": "sts:GetCallerIdentity",
      "Resource": "*"
    }
  ]
}
```

## Operational Considerations

### Cost Optimization

- **S3 Storage**: ~$0.04/month for 1.7GB Splunk installer
- **Data Transfer**: Free within same AWS region to EC2 instances
- **API Calls**: Minimal SSM and S3 API usage

### Security

- **No Public Access**: S3 bucket blocks all public access
- **Account Scoped**: Access limited to resources within the same AWS account
- **No Cross-Account Access**: Not designed for sharing across AWS accounts
- **Encrypted Storage**: All data encrypted at rest using AES256

### Maintenance

- **Version Updates**: Manual confirmation required for all version changes
- **Long Support Windows**: Current target (10.0.2) supported until July 2027
- **API Dependencies**: Relies on endoflife.date API availability
- **Build Number Updates**: Requires manual discovery when targeting new versions

## Troubleshooting

### Common Issues

1. **Prerequisites Failure**: Run `./scripts/verify-prerequisites.sh` to check tools and credentials
2. **API Timeout**: Check network connectivity to endoflife.date
3. **Download Failure**: Verify version/build number combination exists at Splunk
4. **Permission Errors**: Ensure AWS credentials have required S3 and SSM permissions

### Recovery Procedures

1. **Partial Deployment**: Run `./scripts/destroy.sh --force` then `./scripts/deploy.sh`
2. **Parameter Issues**: Delete parameters manually then re-run update script
3. **Cache Problems**: Clear `/tmp/splunk-installer-cache` directory manually

### Support Resources

- **Script Logic Flow**: See `docs/script-logic-flow.md` for detailed troubleshooting
- **URL Analysis**: See `docs/splunk-download-url-analysis.md` for download issues
- **Resource Status**: Use `./scripts/list-deployed-resources.sh` for current state

---

*This project provides a reliable, fast, and secure method for distributing Splunk Enterprise installers within AWS environments while minimizing external dependencies and account access risks.*
