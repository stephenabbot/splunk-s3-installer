# Splunk S3 Installer Management - Functional Requirements

## Project Purpose

This project deploys and manages S3-hosted Splunk Enterprise installer images to enable fast deployment of ephemeral Splunk instances. The project maintains a dedicated S3 bucket containing the latest Splunk installer, eliminating slow downloads during EC2 instance provisioning.

## Core Functional Requirements

### S3 Bucket Management

- Deploy dedicated S3 bucket for Splunk installer storage
- Configure bucket with encryption and public access blocking
- Account-wide access policy for EC2 instances and other AWS services
- Provide bucket cleanup and destruction capabilities

### Splunk Installer Management

- Download latest supported Splunk Enterprise installer from official sources
- Use endoflife.date API to determine latest supported version without Splunk login
- Target stable versions with long support windows (currently 10.0.2 until July 2027)
- Validate installer integrity using file type detection
- Upload installer to S3 bucket with appropriate metadata
- Compare major.minor versions to detect when updates are needed
- Manual confirmation required before replacing existing installer

### Authentication and Access Control

- Use local AWS credentials for deployment and management
- Account-wide S3 bucket access policy allowing any resource in the AWS account
- Secure S3 bucket access with public access blocking enabled
- No external authentication dependencies

### Service Discovery and Publishing

- Publish S3 installer URL to SSM Parameter Store at `/splunk-s3-installer/installer-url`
- Publish installer version to SSM Parameter Store at `/splunk-s3-installer/version`
- Enable service discovery through standardized SSM parameter paths
- Support consuming projects discovering installer location automatically

### Operational Scripts

- **verify-prerequisites**: Validate required tools, credentials, and dependencies
- **deploy**: Deploy S3 bucket and download latest installer with user confirmation
- **update-splunk-installer**: Check for updates using endoflife.date API and update with confirmation
- **destroy**: Clean up all resources including S3 bucket and SSM parameters (supports --force flag)
- **list-deployed-resources**: Display current infrastructure status and installer information

### Version Management Strategy

- Use endoflife.date API for version detection without Splunk account access
- Target latest supported versions with long-term support windows
- Compare major.minor versions only (ignore patch updates)
- Known build numbers maintained in script for reliable downloads
- Manual confirmation required before version updates to prevent unwanted changes

## Installer Download Logic

### Source Management

- Use endoflife.date JSON API to determine latest supported Splunk version
- Construct download URLs using known build numbers for each version
- Direct download from Splunk's official CDN without authentication required
- Fallback to hardcoded version (10.0.2) if API unavailable

### Version Detection

- Query `https://endoflife.date/api/splunk.json` for version information
- Filter for currently supported versions (not EOL)
- Compare with S3-hosted version using major.minor comparison
- User confirmation required before downloading newer versions

### Download Process

- Download to local cache directory using curl with progress display
- Validate downloaded file is not empty and is valid gzip archive
- Upload validated installer to S3 bucket
- Update SSM parameters with new installer URL and version
- Clean up local cache files after successful upload

## Integration Requirements

### Consuming Project Support

- Provide standardized S3 URL format through SSM Parameter Store
- Support secure access from EC2 instances in same account
- Enable fast transfer to EC2 instances during provisioning
- Maintain compatibility with existing deployment patterns

### Usage Pattern

```bash
# Get installer URL from Parameter Store
INSTALLER_URL=$(aws ssm get-parameter --name '/splunk-s3-installer/installer-url' --query 'Parameter.Value' --output text)

# Download installer from S3 (fast, no external download)
aws s3 cp "$INSTALLER_URL" /tmp/splunk-installer.tgz

# Verify download integrity
file /tmp/splunk-installer.tgz
```

### Error Handling

- Graceful handling of API failures with fallback versions
- Retry mechanisms for transient download errors
- Clear error reporting with actionable guidance
- Manual confirmation prevents unwanted automated changes

## Configuration Management

### Environment Configuration

- Static configuration in `config.env` file
- Support for AWS region, credentials, and resource tagging
- Configurable cache directory for temporary downloads
- No sensitive data stored in configuration

### Parameter Management

- Use SSM Parameter Store for service discovery
- Automatic tagging of managed resources for identification
- Support for resource cleanup based on management tags
- Backward compatibility with existing parameter structure

## Security Requirements

### Data Protection

- Encrypt installers at rest in S3 using AES256
- Secure data in transit during all operations
- Block all public access to S3 bucket
- Account-wide access policy for authorized AWS resources only

### Access Control

