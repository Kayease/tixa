# Tixa Audio Processing Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          AUDIO FILE UPLOAD                               │
│  MP3 │ WAV │ FLAC │ AAC │ OGG │ M4A │ WMA │ OPUS │ AIFF                │
└────────────────────────────┬────────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                      FASTAPI MEDIA SERVICE                               │
│                    (templates/main.py)                                   │
└─────────────┬───────────────┬───────────────┬───────────────────────────┘
              │               │               │
              ▼               ▼               ▼
    ┌─────────────┐  ┌─────────────┐  ┌─────────────┐
    │  WAVEFORM   │  │   AUDIO     │  │   FORMAT    │
    │ GENERATION  │  │  STREAMING  │  │ CONVERSION  │
    └──────┬──────┘  └──────┬──────┘  └──────┬──────┘
           │                │                │
           ▼                ▼                ▼
    ┌─────────────┐  ┌─────────────┐  ┌─────────────┐
    │   FFmpeg    │  │   Direct    │  │   FFmpeg    │
    │  + Numpy    │  │   File      │  │   Codec     │
    │ + Matplotlib│  │  Streaming  │  │  Conversion │
    └──────┬──────┘  └──────┬──────┘  └──────┬──────┘
           │                │                │
           ▼                ▼                ▼
    ┌─────────────┐  ┌─────────────┐  ┌─────────────┐
    │ PNG Image   │  │   Audio     │  │  Converted  │
    │ (Waveform)  │  │   Stream    │  │    Audio    │
    └──────┬──────┘  └──────┬──────┘  └──────┬──────┘
           │                │                │
           └────────────────┴────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                     STORAGE & CACHING SYSTEM                             │
├─────────────────────┬───────────────────┬───────────────────────────────┤
│   ORIGINALS/        │      CACHE/       │     THUMBNAILS/               │
│   ├── podcasts/     │   ├── waveforms/  │   ├── audio_thumbs/           │
│   ├── music/        │   ├── converted/  │   └── ...                     │
│   └── voicenotes/   │   └── ...         │                               │
└─────────────────────┴───────────────────┴───────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                        CLIENT APPLICATIONS                               │
├─────────────────────┬───────────────────┬───────────────────────────────┤
│   Web Browser       │   Mobile App      │   Desktop App                 │
│   (HTML5 Audio)     │   (Native Player) │   (Electron/etc)              │
└─────────────────────┴───────────────────┴───────────────────────────────┘
```

## Processing Flow Details

### 1. Upload Flow
```
User Upload → API Validation → File Storage → Metadata Extraction → Response with URLs
```

### 2. Waveform Generation Flow
```
Audio File → FFmpeg (Convert to WAV) → Numpy (Process Data) → 
Matplotlib (Generate Image) → PNG Cache → Serve to Client
```

### 3. Streaming Flow
```
Request → Validate Path → Detect MIME Type → 
Set Headers (Accept-Ranges) → Stream File → Client Playback
```

### 4. Conversion Flow
```
Audio File → FFmpeg (Transcode) → Apply Bitrate/Codec → 
Cache Converted File → Serve to Client
```

### 5. Metadata Extraction Flow
```
Audio File → FFmpeg (Probe) → Parse Output → 
Extract (Duration, Bitrate, Codec, Sample Rate, Channels) → Return JSON
```

## API Endpoint Map

```
POST   /upload/{section}                          → Upload audio file
GET    /process/audio/waveform/{size}/{path}      → Generate waveform
GET    /stream/audio/{path}                       → Stream audio
GET    /process/audio/convert/{format}/{path}     → Convert format
GET    /info/{path}                               → Get metadata
GET    /list/{section}                            → List audio files
DELETE /delete/{path}                             → Delete audio file
GET    /health                                    → Service status
```

## Data Flow Diagram

```
┌──────────┐
│  Client  │
└────┬─────┘
     │ 1. Upload Audio
     ▼
