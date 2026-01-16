# Splunk Download URL Analysis

## Current State (2026)

### Authentication Requirements - RESOLVED

**Key Discovery**: Direct downloads work without authentication when using correct URL patterns and build numbers.

### Working URL Pattern

```
https://download.splunk.com/products/splunk/releases/{version}/linux/splunk-{version}-{build}.x86_64.rpm
```

**Example (Verified Working)**:
```
https://download.splunk.com/products/splunk/releases/10.0.2/linux/splunk-10.0.2-e2d18b4767e9.x86_64.rpm
```

### Critical Requirements

1. **Exact build number required**: Cannot use "latest" or generic patterns
2. **Correct filename format**: Must use `.x86_64.rpm` for Amazon Linux 2 / RHEL-based systems
3. **Valid version/build combination**: Build numbers are specific to each version

## Version and Build Number Discovery

### Version Detection Strategy

**Primary Method**: endoflife.date API
- URL: `https://endoflife.date/api/splunk.json`
- Returns JSON with version info, EOL dates, and latest patch versions
- No authentication required
- Reliable and maintained by third party

**API Response Structure**:
```json
[
  {
    "cycle": "10.0",
    "releaseDate": "2025-07-28",
    "eol": "2027-07-28",
    "latest": "10.0.2",
    "latestReleaseDate": "2025-11-14",
    "lts": false
  }
]
```

### Build Number Management

**Current Known Build Numbers**:
- 10.0.2: `e2d18b4767e9`
- 10.0.1: `c7126eee4e6b` (placeholder)

**Discovery Method**:
1. Log into Splunk.com (manual, one-time)
2. Navigate to download page for target version
3. Copy wget command provided by Splunk
4. Extract build number from filename
5. Add to script's build number lookup function

**Build Number Pattern**: 12-character hexadecimal string (e.g., `e2d18b4767e9`)

## Implementation Strategy

### Successful Approach

1. **Version Detection**: Use endoflife.date API to find latest supported version
2. **Build Lookup**: Maintain known build numbers in script
3. **URL Construction**: Build download URL using version + build number
4. **Direct Download**: Use curl with progress display
5. **Validation**: Verify file type and size after download

### Risk Mitigation

- **Single download per version**: Minimizes risk of account flagging
- **Long-term version targeting**: Use versions with 2+ year support windows
- **Manual confirmation**: User approval required before version updates
- **Fallback version**: Hardcoded known-good version if API fails

## URL Pattern Evolution

### Historical Patterns (No longer work)

```bash
# These patterns are obsolete:
https://download.splunk.com/products/splunk/releases/latest/linux/splunk-latest-Linux-x86_64.tgz
https://download.splunk.com/products/splunk/releases/{version}/linux/splunk-{version}-{build}-Linux-x86_64.tgz
https://download.splunk.com/products/splunk/releases/{version}/linux/splunk-{version}-{build}-linux-amd64.tgz
```

### Current Working Pattern

```bash
# This pattern works without authentication:
https://download.splunk.com/products/splunk/releases/{version}/linux/splunk-{version}-{build}.x86_64.rpm
```

**Key Changes**:
- Using RPM format for Amazon Linux 2 / RHEL-based systems
- Build number is mandatory
- No "latest" URL available

## Testing and Validation

### URL Validation Method

```bash
# Test URL accessibility without downloading
curl -I "https://download.splunk.com/products/splunk/releases/10.0.2/linux/splunk-10.0.2-e2d18b4767e9.x86_64.rpm"

# Expected response:
# HTTP/2 200 
# content-type: binary/octet-stream
# content-length: 1717935022
```

### File Validation

```bash
# Verify downloaded file
file splunk-10.0.2-e2d18b4767e9.x86_64.rpm
# Expected: RPM package

# Check file size (should be >1GB)
ls -lh splunk-10.0.2-e2d18b4767e9.x86_64.rpm
```

## Architecture Compatibility

### File Format Compatibility

- **x86_64** RPM format for RHEL-based systems
- Compatible with Amazon Linux 2, CentOS, RHEL, Fedora
- Native package management integration with yum/dnf
- Works on all current EC2 instance types (t3, m5, c5, r5, etc.)

### Platform Support

- **EC2 Instances**: All x86_64 instance types supported
- **Operating Systems**: Amazon Linux 2, CentOS, RHEL, Fedora (RHEL-based distributions)
- **Package Management**: Native yum/dnf integration
- **Container Platforms**: Docker, Kubernetes, ECS (with RPM-based base images)

## Operational Considerations

### Download Performance

- **File Size**: ~1.7GB for Splunk 10.0.2
- **Download Speed**: Varies by location and network (typically 20-50 MB/s)
- **Progress Display**: curl provides real-time progress with `--progress-bar`
- **Resume Capability**: Not implemented (would require additional logic)

### Storage and Transfer

- **S3 Storage**: ~$0.04/month for 1.7GB in Standard storage class
- **S3 Transfer**: Fast within same AWS region (100+ MB/s to EC2)
- **Cross-Region**: Additional data transfer charges apply
- **Lifecycle**: No automatic lifecycle policies implemented

### Maintenance Requirements

- **Build Number Updates**: Required when targeting new versions
- **API Monitoring**: endoflife.date API dependency
- **Version Strategy**: Balance between stability and security updates
- **Manual Oversight**: All version changes require user confirmation

## Future Considerations

### Potential Issues

1. **Build Number Changes**: Splunk may change build numbering scheme
2. **URL Pattern Changes**: Download URL structure may evolve
3. **Authentication Requirements**: Splunk may require authentication in future
4. **API Dependencies**: endoflife.date API availability

### Mitigation Strategies

1. **Multiple Build Numbers**: Maintain build numbers for multiple versions
2. **Fallback Versions**: Always have known-working version as fallback
3. **Manual Override**: Support for manual version/build specification
4. **Alternative APIs**: Consider additional version detection sources
