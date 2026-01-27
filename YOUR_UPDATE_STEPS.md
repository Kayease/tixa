# Update Your 3 Services - Quick Guide

## Your Current Services

```
📦 TIXA · SERVICES
--------------------------
Project : kayease
Domain  : img.kayease.com
Port    : 12515
API Key : kayease_live_f9580b55ae74176a9a3432d571ed9c4d
--------------------------
Project : bazarxpress
Domain  : img.bazarxpress.in
Port    : 18311
API Key : bazarxpress_live_32e4a1ce595dd4016b093cf631abd70f
--------------------------
Project : bazarxpressdemo
Domain  : img.bazarxpress.kayease.com
Port    : 13473
API Key : bazarxpressdemo_live_d881e8e6b7a7bf4a7f4e5a162ad4642f
```

## What You Need to Do

### Step 1: Update Tixa CLI on VPS

First, you need to upload the updated Tixa files to your VPS.

**From your local machine (Windows):**

```powershell
# Navigate to tixa directory
cd d:\tixa

# Upload updated files to VPS
scp -r cli core templates user@your-vps-ip:/opt/tixa/

# Or if you have specific files:
scp cli/tixa user@your-vps-ip:/opt/tixa/cli/
scp core/update.sh user@your-vps-ip:/opt/tixa/core/
scp core/create.sh user@your-vps-ip:/opt/tixa/core/
scp templates/main.py user@your-vps-ip:/opt/tixa/templates/
```

### Step 2: Make Update Script Executable

**On your VPS:**

```bash
# SSH into your VPS
ssh user@your-vps-ip

# Make update script executable
chmod +x /opt/tixa/core/update.sh
chmod +x /opt/tixa/cli/tixa

# Verify tixa command works
tixa
```

You should see the new "Updates:" section in the help menu.

### Step 3: Run the Update

**Option A: Update All Services at Once (Recommended)**

```bash
# Update all 3 services with one command
tixa update --all

# Or skip confirmation:
tixa update --all --yes
```

**Option B: Update One by One (Safer for Testing)**

```bash
# Test with demo service first
tixa update bazarxpressdemo

# Verify it works
curl https://img.bazarxpress.kayease.com/health | jq '.supported_formats.audio'

# Then update production services
tixa update kayease
tixa update bazarxpress
```

### Step 4: Verify Updates

```bash
# Check all services are running
systemctl status kayease-processor
systemctl status bazarxpress-processor
systemctl status bazarxpressdemo-processor

# Test health endpoints
curl https://img.kayease.com/health | jq
curl https://img.bazarxpress.in/health | jq
curl https://img.bazarxpress.kayease.com/health | jq

# Verify audio support
curl https://img.kayease.com/health | jq '.supported_formats.audio'
```

Expected output:
```json
[
  ".mp3",
  ".wav",
  ".flac",
  ".aac",
  ".ogg",
  ".m4a",
  ".wma",
  ".opus",
  ".aiff",
  ".oga"
]
```

## Complete Update Process (Copy-Paste)

Here's the complete process you can copy and paste:

```bash
# ============================================
# STEP 1: SSH into VPS
# ============================================
ssh user@your-vps-ip

# ============================================
# STEP 2: Verify current services
# ============================================
tixa list

# ============================================
# STEP 3: Update all services
# ============================================
tixa update --all --yes

# ============================================
# STEP 4: Verify updates
# ============================================
# Check services are running
systemctl status kayease-processor bazarxpress-processor bazarxpressdemo-processor

# Test health endpoints
echo "Testing kayease..."
curl -s https://img.kayease.com/health | jq '.supported_formats.audio'

echo "Testing bazarxpress..."
curl -s https://img.bazarxpress.in/health | jq '.supported_formats.audio'

echo "Testing bazarxpressdemo..."
curl -s https://img.bazarxpress.kayease.com/health | jq '.supported_formats.audio'

# ============================================
# STEP 5: Test audio upload (optional)
# ============================================
# Create test audio
ffmpeg -f lavfi -i "sine=frequency=440:duration=2" test.mp3

# Upload to demo service
curl -X POST "https://img.bazarxpress.kayease.com/upload/test" \
  -H "X-API-Key: bazarxpressdemo_live_d881e8e6b7a7bf4a7f4e5a162ad4642f" \
  -F "file=@test.mp3"

# Clean up
rm test.mp3

echo "✅ All services updated successfully!"
```

## Timeline

```
Total time: ~2-3 minutes
├── Upload files to VPS: 30 seconds
├── Update all 3 services: 1-2 minutes
│   ├── kayease: ~25 seconds (1-2 sec downtime)
│   ├── bazarxpress: ~25 seconds (1-2 sec downtime)
│   └── bazarxpressdemo: ~25 seconds (1-2 sec downtime)
└── Verification: 30 seconds

Total downtime: 3-6 seconds (1-2 sec per service)
```