- Restrict S3 bucket access to account resources only
- No cross-account access supported
- Principle of least privilege for resource access
- Management tags for resource identification and cleanup

## Maintenance and Operations

### Manual Operations

- Manual script execution for all operations
- User confirmation required for installer updates
- Support for force operations when needed (destroy --force)
- Troubleshooting tools and diagnostic capabilities

### Monitoring Integration

- Resource listing and status reporting through list-deployed-resources script
- Cost monitoring through S3 storage metrics
- No automated monitoring or alerting configured
- Manual verification of deployment status
- Enable service discovery through standardized SSM parameter paths
- Support consuming projects discovering installer location automatically

### GitHub Actions Integration

- Bootstrap script publishes GitHub project variables for OIDC authentication
- Support automated deployment through GitHub Actions using OIDC connection
- Enable GitHub Actions to dynamically build OIDC connection string
- Integrate with foundation OIDC provider for secure CI/CD authentication

### Operational Scripts

- verify-prerequisites: Validate required tools, credentials, and dependencies
- deploy: Deploy S3 bucket, download installer, configure access policies
- destroy: Clean up all resources including S3 bucket and stored installers
- list-deployed-resources: Display current infrastructure status and installer information

### Deployment Lifecycle Support

- Local development and testing using script execution
- GitHub Actions integration for automated deployment
- Lambda function capability for maintenance operations under 15-minute execution limit
- Idempotent operations supporting multiple executions

## Installer Download Logic

### Source Management

- Use existing download logic from ephemeral Splunk project user data script
- Support multiple download methods with fallback strategies
- Handle download failures gracefully with retry mechanisms
- Validate download completeness and integrity

### Version Detection

- Determine latest available Splunk Enterprise version
- Compare with currently stored version in S3
- Trigger updates when newer versions detected
- Support manual version override capabilities

### Storage Optimization

- Implement S3 storage class transitions for cost optimization
- Move installers to Infrequent Access after specified period
- Support retrieval from different storage classes as needed
- Clean up obsolete installer versions

## Integration Requirements

### Consuming Project Support

- Provide standardized S3 URL format for consuming projects
- Support secure access from EC2 instances in same account
- Enable fast transfer to EC2 instances during provisioning
- Maintain compatibility with existing deployment patterns

### Monitoring and Maintenance

- Support scheduled maintenance operations
- Provide installer freshness validation
- Enable manual and automated update triggers
- Log all operations for audit and troubleshooting

### Error Handling

- Graceful handling of download failures
- Retry mechanisms for transient errors
- Clear error reporting with actionable guidance
- Rollback capabilities for failed updates

## Configuration Management

### Environment Configuration

- Support multiple deployment environments
- Environment-specific S3 bucket naming
- Configurable update schedules and policies
- Flexible authentication method selection

### Parameter Management

- Use configuration files for deployment settings
- Support environment variable overrides
- Maintain backward compatibility with existing patterns
- Secure handling of sensitive configuration data

## Performance Requirements

### Download Performance

- Optimize installer download from official sources
- Support parallel downloads when beneficial
- Implement download progress reporting
- Handle large file transfers efficiently

### Lambda Execution Constraints

- Complete all operations within 15-minute Lambda timeout
- Optimize for cold start performance
- Minimize memory usage during operations
- Support incremental processing when needed

### S3 Transfer Performance

- Enable fast transfer from S3 to EC2 instances
- Optimize S3 bucket configuration for transfer speed
- Support regional optimization for reduced latency
- Implement transfer acceleration when beneficial

## Security Requirements

### Data Protection

- Encrypt installers at rest in S3
- Secure data in transit during all operations
- Implement access logging for audit trails
- Protect against unauthorized access

### Access Control

- Restrict S3 bucket access to authorized services only
- Implement time-limited access tokens when possible
- Support cross-account access for consuming projects
- Maintain principle of least privilege

### Compliance

- Support audit requirements for installer management
- Maintain change logs for all installer updates
- Provide access history and usage tracking
- Enable compliance reporting capabilities

## Maintenance and Operations

### Automated Maintenance

- Support scheduled installer updates
- Automated cleanup of obsolete versions
- Health checks for S3 bucket and stored installers
- Notification capabilities for maintenance events

### Manual Operations

- Support manual installer updates and rollbacks
- Emergency procedures for rapid deployment
- Troubleshooting tools and diagnostic capabilities
- Manual override capabilities for automated processes

### Monitoring Integration

- CloudWatch integration for operational metrics
- Cost monitoring and alerting capabilities
- Performance monitoring for download and transfer operations
- Integration with existing monitoring infrastructure
