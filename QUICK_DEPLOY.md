# Quick Deployment Checklist

## Pre-Deployment (5 minutes)

```bash
# 1. SSH into VPS
ssh user@your-vps-ip

# 2. Create backup
cp /path/to/service/main.py ~/main.py.backup-$(date +%Y%m%d)

# 3. Check current service status
sudo systemctl status your-service-name
```

## Install Dependencies (3 minutes)

```bash
# 4. Install FFmpeg (if not installed)
sudo apt update && sudo apt install -y ffmpeg

# 5. Install Python packages
pip install numpy>=1.24.0 matplotlib>=3.7.0

# 6. Verify installation
python3 -c "import numpy, matplotlib, wave; print('✓ Ready')"
```

## Deploy (2 minutes)

```bash
# 7. Upload new main.py to VPS
# From your local machine:
scp d:\tixa\templates\main.py user@vps:/path/to/service/main.py

# 8. Restart service gracefully
sudo systemctl restart your-service-name

# Or if using PM2:
# pm2 reload your-service-name
```

## Verify (2 minutes)

```bash
# 9. Check service is running
sudo systemctl status your-service-name

# 10. Test health endpoint
curl http://localhost:8000/health | jq '.supported_formats.audio'

# Should show: [".mp3", ".wav", ".flac", ".aac", ".ogg", ".m4a", ".wma", ".opus", ".aiff", ".oga"]

# 11. Test existing features still work
curl http://localhost:8000/health | jq '.status'
# Should show: "healthy"
```

## Rollback (if needed)

```bash
# If something goes wrong:
cp ~/main.py.backup-$(date +%Y%m%d) /path/to/service/main.py
sudo systemctl restart your-service-name
```

---

## Total Time: ~12 minutes

✅ **Zero breaking changes** - All existing functionality remains intact  
✅ **Minimal downtime** - Only during service restart (~1-2 seconds)  
✅ **Easy rollback** - Backup file ready to restore  

---

## One-Line Deployment (Advanced)

If you're confident and want to deploy in one command:

```bash
# Full deployment in one line
ssh user@vps "cd /path/to/service && \
  cp main.py main.py.backup && \
  pip install -q numpy matplotlib && \
  sudo systemctl restart your-service-name && \
  sleep 3 && \
  curl -s http://localhost:8000/health | jq '.supported_formats.audio'"
```

Then upload the new `main.py` file via SCP or your preferred method.

---

## Need Help?

- **Full Guide**: See `DEPLOYMENT_GUIDE.md`
- **Installation**: See `INSTALLATION.md`
- **API Docs**: See `AUDIO_SUPPORT.md`
- **Architecture**: See `ARCHITECTURE.md`
