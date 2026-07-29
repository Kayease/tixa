# Tixa Audio API Guide

## Overview
The media processing service now supports comprehensive audio file handling with multiple formats, waveform generation, streaming, and format conversion capabilities.

## Supported Audio Formats
- **MP3** (.mp3) - MPEG Audio Layer 3
- **WAV** (.wav) - Waveform Audio File Format
- **FLAC** (.flac) - Free Lossless Audio Codec
- **AAC** (.aac) - Advanced Audio Coding
- **OGG** (.ogg, .oga) - Ogg Vorbis
- **M4A** (.m4a) - MPEG-4 Audio
- **WMA** (.wma) - Windows Media Audio
- **OPUS** (.opus) - Opus Interactive Audio Codec
- **AIFF** (.aiff) - Audio Interchange File Format

## Features

### 1. Audio Upload
Upload audio files to any section with automatic metadata extraction.

**Endpoint:** `POST /upload/{section}`

**Example:**
```bash
curl -X POST "https://your-domain.com/upload/podcasts" \
  -H "X-API-Key: your-api-key" \
  -F "file=@audio.mp3"
```

**Response:**
```json
{
  "message": "Upload successful",
  "file_type": "audio",
  "file_name": "abc123_audio.mp3",
  "original_url": "https://your-domain.com/originals/podcasts/abc123_audio.mp3",
  "processed_url": "https://your-domain.com/process/audio/waveform/800x200/podcasts/abc123_audio.mp3",
  "thumbnail_url": "https://your-domain.com/process/audio/waveform/400x100/podcasts/abc123_audio.mp3",
  "section": "podcasts"
}
```

### 2. Waveform Generation
Generate visual waveform representations of audio files.

**Endpoint:** `GET /process/audio/waveform/{size}/{audio_path}`

**Parameters:**
- `size`: Dimensions in format `{width}x{height}` (e.g., 800x200)
- `color`: Waveform color (blue, green, red, purple, orange, pink, cyan) - Optional, default: blue

**Examples:**
```bash
# Blue waveform (default)
GET /process/audio/waveform/800x200/podcasts/abc123_audio.mp3

# Green waveform
GET /process/audio/waveform/800x200/podcasts/abc123_audio.mp3?color=green

# Large purple waveform
GET /process/audio/waveform/1200x300/music/song.mp3?color=purple
```

**Features:**
- Automatic caching for faster subsequent requests
- Multiple color options for branding
- Responsive sizing
- Dark background (#1F2937) for modern UI
- PNG output format

### 3. Audio Streaming
Stream audio files directly in the browser with proper MIME types.

**Endpoint:** `GET /stream/audio/{audio_path}`

**Example:**
```html
<!-- HTML5 Audio Player -->
<audio controls>
  <source src="https://your-domain.com/stream/audio/podcasts/abc123_audio.mp3" type="audio/mpeg">
  Your browser does not support the audio element.
</audio>
```

**Features:**
- Proper MIME type detection for all supported formats
- Browser-compatible streaming
- Accept-Ranges header for seeking support
- Inline content disposition for direct playback

### 4. Audio Format Conversion
Convert audio files between different formats on-the-fly.

**Endpoint:** `GET /process/audio/convert/{format}/{audio_path}`

**Parameters:**
- `format`: Target format (mp3, wav, ogg, flac, m4a, aac)
- `bitrate`: Audio bitrate (e.g., 128k, 192k, 320k) - Optional, default: 192k

**Examples:**
```bash
# Convert to MP3 with default bitrate (192k)
GET /process/audio/convert/mp3/podcasts/original.wav

# Convert to high-quality MP3 (320k)
GET /process/audio/convert/mp3/podcasts/original.wav?bitrate=320k

# Convert to lossless FLAC
GET /process/audio/convert/flac/music/song.mp3

# Convert to OGG Vorbis
GET /process/audio/convert/ogg/podcasts/audio.mp3?bitrate=128k
```

**Supported Conversions:**
- **MP3**: Uses libmp3lame encoder, supports bitrate parameter
- **WAV**: Uncompressed PCM audio
- **OGG**: Uses libvorbis encoder, supports bitrate parameter
- **FLAC**: Lossless compression
- **M4A/AAC**: Uses AAC encoder, supports bitrate parameter

### 5. Audio Metadata Extraction
Get detailed information about audio files.

**Endpoint:** `GET /info/{audio_path}`

**Example:**
```bash
GET /info/podcasts/abc123_audio.mp3
```

**Response:**
```json
{
  "file_name": "abc123_audio.mp3",
  "file_path": "podcasts/abc123_audio.mp3",
  "file_type": "audio",
  "file_size": 5242880,
  "file_size_mb": 5.0,
  "created_time": 1706342400.0,
  "modified_time": 1706342400.0,
  "audio_metadata": {
    "duration": "00:03:45.23",
    "bitrate": "192",
    "codec": "mp3",
    "sample_rate": "44100 Hz",
    "channels": "stereo"
  }
}
```

### 6. List Audio Files
List all audio files in a section with pagination.

**Endpoint:** `GET /list/{section}`

**Parameters:**
- `page`: Page number (default: 1)
- `limit`: Items per page (default: 50, max: 100)

**Example:**
```bash
GET /list/podcasts?page=1&limit=20
```

**Response includes:**
- File metadata
- Audio-specific information
- URLs for original, waveform, and streaming
- Delete endpoint

## Integration Examples

### Frontend Integration (React/Next.js)

```jsx
import React, { useState } from 'react';

const AudioPlayer = ({ audioUrl, waveformUrl }) => {
  const [isPlaying, setIsPlaying] = useState(false);

  return (
    <div className="audio-player">
      {/* Waveform Visualization */}
      <img 
        src={waveformUrl} 
        alt="Audio Waveform" 
        className="w-full h-32 rounded-lg"
      />
      
      {/* Audio Player */}
      <audio 
        controls 
        className="w-full mt-4"
        onPlay={() => setIsPlaying(true)}
        onPause={() => setIsPlaying(false)}
      >
        <source src={audioUrl} type="audio/mpeg" />
        Your browser does not support the audio element.
      </audio>
    </div>
  );
};

// Usage
<AudioPlayer 
  audioUrl="https://your-domain.com/stream/audio/podcasts/episode1.mp3"
  waveformUrl="https://your-domain.com/process/audio/waveform/800x200/podcasts/episode1.mp3?color=blue"
/>
```

### Upload Audio File

```javascript
async function uploadAudio(file, section) {
  const formData = new FormData();
  formData.append('file', file);

  const response = await fetch(`https://your-domain.com/upload/${section}`, {
    method: 'POST',
    headers: {
      'X-API-Key': 'your-api-key'
    },
    body: formData
  });

  const data = await response.json();
  return data;
}

