# Safe Deployment Guide - Audio Support Update

This guide will help you safely update your running VPS service with the new audio support features **without affecting ongoing functionality**.

## Pre-Deployment Checklist

Before you begin, ensure you have:

- [ ] SSH access to your VPS
- [ ] Backup of current service files
- [ ] Root or sudo privileges
- [ ] Knowledge of your current service setup (systemd, supervisor, etc.)

## Deployment Strategy

We'll use a **blue-green deployment** approach with the following steps:

1. Install new dependencies (non-disruptive)
2. Test the updated code
3. Deploy with graceful restart
4. Verify functionality
5. Rollback plan (if needed)

---

## Step 1: Backup Current Service

### 1.1 Backup Service Files

```bash
# SSH into your VPS
ssh user@your-vps-ip

# Create backup directory
mkdir -p ~/tixa-backup-$(date +%Y%m%d)

# Backup current main.py
cp /path/to/your/current/main.py ~/tixa-backup-$(date +%Y%m%d)/main.py.backup

# Backup entire service directory (optional but recommended)
tar -czf ~/tixa-backup-$(date +%Y%m%d)/tixa-service-backup.tar.gz /path/to/your/service/
```

### 1.2 Note Current Service Status

```bash
# If using systemd
sudo systemctl status your-service-name

# If using supervisor
sudo supervisorctl status your-service-name

# Note the process ID and port
sudo netstat -tlnp | grep :8000  # Replace 8000 with your port
```

---

## Step 2: Install Dependencies (Non-Disruptive)

Installing dependencies won't affect the running service.

### 2.1 Install FFmpeg (if not already installed)

```bash
# Check if FFmpeg is installed
ffmpeg -version

# If not installed:
sudo apt update
sudo apt install -y ffmpeg

# Verify installation
ffmpeg -version
```

### 2.2 Install Python Dependencies

```bash
# Navigate to your service directory
cd /path/to/your/service/

# Activate virtual environment (if using one)
source venv/bin/activate  # Adjust path as needed

# Install new dependencies WITHOUT upgrading existing ones
pip install numpy>=1.24.0 matplotlib>=3.7.0 --no-deps

# Or install with dependencies (safer)
pip install numpy>=1.24.0 matplotlib>=3.7.0
```

### 2.3 Verify Dependencies

```bash
# Test imports without affecting running service
python3 << 'EOF'
try:
    import numpy
    import matplotlib
    import wave
    print("✓ All audio dependencies installed successfully!")
except ImportError as e:
    print(f"✗ Missing dependency: {e}")
EOF
```

---

## Step 3: Deploy Updated Code

### Option A: Zero-Downtime Deployment (Recommended)

This method runs the new version alongside the old one, then switches traffic.

#### 3.1 Create New Service Instance

```bash
# Copy updated main.py to a new location
cp ~/path/to/new/main.py /path/to/your/service/main_new.py

# Test the new code
cd /path/to/your/service/
python3 -c "import main_new; print('✓ New code syntax is valid')"
```

#### 3.2 Start New Instance on Different Port

```bash
# Start new instance on port 8001 (while old runs on 8000)
uvicorn main_new:app --host 0.0.0.0 --port 8001 &

# Wait a few seconds
sleep 5

# Test new instance
curl http://localhost:8001/health
```

#### 3.3 Verify New Instance Works

```bash
# Test health endpoint
curl http://localhost:8001/health | jq

# Test audio support
curl http://localhost:8001/health | jq '.supported_formats.audio'

# Expected output should include audio formats
```

#### 3.4 Switch Traffic (if using Nginx)

```bash
# Edit Nginx config
sudo nano /etc/nginx/sites-available/your-site

# Change proxy_pass from port 8000 to 8001
# Before: proxy_pass http://localhost:8000;
# After:  proxy_pass http://localhost:8001;

# Test Nginx config
sudo nginx -t

# Reload Nginx (no downtime)
sudo systemctl reload nginx
```

#### 3.5 Stop Old Instance

```bash
# Find old process
ps aux | grep "uvicorn main:app"

# Kill old process gracefully
kill -TERM <old-process-pid>

# Rename files
mv /path/to/your/service/main.py /path/to/your/service/main_old.py
mv /path/to/your/service/main_new.py /path/to/your/service/main.py
```

#### 3.6 Update Service to Use Correct Port