## What Happens During Update

For each of your 3 services:

1. ✅ **Backup created** → `/var/backups/tixa-updates/{service}-{timestamp}.tar.gz`
2. ✅ **Dependencies installed** → numpy, matplotlib
3. ✅ **Code deployed** → New main.py with audio support
4. ✅ **Syntax verified** → Auto-rollback if errors
5. ⚡ **Service restarted** → 1-2 seconds downtime
6. ✅ **Health checked** → Confirms audio support active

## After Update

Your services will have:

### New Capabilities
- ✅ Audio file upload (10 formats)
- ✅ Waveform generation
- ✅ Audio streaming
- ✅ Format conversion
- ✅ Audio metadata extraction

### Unchanged
- ✅ All existing image/video/PDF functionality
- ✅ API keys (same as before)
- ✅ Domains (same as before)
- ✅ Ports (same as before)
- ✅ File storage structure

## Test Audio Features

### Upload Audio File
```bash
# Create test audio
ffmpeg -f lavfi -i "sine=frequency=440:duration=5" test-audio.mp3

# Upload to kayease
curl -X POST "https://img.kayease.com/upload/podcasts" \
  -H "X-API-Key: kayease_live_f9580b55ae74176a9a3432d571ed9c4d" \
  -F "file=@test-audio.mp3"

# Response will include:
# - original_url: Direct audio file
# - processed_url: Waveform visualization
# - thumbnail_url: Smaller waveform
```

### Generate Waveform
```bash
# Blue waveform (default)
https://img.kayease.com/process/audio/waveform/800x200/podcasts/your-file.mp3

# Green waveform
https://img.kayease.com/process/audio/waveform/800x200/podcasts/your-file.mp3?color=green

# Purple waveform
https://img.kayease.com/process/audio/waveform/800x200/podcasts/your-file.mp3?color=purple
```

### Stream Audio
```html
<!-- HTML5 Audio Player -->
<audio controls>
  <source src="https://img.kayease.com/stream/audio/podcasts/your-file.mp3" type="audio/mpeg">
</audio>
```

### Convert Format
```bash
# Convert to MP3
https://img.kayease.com/process/audio/convert/mp3/podcasts/your-file.wav?bitrate=320k

# Convert to WAV
https://img.kayease.com/process/audio/convert/wav/podcasts/your-file.mp3

# Convert to FLAC (lossless)
https://img.kayease.com/process/audio/convert/flac/podcasts/your-file.mp3
```

## Rollback (If Needed)

If something goes wrong with any service:

```bash
# Find the backup
ls -lt /var/backups/tixa-updates/

# Stop the service
systemctl stop kayease-processor

# Restore from backup
tar -xzf /var/backups/tixa-updates/kayease-{timestamp}.tar.gz \
    -C /opt/kayease-processor/

# Start the service
systemctl start kayease-processor

# Verify
curl https://img.kayease.com/health
```

## Monitoring

Monitor your services after update:

```bash
# Watch all service logs
journalctl -u kayease-processor -u bazarxpress-processor -u bazarxpressdemo-processor -f

# Check resource usage
htop

# Monitor disk space (cache will grow with audio files)
df -h
du -sh /var/www/images/*/cache/
```

## Troubleshooting

### Service won't start
```bash
# Check logs
journalctl -u kayease-processor -n 50

# Verify dependencies
cd /opt/kayease-processor
source venv/bin/activate
python3 -c "import numpy, matplotlib, wave"
deactivate
```

### FFmpeg not found
```bash
# Install FFmpeg
apt-get update
apt-get install -y ffmpeg

# Verify
ffmpeg -version
```

### Audio features not working
```bash
# Check if dependencies are installed
cd /opt/kayease-processor
source venv/bin/activate
pip list | grep -E "numpy|matplotlib"
deactivate

# Reinstall if needed
source venv/bin/activate
pip install numpy matplotlib
deactivate

# Restart service
systemctl restart kayease-processor
```

## Summary

**Before Update:**
- 3 services running (images, videos, PDFs)
- Total uptime: 100%

**After Update:**
- 3 services running (images, videos, PDFs, **AUDIO**)
- Total downtime: ~6 seconds (2 sec per service)
- New features: Audio support with 10 formats
- Backups: Saved in `/var/backups/tixa-updates/`

**Command to run:**
```bash
tixa update --all --yes
```

**Time required:** 2-3 minutes  
**Risk level:** LOW (automatic rollback on failure)  
**Breaking changes:** NONE (100% backward compatible)

---

**You're ready to update! Just run `tixa update --all --yes` and you'll have audio support on all 3 services in 2-3 minutes!** 🚀
