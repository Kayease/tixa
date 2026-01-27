# Safe VPS Update Strategy

## Deployment Flow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                    CURRENT STATE (VPS)                          │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Service Running: main.py (without audio support)        │  │
│  │  Port: 8000                                              │  │
│  │  Status: ✓ Healthy                                       │  │
│  │  Features: Images, Videos, PDFs                          │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    STEP 1: BACKUP (No Downtime)                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  cp main.py main.py.backup                               │  │
│  │  Service continues running normally                       │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│              STEP 2: INSTALL DEPENDENCIES (No Downtime)         │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  apt install ffmpeg                                      │  │
│  │  pip install numpy matplotlib                            │  │
│  │  Service continues running normally                       │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│              STEP 3: DEPLOY NEW CODE (No Downtime)              │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Upload new main.py to VPS                               │  │
│  │  Service still running old version                        │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│         STEP 4: GRACEFUL RESTART (1-2 seconds downtime)         │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  systemctl restart service                               │  │
│  │  ⏱️  Brief interruption: ~1-2 seconds                    │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    NEW STATE (VPS)                              │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Service Running: main.py (WITH audio support)           │  │
│  │  Port: 8000                                              │  │
│  │  Status: ✓ Healthy                                       │  │
│  │  Features: Images, Videos, PDFs, AUDIO ✨                │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

## Zero-Downtime Alternative (Blue-Green Deployment)

```
┌─────────────────────────────────────────────────────────────────┐
│                    CURRENT STATE                                │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  OLD Service: Port 8000 (Active)                         │  │
│  │  Nginx → Port 8000                                       │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│              STEP 1: START NEW INSTANCE                         │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  OLD Service: Port 8000 (Active) ✓                       │  │
│  │  NEW Service: Port 8001 (Testing) 🆕                     │  │
│  │  Nginx → Port 8000 (unchanged)                           │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│              STEP 2: VERIFY NEW INSTANCE                        │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Test: curl localhost:8001/health                        │  │
│  │  Verify audio support working                            │  │
│  │  OLD Service: Still serving traffic                      │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│              STEP 3: SWITCH TRAFFIC (Instant)                   │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Nginx: proxy_pass → Port 8001                          │  │
│  │  nginx reload (no downtime)                              │  │
│  │  Traffic now going to NEW service                        │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│              STEP 4: CLEANUP OLD INSTANCE                       │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Stop OLD service on port 8000                           │  │
│  │  NEW Service: Port 8001 (Active) ✓                       │  │
│  │  Keep OLD as backup for quick rollback                   │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

## Comparison: Deployment Methods

| Method | Downtime | Complexity | Rollback Speed | Best For |
|--------|----------|------------|----------------|----------|
| **Graceful Restart** | 1-2 seconds | Low | Fast (1 min) | Small services, low traffic |
| **Blue-Green** | 0 seconds | Medium | Instant | Production, high traffic |
| **Rolling Update** | 0 seconds | High | Medium | Multiple instances |

## Risk Assessment

```
┌─────────────────────────────────────────────────────────────────┐
│                    RISK LEVEL: LOW ✅                           │
├─────────────────────────────────────────────────────────────────┤
│  ✓ Backward Compatible: All existing endpoints work            │
│  ✓ No Breaking Changes: Only additions, no modifications       │
│  ✓ Dependencies Safe: numpy & matplotlib don't conflict        │
│  ✓ Rollback Ready: Backup file available                       │
│  ✓ Tested Code: Production-ready implementation                │
└─────────────────────────────────────────────────────────────────┘
```

## Timeline Estimate

```
Activity                          Time        Downtime
─────────────────────────────────────────────────────────
SSH + Backup                      2 min       None
Install FFmpeg                    2 min       None
Install Python packages           1 min       None
Upload new code                   1 min       None
Restart service                   30 sec      1-2 sec
Verification                      2 min       None
─────────────────────────────────────────────────────────
TOTAL                            8.5 min      1-2 sec
```

## What Stays the Same

```
✓ All existing API endpoints
✓ Image processing functionality
✓ Video processing functionality
✓ PDF processing functionality
✓ Upload endpoint behavior
✓ Delete endpoint behavior
✓ List endpoint behavior
✓ Authentication (API key)
✓ File storage structure
✓ Cache mechanism
✓ Security features
```

## What's New (Additions Only)

```
+ Audio format support (10 formats)
+ Waveform generation endpoint
+ Audio streaming endpoint
+ Format conversion endpoint
+ Audio metadata in /info endpoint
+ Audio formats in /health endpoint
```

## Rollback Procedure (If Needed)

```
┌─────────────────────────────────────────────────────────────────┐
│  PROBLEM DETECTED                                               │
└────────────────┬────────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────────┐
│  1. Stop current service                                        │
│     sudo systemctl stop your-service                            │
└────────────────┬────────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────────┐
│  2. Restore backup                                              │
│     cp main.py.backup main.py                                   │
└────────────────┬────────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────────┐
│  3. Start service                                               │
│     sudo systemctl start your-service                           │
└────────────────┬────────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────────┐
│  SERVICE RESTORED (2 minutes total)                             │
└─────────────────────────────────────────────────────────────────┘
```

## Monitoring Checklist

After deployment, monitor these for 15-30 minutes:

```
□ Service status: systemctl status your-service
□ Error logs: journalctl -u your-service -f
□ Health endpoint: curl localhost:8000/health
□ CPU usage: top or htop
□ Memory usage: free -h
□ Disk usage: df -h
□ Response times: curl -w "@curl-format.txt" localhost:8000/health
```

## Success Criteria

Your deployment is successful when:

```
✓ Service is running (systemctl status shows active)
✓ Health endpoint returns "healthy"
✓ Audio formats appear in /health response
✓ Existing features work (test image/video/pdf)
✓ No errors in logs
✓ Response times are normal
✓ Memory usage is stable
```

---

## Quick Command Reference

```bash
# Pre-deployment
ssh user@vps
cp main.py main.py.backup

# Install
sudo apt install -y ffmpeg
pip install numpy matplotlib

# Deploy
scp local/main.py user@vps:/path/main.py
sudo systemctl restart service

# Verify
curl localhost:8000/health | jq

# Rollback (if needed)
cp main.py.backup main.py
sudo systemctl restart service
```

---

**Recommendation**: Use **Graceful Restart** method for simplicity. Total downtime: ~1-2 seconds during restart. All existing functionality preserved. ✅