```bash
# If using systemd, edit service file
sudo nano /etc/systemd/system/your-service.service

# Ensure it uses port 8000 again
# ExecStart=/path/to/uvicorn main:app --host 0.0.0.0 --port 8000

# Reload systemd
sudo systemctl daemon-reload

# Update Nginx back to port 8000
sudo nano /etc/nginx/sites-available/your-site
# Change: proxy_pass http://localhost:8000;

# Reload Nginx
sudo nginx -t && sudo systemctl reload nginx
```

---

### Option B: Graceful Restart (Minimal Downtime)

This method has ~1-2 seconds of downtime during restart.

#### 3.1 Replace Code

```bash
# Navigate to service directory
cd /path/to/your/service/

# Backup current file
cp main.py main.py.backup

# Upload new main.py
# (Use scp, git pull, or direct copy)
# Example with scp from local machine:
# scp d:\tixa\templates\main.py user@vps:/path/to/service/main.py
```

#### 3.2 Graceful Restart

**If using systemd:**

```bash
# Reload the service gracefully
sudo systemctl reload your-service-name

# Or restart if reload not supported
sudo systemctl restart your-service-name

# Check status
sudo systemctl status your-service-name
```

**If using supervisor:**

```bash
# Restart gracefully
sudo supervisorctl restart your-service-name

# Check status
sudo supervisorctl status your-service-name
```

**If using PM2:**

```bash
# Reload with zero downtime
pm2 reload your-service-name

# Check status
pm2 status
```

**If running manually:**

```bash
# Find process
ps aux | grep uvicorn

# Send graceful shutdown signal
kill -TERM <process-id>

# Wait for shutdown
sleep 2

# Start new instance
uvicorn main:app --host 0.0.0.0 --port 8000 &
```

---

## Step 4: Verify Deployment

### 4.1 Check Service Health

```bash
# Test health endpoint
curl http://localhost:8000/health

# Should return audio formats
curl http://localhost:8000/health | jq '.supported_formats.audio'

# Expected output:
# [".mp3", ".wav", ".flac", ".aac", ".ogg", ".m4a", ".wma", ".opus", ".aiff", ".oga"]
```

### 4.2 Test Audio Upload

```bash
# Create test audio file
ffmpeg -f lavfi -i "sine=frequency=440:duration=2" -ac 2 test-audio.mp3

# Upload test file
curl -X POST "http://localhost:8000/upload/test" \
  -H "X-API-Key: your-api-key" \
  -F "file=@test-audio.mp3"

# Clean up
rm test-audio.mp3
```

### 4.3 Test Waveform Generation

```bash
# Test waveform endpoint (replace with actual file path from upload)
curl "http://localhost:8000/process/audio/waveform/800x200/test/your-file.mp3?color=blue" \
  --output /tmp/test-waveform.png

# Verify file was created
ls -lh /tmp/test-waveform.png
```

### 4.4 Check Existing Functionality

```bash
# Test image processing (ensure it still works)
curl "http://localhost:8000/health" | jq '.supported_formats.images'

# Test video processing
curl "http://localhost:8000/health" | jq '.supported_formats.videos'

# Test PDF processing
curl "http://localhost:8000/health" | jq '.supported_formats.documents'
```

### 4.5 Monitor Logs

```bash
# If using systemd
sudo journalctl -u your-service-name -f

# If using supervisor
sudo tail -f /var/log/supervisor/your-service-name.log

# Look for any errors
```

---

## Step 5: Rollback Plan (If Needed)

If something goes wrong, you can quickly rollback:

### Quick Rollback

```bash
# Stop current service
sudo systemctl stop your-service-name

# Restore backup
cp ~/tixa-backup-$(date +%Y%m%d)/main.py.backup /path/to/service/main.py

# Start service
sudo systemctl start your-service-name

# Verify
curl http://localhost:8000/health
```

---

## Deployment Script (Automated)

Here's a complete script for automated deployment:

```bash
#!/bin/bash

# Configuration
SERVICE_NAME="your-service-name"
SERVICE_PATH="/path/to/your/service"
BACKUP_DIR="$HOME/tixa-backup-$(date +%Y%m%d-%H%M%S)"
NEW_MAIN_PY="/path/to/new/main.py"

echo "🚀 Starting deployment..."

# Step 1: Create backup
echo "📦 Creating backup..."
mkdir -p "$BACKUP_DIR"
cp "$SERVICE_PATH/main.py" "$BACKUP_DIR/main.py.backup"
echo "✓ Backup created at $BACKUP_DIR"

# Step 2: Install dependencies
echo "📚 Installing dependencies..."
pip install numpy>=1.24.0 matplotlib>=3.7.0 -q
echo "✓ Dependencies installed"

# Step 3: Verify dependencies
echo "🔍 Verifying dependencies..."
python3 << 'EOF'
import numpy
import matplotlib
import wave
print("✓ All dependencies verified")
EOF

# Step 4: Copy new code
echo "📝 Deploying new code..."
cp "$NEW_MAIN_PY" "$SERVICE_PATH/main.py"
echo "✓ Code deployed"

# Step 5: Restart service
echo "🔄 Restarting service..."
sudo systemctl restart "$SERVICE_NAME"
sleep 3

# Step 6: Verify deployment
echo "✅ Verifying deployment..."
HEALTH_CHECK=$(curl -s http://localhost:8000/health)

if echo "$HEALTH_CHECK" | grep -q "audio"; then
    echo "✓ Deployment successful! Audio support is active."
    echo "✓ Backup available at: $BACKUP_DIR"
else
    echo "✗ Deployment verification failed!"
    echo "🔙 Rolling back..."
    cp "$BACKUP_DIR/main.py.backup" "$SERVICE_PATH/main.py"
    sudo systemctl restart "$SERVICE_NAME"
    echo "✓ Rollback complete"
    exit 1
fi

echo "🎉 Deployment complete!"
```

Save this as `deploy.sh` and run:

```bash
chmod +x deploy.sh
./deploy.sh
```

---

## Post-Deployment Monitoring

### Monitor Service Performance

```bash
# Watch service logs
sudo journalctl -u your-service-name -f

# Monitor resource usage
htop

# Check disk usage (cache will grow with audio files)
df -h
du -sh /var/www/images/*/cache/
```

### Set Up Alerts (Optional)

```bash
# Monitor service status
watch -n 5 'systemctl is-active your-service-name'

# Monitor endpoint
watch -n 10 'curl -s http://localhost:8000/health | jq .status'
```

---

## Troubleshooting

### Service Won't Start

```bash
# Check logs
sudo journalctl -u your-service-name -n 50

# Common issues:
# 1. Missing dependencies
pip list | grep -E "numpy|matplotlib"

# 2. Port already in use
sudo netstat -tlnp | grep :8000

# 3. Permission issues
ls -la /var/www/images/
```

### Audio Features Not Working

```bash
# Check FFmpeg
ffmpeg -version

# Test audio processing manually
python3 << 'EOF'
import subprocess
result = subprocess.run(['ffmpeg', '-version'], capture_output=True)
print(result.stdout.decode())
EOF
```

### Existing Features Broken

```bash
# Rollback immediately
cp ~/tixa-backup-*/main.py.backup /path/to/service/main.py
sudo systemctl restart your-service-name
```

---

## Best Practices

1. **Always backup** before deployment
2. **Test in staging** environment first (if available)
3. **Deploy during low-traffic** hours
4. **Monitor logs** for 15-30 minutes after deployment
5. **Keep rollback plan** ready
6. **Document changes** in deployment log

---

## Deployment Checklist

- [ ] Backup current service files
- [ ] Install FFmpeg
- [ ] Install Python dependencies (numpy, matplotlib)
- [ ] Test dependencies
- [ ] Deploy new code
- [ ] Restart service gracefully
- [ ] Verify health endpoint
- [ ] Test audio upload
- [ ] Test waveform generation
- [ ] Verify existing features still work
- [ ] Monitor logs for errors
- [ ] Document deployment
- [ ] Clean up old backups (after 24-48 hours)

---

## Quick Reference Commands

```bash
# Backup
cp main.py main.py.backup-$(date +%Y%m%d)

# Install deps
pip install numpy matplotlib

# Deploy
cp new-main.py main.py

# Restart
sudo systemctl restart your-service

# Verify
curl http://localhost:8000/health | jq

# Rollback
cp main.py.backup main.py && sudo systemctl restart your-service
```

---

**Your service will continue running with all existing functionality while you safely add audio support!** 🚀
