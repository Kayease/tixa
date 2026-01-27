# Quick Installation Guide - Audio Support

This guide will help you set up the audio processing capabilities for your Tixa media service.

## Prerequisites

- Python 3.8 or higher
- Ubuntu/Debian Linux (or similar)
- Root or sudo access

## Step 1: Install System Dependencies

### Install FFmpeg (Required for Audio & Video Processing)

```bash
# Update package list
sudo apt update

# Install FFmpeg
sudo apt install -y ffmpeg

# Verify installation
ffmpeg -version
```

Expected output should show FFmpeg version information.

### Install libvips (Required for Image Processing)

```bash
# Install libvips and development files
sudo apt install -y libvips libvips-dev

# Verify installation
vips --version
```

## Step 2: Install Python Dependencies

### Option A: Using pip (Recommended)

```bash
# Navigate to your project directory
cd /path/to/tixa

# Install all dependencies
pip install -r requirements.txt
```

### Option B: Manual Installation

```bash
# Core framework
pip install fastapi>=0.104.0
pip install uvicorn[standard]>=0.24.0
pip install python-multipart>=0.0.6

# Image processing
pip install pyvips>=2.2.1
pip install Pillow>=10.1.0

# PDF processing
pip install PyMuPDF>=1.23.0

# Audio processing (NEW)
pip install numpy>=1.24.0
pip install matplotlib>=3.7.0

# Additional utilities
pip install aiofiles>=23.2.1
```

## Step 3: Verify Installation

### Test FFmpeg

```bash
# Test audio conversion
ffmpeg -version

# Test if FFmpeg can process audio
ffmpeg -f lavfi -i "sine=frequency=1000:duration=1" -ac 1 test.mp3
rm test.mp3
```

### Test Python Dependencies

```bash
python3 << EOF
import numpy
import matplotlib
import wave
import pyvips
import fitz
print("✓ All Python dependencies installed successfully!")
EOF
```

## Step 4: Configure the Service

### Update Configuration Variables

Edit your service configuration or environment file:

```bash
# Example configuration
PROJECT_NAME="your-project-name"
API_KEY="your-secure-api-key"
BASE_URL="https://your-domain.com"
FFMPEG_BIN="/usr/bin/ffmpeg"  # Optional, auto-detected if not set
```

### Create Required Directories

```bash
# Create base directory structure
sudo mkdir -p /var/www/images/your-project-name/{originals,cache,thumbnails}

# Set proper permissions
sudo chown -R www-data:www-data /var/www/images/your-project-name
sudo chmod -R 755 /var/www/images/your-project-name
```

## Step 5: Test the Service

### Start the Service

```bash
# Navigate to your project directory
cd /path/to/tixa

# Start the service (development mode)
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

### Test Health Endpoint

```bash
# Check if service is running
curl http://localhost:8000/health
```

Expected response:
```json
{
  "status": "healthy",
  "service": "Impexinfo Media Processor",
  "supported_formats": {
    "images": [...],
    "videos": [...],
    "documents": [...],
    "audio": [".mp3", ".wav", ".flac", ".aac", ".ogg", ".m4a", ".wma", ".opus", ".aiff", ".oga"]
  }
}
```

### Test Audio Upload

```bash
# Create a test audio file
ffmpeg -f lavfi -i "sine=frequency=440:duration=5" -ac 2 test-audio.mp3

# Upload the test file
curl -X POST "http://localhost:8000/upload/test" \
  -H "X-API-Key: your-api-key" \
  -F "file=@test-audio.mp3"

# Clean up
rm test-audio.mp3
```

### Test Waveform Generation

```bash
# Generate waveform (replace with your uploaded file path)
curl "http://localhost:8000/process/audio/waveform/800x200/test/your-file.mp3?color=blue" \
  --output waveform.png

# View the waveform
# On Linux with GUI:
xdg-open waveform.png
```

### Test Audio Streaming

```bash
# Stream audio file
curl "http://localhost:8000/stream/audio/test/your-file.mp3" \
  --output streamed-audio.mp3

# Play the audio (requires mpv or similar)
mpv streamed-audio.mp3
```

### Test Format Conversion

```bash
# Convert MP3 to WAV
curl "http://localhost:8000/process/audio/convert/wav/test/your-file.mp3" \
  --output converted.wav