// Usage
const audioFile = document.querySelector('input[type="file"]').files[0];
const result = await uploadAudio(audioFile, 'podcasts');
console.log('Uploaded:', result.original_url);
console.log('Waveform:', result.processed_url);
```

### Convert Audio Format

```javascript
async function convertAudio(audioPath, targetFormat, bitrate = '192k') {
  const url = `https://your-domain.com/process/audio/convert/${targetFormat}/${audioPath}?bitrate=${bitrate}`;
  
  const response = await fetch(url);
  const blob = await response.blob();
  
  // Download converted file
  const downloadUrl = window.URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = downloadUrl;
  a.download = `converted.${targetFormat}`;
  a.click();
}

// Usage
await convertAudio('podcasts/episode1.wav', 'mp3', '320k');
```

## Performance Considerations

### Caching
- Waveforms are cached after first generation
- Converted audio files are cached
- Cache is automatically managed and cleaned up on file deletion

### Optimization Tips
1. **Waveform Generation**: Smaller sizes (400x100) generate faster than larger ones
2. **Format Conversion**: WAV and FLAC conversions are faster than MP3/OGG
3. **Streaming**: Original files stream directly without processing
4. **Bitrate**: Lower bitrates (128k) convert faster than higher ones (320k)

## Error Handling

Common error responses:

```json
// Unsupported format
{
  "detail": "Unsupported file format. Supported: .mp3, .wav, .flac, .aac, .ogg, .m4a, .wma, .opus, .aiff, .oga"
}

// File not found
{
  "detail": "Original audio file not found"
}

// Invalid size format
{
  "detail": "Invalid size format. Use {width}x{height}"
}

// Conversion error
{
  "detail": "Audio conversion error: [error details]"
}
```

## Dependencies

The audio processing features require:
- **FFmpeg**: For audio conversion and metadata extraction
- **Python libraries**:
  - `wave`: WAV file processing
  - `numpy`: Audio data manipulation
  - `matplotlib`: Waveform visualization

## Health Check

Check service status and supported formats:

```bash
GET /health
```

**Response:**
```json
{
  "status": "healthy",
  "service": "Impexinfo Media Processor",
  "supported_formats": {
    "images": [".jpg", ".jpeg", ".png", ...],
    "videos": [".mp4", ".mov", ".avi", ...],
    "documents": [".pdf", ".doc", ".docx", ...],
    "audio": [".mp3", ".wav", ".flac", ".aac", ".ogg", ".m4a", ".wma", ".opus", ".aiff", ".oga"]
  }
}
```

## Use Cases

### 1. Podcast Platform
- Upload podcast episodes in any format
- Generate waveforms for visual appeal
- Stream episodes directly in browser
- Convert to web-optimized formats (MP3)

### 2. Music Library
- Store music in lossless formats (FLAC)
- Generate waveforms for track previews
- Convert to streaming formats on-demand
- Extract metadata for cataloging

### 3. Voice Notes/Recordings
- Upload voice recordings from mobile apps
- Generate visual waveforms for quick identification
- Convert to compressed formats for storage
- Stream for playback

### 4. Audio Content Management
- Centralized audio storage
- Automatic format conversion
- Visual representation for CMS
- Metadata extraction for search

## Best Practices

1. **Upload in High Quality**: Upload in the highest quality format available (FLAC, WAV)
2. **Convert on Demand**: Use conversion endpoints for different use cases
3. **Cache Waveforms**: Waveforms are cached automatically, use consistent sizes
4. **Use Streaming**: Use the streaming endpoint for browser playback
5. **Monitor Storage**: Converted files are cached, monitor disk usage
6. **API Key Security**: Always use HTTPS and keep API keys secure

## Troubleshooting

### FFmpeg Not Found
If you get "ffmpeg not found" errors:
```bash
# Install FFmpeg on Ubuntu/Debian
sudo apt update && sudo apt install -y ffmpeg

# Verify installation
ffmpeg -version
```

### Waveform Generation Fails
- Ensure matplotlib and numpy are installed
- Check audio file is not corrupted
- Verify sufficient disk space for cache

### Conversion Timeout
- Large files may take longer to convert
- Consider increasing timeout limits for production
- Use lower bitrates for faster conversion

## API Reference Summary

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/upload/{section}` | POST | Upload audio file |
| `/process/audio/waveform/{size}/{path}` | GET | Generate waveform |
| `/stream/audio/{path}` | GET | Stream audio file |
| `/process/audio/convert/{format}/{path}` | GET | Convert audio format |
| `/info/{path}` | GET | Get audio metadata |
| `/list/{section}` | GET | List audio files |
| `/delete/{path}` | DELETE | Delete audio file |
| `/health` | GET | Service health check |
