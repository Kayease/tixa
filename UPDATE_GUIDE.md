# TIXA Update Command - User Guide

## Overview

The `tixa update` command safely updates your running media processing services with new features and dependencies without affecting ongoing functionality.

## What Gets Updated

When you run `tixa update`, the following components are updated:

✅ **main.py** - Updated with new audio support features  
✅ **Python dependencies** - Installs numpy and matplotlib for audio processing  
✅ **Service configuration** - Maintains existing settings (API key, domain, port)  
✅ **Automatic backup** - Creates backup before updating  
✅ **Health verification** - Confirms service works after update  

## Usage

### Update a Single Service

```bash
# Interactive mode (prompts for service name)
tixa update

# Direct mode (specify service name)
tixa update kayease
tixa update bazarxpress
tixa update bazarxpressdemo
```

### Update All Services

```bash
# With confirmation prompt
tixa update --all

# Skip confirmation (auto-yes)
tixa update --all --yes
tixa update --all -y
```

### Advanced Options

```bash
# Skip backup creation (faster, but not recommended)
tixa update kayease --skip-backup

# Update all services without confirmation or backup (fastest)
tixa update --all --yes --skip-backup
```

## Step-by-Step Process

For each service, the update command performs these steps:

### 1. **Backup Creation** (5 seconds)
```
✓ Creates full backup of service directory
✓ Saved to: /var/backups/tixa-updates/
✓ Format: {service}-{timestamp}.tar.gz
```

### 2. **Dependency Installation** (10-15 seconds)
```
✓ Activates service virtual environment
✓ Installs numpy>=1.24.0
✓ Installs matplotlib>=3.7.0
✓ Upgrades pip if needed
```

### 3. **Code Deployment** (2 seconds)
```
✓ Backs up current main.py
✓ Deploys new main.py with audio support
✓ Preserves API key, domain, and port settings
```

### 4. **Syntax Verification** (1 second)
```
✓ Validates Python syntax
✓ Auto-rollback if syntax errors detected
```

### 5. **Service Restart** (1-2 seconds)
```
⚡ Brief downtime: 1-2 seconds
✓ Graceful restart of systemd service
✓ Auto-rollback if service fails to start
```

### 6. **Health Check** (2 seconds)
```
✓ Verifies service is running
✓ Confirms audio support is active
✓ Tests health endpoint
```

**Total time per service: ~20-25 seconds**  
**Downtime per service: 1-2 seconds**

## Example: Update All Your Services

```bash
# You have 3 services running:
# - kayease (img.kayease.com:12515)
# - bazarxpress (img.bazarxpress.in:18311)
# - bazarxpressdemo (img.bazarxpress.kayease.com:13473)

# Run update command
tixa update --all

# Output:
🔄 TIXA · UPDATE SERVICES

Services to update: 3

  • kayease (img.kayease.com:12515)
  • bazarxpress (img.bazarxpress.in:18311)
  • bazarxpressdemo (img.bazarxpress.kayease.com:13473)

This will update 3 service(s) with:
  • New audio support (10 formats)
  • Updated dependencies (numpy, matplotlib)
  • Enhanced main.py with audio endpoints

Downtime per service: ~1-2 seconds (during restart)

Continue? (yes/no): yes

▶ Running pre-update checks...
✓ FFmpeg already installed
✓ Pre-update checks passed

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Updating service: kayease
─────────────────────────────────────────────────────
▶ Creating backup...
✓ Backup created: /var/backups/tixa-updates/kayease-20260127-121500.tar.gz
▶ Installing new dependencies...
✓ Dependencies updated
✓ Current main.py backed up
▶ Deploying updated main.py...
✓ New main.py deployed
▶ Verifying Python syntax...
✓ Syntax check passed
▶ Restarting service (1-2 sec downtime)...
✓ Service restarted successfully
▶ Verifying health endpoint...
✓ Audio support verified ✨

✓ Service 'kayease' updated successfully!

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[... repeats for bazarxpress and bazarxpressdemo ...]

📊 UPDATE SUMMARY
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Total services: 3
Updated: 3
Failed: 0

✨ New features available:
  • Audio file support (MP3, WAV, FLAC, AAC, OGG, M4A, WMA, OPUS, AIFF)
  • Waveform generation endpoint
  • Audio streaming endpoint
  • Format conversion endpoint

📚 Test your services:
  • https://img.kayease.com/health
  • https://img.bazarxpress.in/health
  • https://img.bazarxpress.kayease.com/health

💾 Backups saved to: /var/backups/tixa-updates

🎉 All services updated successfully!
```

## Safety Features

### Automatic Backup
- Full service backup before any changes
- Stored in `/var/backups/tixa-updates/`
- Named with timestamp for easy identification
- Can be used for manual rollback if needed

### Automatic Rollback
The update script automatically rolls back if:
- Python syntax errors detected
- Service fails to start
- Health check fails

### Zero Breaking Changes
- All existing endpoints continue working
- API keys remain unchanged
- Domains and ports stay the same
- File storage structure preserved
- Only additions, no modifications

## Verification After Update

### Check Service Status
```bash
# Check if services are running
systemctl status kayease-processor
systemctl status bazarxpress-processor
systemctl status bazarxpressdemo-processor
```

