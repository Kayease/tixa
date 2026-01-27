# Tixa - Advanced Media Processing Service

A comprehensive FastAPI-based media processing service that handles images, videos, PDFs, and **audio files** with advanced processing capabilities.

## Features

### 🖼️ Image Processing
- Multiple format support (JPG, PNG, WebP, GIF, BMP, TIFF, SVG)
- Dynamic resizing and optimization
- Thumbnail generation with aspect ratio preservation
- Format conversion with quality control
- Powered by pyvips for high performance

### 🎬 Video Processing
- Support for MP4, MOV, AVI, MKV, WebM, FLV, WMV, M4V, 3GP
- Video thumbnail extraction at any timestamp
- FFmpeg-powered processing
- Automatic caching

### 📄 PDF Processing
- PDF thumbnail generation
- Multi-page preview support
- Page-specific rendering
- Metadata extraction

### 🎵 **Audio Processing** (NEW!)
- **10 audio formats supported**: MP3, WAV, FLAC, AAC, OGG, M4A, WMA, OPUS, AIFF
- **Waveform generation**: Visual audio representation with customizable colors
- **Audio streaming**: Browser-compatible streaming with proper MIME types
- **Format conversion**: Convert between formats on-the-fly with bitrate control
- **Metadata extraction**: Duration, bitrate, codec, sample rate, channels
- **Caching system**: Automatic caching for waveforms and conversions

## Quick Start

### Installation

1. Clone the repository:
```bash
git clone https://github.com/yourusername/tixa.git
cd tixa
```

2. Install dependencies:
```bash
# Install Python dependencies
pip install -r requirements.txt

# Install FFmpeg (required for video and audio processing)
sudo apt update && sudo apt install -y ffmpeg

# Install libvips (required for image processing)
sudo apt install -y libvips libvips-dev
```

3. Run the installation script:
```bash
bash install.sh
```

## Audio Support

For detailed audio processing documentation, see [AUDIO_SUPPORT.md](./AUDIO_SUPPORT.md)

### Quick Audio Examples

**Upload Audio:**
```bash
curl -X POST "https://your-domain.com/upload/podcasts" \
  -H "X-API-Key: your-api-key" \
  -F "file=@audio.mp3"
```

**Generate Waveform:**
```
GET /process/audio/waveform/800x200/podcasts/audio.mp3?color=blue
```

**Stream Audio:**
```html
<audio controls>
  <source src="https://your-domain.com/stream/audio/podcasts/audio.mp3">
</audio>
```

**Convert Format:**
```
GET /process/audio/convert/mp3/podcasts/audio.wav?bitrate=320k
```

## API Endpoints

### Core Endpoints
- `POST /upload/{section}` - Upload media files
- `GET /originals/{path}` - Access original files
- `DELETE /delete/{path}` - Delete files and cached derivatives

### Image Endpoints
- `GET /process/{width}/{height}/{path}` - Process images
- `GET /thumbnail/{width}/{height}/{path}` - Generate thumbnails

### Video Endpoints
- `GET /process/video/thumbnail/{size}/{path}` - Video thumbnails

### PDF Endpoints
- `GET /process/pdf/thumbnail/{size}/{path}` - PDF thumbnails
- `GET /process/pdf/preview/{path}` - Multi-page preview

### Audio Endpoints (NEW!)
- `GET /process/audio/waveform/{size}/{path}` - Generate waveform
- `GET /stream/audio/{path}` - Stream audio
- `GET /process/audio/convert/{format}/{path}` - Convert format

### Utility Endpoints
- `GET /info/{path}` - File information and metadata
- `GET /list/{section}` - List files in section
- `GET /sections` - List all sections
- `GET /health` - Service health check

## Supported Formats

| Type | Formats |
|------|---------|
| **Images** | JPG, JPEG, PNG, WebP, GIF, BMP, TIFF, SVG |
| **Videos** | MP4, MOV, AVI, MKV, WebM, FLV, WMV, M4V, 3GP |
| **Documents** | PDF, DOC, DOCX, TXT, RTF |
| **Audio** | MP3, WAV, FLAC, AAC, OGG, M4A, WMA, OPUS, AIFF |

## Configuration

The service uses environment variables and template placeholders:

- `{{PROJECT}}` - Project name for file organization
- `{{API_KEY}}` - API authentication key
- `{{BASE_URL}}` - Base URL for generated URLs
- `FFMPEG_BIN` - Custom FFmpeg binary path (optional)

## Directory Structure

```
/var/www/images/{PROJECT}/
├── originals/     # Original uploaded files
├── cache/         # Processed files (images, video thumbnails, audio waveforms, conversions)
└── thumbnails/    # Image thumbnails
```

## Security Features

- API key authentication
- Path traversal protection
- Safe file handling
- CORS support with configurable origins

## Performance

- **Caching**: All processed files are cached for instant subsequent access
- **Lazy Processing**: Files are processed on-demand
- **Efficient Storage**: Automatic cleanup of empty directories
- **Optimized Libraries**: Uses pyvips for fast image processing

## Use Cases

- **Content Management Systems**: Centralized media storage and processing
- **E-commerce Platforms**: Product images with dynamic sizing
- **Podcast Platforms**: Audio hosting with waveform visualization
- **Video Platforms**: Video thumbnails and previews
- **Document Management**: PDF previews and thumbnails
- **Music Libraries**: Audio streaming and format conversion

## Requirements

- Python 3.8+
- FFmpeg (for video and audio processing)
- libvips (for image processing)
- See `requirements.txt` for Python dependencies

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

[Your License Here]

## Support

For detailed audio processing documentation, see [AUDIO_SUPPORT.md](./AUDIO_SUPPORT.md)

For issues and questions, please open an issue on GitHub.