┌──────────────────┐
│   FastAPI API    │
│  (API Gateway)   │
└────┬─────────────┘
     │ 2. Store Original
     ▼
┌──────────────────┐
│  File System     │
│  /originals/     │
└────┬─────────────┘
     │ 3. Process Request
     ▼
┌──────────────────┐
│  Audio Processor │
│  (FFmpeg/Numpy)  │
└────┬─────────────┘
     │ 4. Cache Result
     ▼
┌──────────────────┐
│  File System     │
│  /cache/         │
└────┬─────────────┘
     │ 5. Return URL
     ▼
┌──────────┐
│  Client  │
└──────────┘
```

## Component Dependencies

```
┌─────────────────────────────────────────────┐
│         Python Application Layer            │
│  ┌─────────────────────────────────────┐   │
│  │         FastAPI Framework           │   │
│  └─────────────────────────────────────┘   │
│  ┌──────────┐  ┌──────────┐  ┌─────────┐  │
│  │  Pyvips  │  │ PyMuPDF  │  │  Numpy  │  │
│  │ (Images) │  │  (PDFs)  │  │ (Audio) │  │
│  └──────────┘  └──────────┘  └─────────┘  │
│  ┌──────────────────────────────────────┐  │
│  │         Matplotlib (Waveforms)       │  │
│  └──────────────────────────────────────┘  │
└─────────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────┐
│        System Binary Dependencies           │
│  ┌──────────┐  ┌──────────┐  ┌─────────┐   │
│  │  FFmpeg  │  │ libvips  │  │  Other  │   │
│  │ (A/V)    │  │ (Images) │  │  Tools  │   │
│  └──────────┘  └──────────┘  └─────────┘   │
└─────────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────┐
│          Operating System (Linux)           │
└─────────────────────────────────────────────┘
```

## Caching Strategy

```
Request for Processed Audio
        │
        ▼
    ┌───────┐
    │ Cache │ ──Yes──→ Return Cached File
    │ Exists?│
    └───┬───┘
        │ No
        ▼
    Process Audio
        │
        ▼
    Save to Cache
        │
        ▼
    Return New File
```

## Security Layers

```
┌─────────────────────────────────────────────┐
│  1. API Key Authentication                  │
│     (X-API-Key header validation)           │
└────────────────┬────────────────────────────┘
                 ▼
┌─────────────────────────────────────────────┐
│  2. Path Traversal Protection               │
│     (_safe_within_base validation)          │
└────────────────┬────────────────────────────┘
                 ▼
┌─────────────────────────────────────────────┐
│  3. File Type Validation                    │
│     (Extension whitelist)                   │
└────────────────┬────────────────────────────┘
                 ▼
┌─────────────────────────────────────────────┐
│  4. Input Sanitization                      │
│     (URL decoding, path normalization)      │
└────────────────┬────────────────────────────┘
                 ▼
┌─────────────────────────────────────────────┐
│  5. Process Isolation                       │
│     (Subprocess timeouts, error handling)   │
└─────────────────────────────────────────────┘
```

## Performance Optimization

```
┌─────────────────────────────────────────────┐
│  Optimization Layer 1: Caching              │
│  • Waveforms cached after generation        │
│  • Converted files cached                   │
│  • Automatic cache invalidation on delete   │
└────────────────┬────────────────────────────┘
                 ▼
┌─────────────────────────────────────────────┐
│  Optimization Layer 2: Processing           │
│  • Downsampling for waveforms (8kHz)        │
│  • Lazy processing (on-demand)              │
│  • Efficient numpy operations               │
└────────────────┬────────────────────────────┘
                 ▼
┌─────────────────────────────────────────────┐
│  Optimization Layer 3: Delivery             │
│  • Direct file streaming (no processing)    │
│  • Accept-Ranges for seeking               │
│  • Proper MIME types for browser caching    │
└─────────────────────────────────────────────┘
```