# Verify the converted file
file converted.wav
```

## Step 6: Production Deployment

### Using Systemd Service

Create a systemd service file:

```bash
sudo nano /etc/systemd/system/tixa-media.service
```

Add the following content:

```ini
[Unit]
Description=Tixa Media Processing Service
After=network.target

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=/path/to/tixa
Environment="PATH=/usr/local/bin:/usr/bin:/bin"
ExecStart=/usr/bin/python3 -m uvicorn main:app --host 0.0.0.0 --port 8000
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

Enable and start the service:

```bash
# Reload systemd
sudo systemctl daemon-reload

# Enable service to start on boot
sudo systemctl enable tixa-media

# Start the service
sudo systemctl start tixa-media

# Check status
sudo systemctl status tixa-media
```

### Using Nginx Reverse Proxy

Create Nginx configuration:

```bash
sudo nano /etc/nginx/sites-available/tixa-media
```

Add the following:

```nginx
server {
    listen 80;
    server_name your-domain.com;

    client_max_body_size 100M;

    location / {
        proxy_pass http://localhost:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # For audio streaming
        proxy_buffering off;
        proxy_request_buffering off;
    }
}
```

Enable the site:

```bash
# Create symbolic link
sudo ln -s /etc/nginx/sites-available/tixa-media /etc/nginx/sites-enabled/

# Test configuration
sudo nginx -t

# Reload Nginx
sudo systemctl reload nginx
```

## Troubleshooting

### FFmpeg Not Found

**Error:** `ffmpeg not found. Install ffmpeg: apt update && apt install -y ffmpeg`

**Solution:**
```bash
sudo apt update
sudo apt install -y ffmpeg
which ffmpeg  # Should show /usr/bin/ffmpeg
```

### Matplotlib Import Error

**Error:** `ModuleNotFoundError: No module named 'matplotlib'`

**Solution:**
```bash
pip install matplotlib>=3.7.0
```

### Numpy Import Error

**Error:** `ModuleNotFoundError: No module named 'numpy'`

**Solution:**
```bash
pip install numpy>=1.24.0
```

### Permission Denied

**Error:** `Permission denied` when accessing `/var/www/images/`

**Solution:**
```bash
sudo chown -R www-data:www-data /var/www/images/
sudo chmod -R 755 /var/www/images/
```

### Waveform Generation Timeout

**Error:** Waveform generation takes too long or times out

**Solution:**
- Reduce the waveform size (e.g., 400x100 instead of 1200x300)
- Increase timeout in the code if needed
- Check available system resources

### Audio Conversion Fails

**Error:** `FFmpeg conversion error`

**Solution:**
```bash
# Check FFmpeg codecs
ffmpeg -codecs | grep -i mp3
ffmpeg -codecs | grep -i aac

# Ensure all required codecs are available
sudo apt install -y ffmpeg libavcodec-extra
```

## Performance Tuning

### Increase Upload Size Limit

For Nginx:
```nginx
client_max_body_size 500M;
```

For Uvicorn:
```bash
uvicorn main:app --limit-max-requests 1000 --timeout-keep-alive 5
```

### Cache Management

Monitor cache size:
```bash
du -sh /var/www/images/your-project/cache/
```

Clean old cache files (optional):
```bash
# Remove cache files older than 30 days
find /var/www/images/your-project/cache/ -type f -mtime +30 -delete
```

## Next Steps

1. ✅ Review the [AUDIO_SUPPORT.md](./AUDIO_SUPPORT.md) for detailed API documentation
2. ✅ Check [ARCHITECTURE.md](./ARCHITECTURE.md) for system architecture
3. ✅ Open [examples/audio-demo.html](./examples/audio-demo.html) for interactive demo
4. ✅ Read [IMPLEMENTATION_SUMMARY.md](./IMPLEMENTATION_SUMMARY.md) for complete feature list

## Support

If you encounter any issues:

1. Check the service logs: `sudo journalctl -u tixa-media -f`
2. Verify FFmpeg installation: `ffmpeg -version`
3. Test Python dependencies: `python3 -c "import numpy, matplotlib, wave"`
4. Review the troubleshooting section above

## Security Checklist

- [ ] Change default API key
- [ ] Use HTTPS in production
- [ ] Set up firewall rules
- [ ] Limit file upload sizes
- [ ] Regular security updates
- [ ] Monitor disk usage
- [ ] Set up log rotation
- [ ] Backup original files

---

**Installation Complete!** 🎉

Your Tixa media service now supports comprehensive audio processing with 10 different formats, waveform generation, streaming, and format conversion capabilities.
