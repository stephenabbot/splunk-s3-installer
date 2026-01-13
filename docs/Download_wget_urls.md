# Splunk Download wget Commands

## Official Download Page

<https://www.splunk.com/en_us/download/splunk-enterprise.html>

## Working wget Commands

### Splunk 10.0.2 (Current)
```bash
wget -O splunk-10.0.2-e2d18b4767e9-linux-amd64.tgz "https://download.splunk.com/products/splunk/releases/10.0.2/linux/splunk-10.0.2-e2d18b4767e9-linux-amd64.tgz"
```

**Build Number**: `e2d18b4767e9`  
**File Size**: ~1.7GB  
**Verified Working**: 2026-01-13

## URL Pattern

```
https://download.splunk.com/products/splunk/releases/{version}/linux/splunk-{version}-{build}-linux-amd64.tgz
```

**Requirements**:
- Exact version number (e.g., `10.0.2`)
- Correct build number for that version
- Use `linux-amd64.tgz` format (not `Linux-x86_64.tgz`)

## Notes

- No authentication required for direct downloads
- Build numbers are version-specific and must be discovered manually
- URLs can be tested with `curl -I` before downloading