### Test Health Endpoints
```bash
# Test each service
curl https://img.kayease.com/health | jq
curl https://img.bazarxpress.in/health | jq
curl https://img.bazarxpress.kayease.com/health | jq

# Verify audio support
curl https://img.kayease.com/health | jq '.supported_formats.audio'

# Expected output:
# [".mp3", ".wav", ".flac", ".aac", ".ogg", ".m4a", ".wma", ".opus", ".aiff", ".oga"]
```

### Test Audio Upload
```bash
# Create test audio file
ffmpeg -f lavfi -i "sine=frequency=440:duration=2" test.mp3

# Upload to service
curl -X POST "https://img.kayease.com/upload/test" \
  -H "X-API-Key: kayease_live_f9580b55ae74176a9a3432d571ed9c4d" \
  -F "file=@test.mp3"

# Clean up
rm test.mp3
```

## Troubleshooting

### Update Failed for a Service

If an update fails, the script automatically rolls back. Check the error message:

```bash
# View service logs
journalctl -u kayease-processor -n 50

# Check service status
systemctl status kayease-processor

# Manually restart if needed
systemctl restart kayease-processor
```

### Service Won't Start After Update

```bash
# Check logs for errors
journalctl -u kayease-processor -n 100

# Manually rollback using backup
cd /var/backups/tixa-updates/
ls -lt | head -5  # Find latest backup

# Extract backup
tar -xzf kayease-20260127-121500.tar.gz -C /opt/kayease-processor/

# Restart service
systemctl restart kayease-processor
```

### FFmpeg Not Found

```bash
# Install FFmpeg
apt-get update
apt-get install -y ffmpeg

# Verify installation
ffmpeg -version

# Re-run update
tixa update --all
```

### Dependencies Installation Failed

```bash
# Manually install dependencies
cd /opt/kayease-processor
source venv/bin/activate
pip install numpy matplotlib
deactivate

# Re-run update
tixa update kayease
```

## Manual Rollback

If you need to manually rollback a service:

```bash
# 1. Find the backup
ls -lt /var/backups/tixa-updates/

# 2. Stop the service
systemctl stop kayease-processor

# 3. Restore from backup
tar -xzf /var/backups/tixa-updates/kayease-20260127-121500.tar.gz \
    -C /opt/kayease-processor/

# 4. Start the service
systemctl start kayease-processor

# 5. Verify
systemctl status kayease-processor
curl https://img.kayease.com/health
```

## Best Practices

### 1. Update During Low Traffic
```bash
# Schedule updates during off-peak hours
# Example: Late night or early morning
```

### 2. Update One Service First
```bash
# Test with one service before updating all
tixa update bazarxpressdemo  # Demo service first
# Verify it works
# Then update production services
tixa update kayease
tixa update bazarxpress
```

### 3. Monitor After Update
```bash
# Watch logs for 5-10 minutes after update
journalctl -u kayease-processor -f
journalctl -u bazarxpress-processor -f
journalctl -u bazarxpressdemo-processor -f
```

### 4. Keep Backups
```bash
# Backups are kept automatically
# Clean up old backups after 30 days
find /var/backups/tixa-updates/ -name "*.tar.gz" -mtime +30 -delete
```

## What's New After Update

### New API Endpoints

#### 1. Waveform Generation
```bash
GET /process/audio/waveform/{size}/{audio_path}?color={color}

# Example:
https://img.kayease.com/process/audio/waveform/800x200/podcasts/audio.mp3?color=blue
```

#### 2. Audio Streaming
```bash
GET /stream/audio/{audio_path}

# Example:
https://img.kayease.com/stream/audio/podcasts/audio.mp3
```

#### 3. Format Conversion
```bash
GET /process/audio/convert/{format}/{audio_path}?bitrate={bitrate}

# Example:
https://img.kayease.com/process/audio/convert/mp3/podcasts/audio.wav?bitrate=320k
```

### Enhanced Existing Endpoints

#### Upload Endpoint
Now accepts audio files and returns audio-specific URLs:
```json
{
  "file_type": "audio",
  "processed_url": "https://img.kayease.com/process/audio/waveform/800x200/...",
  "thumbnail_url": "https://img.kayease.com/process/audio/waveform/400x100/..."
}
```

#### Info Endpoint
Now includes audio metadata:
```json
{
  "file_type": "audio",
  "audio_metadata": {
    "duration": "00:03:45.23",
    "bitrate": "192",
    "codec": "mp3",
    "sample_rate": "44100 Hz",
    "channels": "stereo"
  }
}
```

#### Health Endpoint
Now reports audio formats:
```json
{
  "status": "healthy",
  "supported_formats": {
    "images": [...],
    "videos": [...],
    "documents": [...],
    "audio": [".mp3", ".wav", ".flac", ...]
  }
}
```

## Quick Reference

```bash
# Update single service (interactive)
tixa update

# Update specific service
tixa update kayease

# Update all services
tixa update --all

# Update all (skip confirmation)
tixa update --all --yes

# Check service status
systemctl status kayease-processor

# View logs
journalctl -u kayease-processor -f

# Test health
curl https://img.kayease.com/health | jq

# List backups
ls -lh /var/backups/tixa-updates/
```

## Support

If you encounter issues:

1. Check service logs: `journalctl -u {service}-processor -n 100`
2. Verify service status: `systemctl status {service}-processor`
3. Test health endpoint: `curl https://{domain}/health`
4. Review backup files: `ls /var/backups/tixa-updates/`
5. Manual rollback if needed (see Manual Rollback section)

---

**The update command is designed to be safe, fast, and reliable. Your services will continue running with minimal interruption!** 🚀
