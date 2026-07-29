from fastapi import FastAPI, HTTPException, UploadFile, File, Depends, Header, Query
from fastapi.responses import FileResponse
from fastapi.middleware.cors import CORSMiddleware
import pyvips
import subprocess
import uuid
import os
import re
import shutil
import secrets
import hashlib
import logging
import threading
import contextlib
import tempfile
from pathlib import Path
from urllib.parse import quote, unquote
from typing import Iterable, List
import fitz  # PyMuPDF for PDF processing
from PIL import Image as PILImage
import io
import wave
import numpy as np
import matplotlib

matplotlib.use("Agg")  # never attempt to open a display from a service process
from matplotlib.figure import Figure
from matplotlib.backends.backend_agg import FigureCanvasAgg

app = FastAPI(title="Advanced Media Processing Service")

logger = logging.getLogger("media-processor")

# ---------------------------
# Configuration
# ---------------------------
PROJECT_NAME = "{{PROJECT}}"
BASE_PATH = Path(f"/var/www/images/{PROJECT_NAME}")
ORIGINALS_DIR = BASE_PATH / "originals"
CACHE_DIR = BASE_PATH / "cache"
THUMBNAILS_DIR = BASE_PATH / "thumbnails"

ORIGINALS_DIR.mkdir(parents=True, exist_ok=True)
CACHE_DIR.mkdir(parents=True, exist_ok=True)
THUMBNAILS_DIR.mkdir(parents=True, exist_ok=True)

# Resolved once at import so every containment check compares canonical paths.
ORIGINALS_ROOT = ORIGINALS_DIR.resolve()
CACHE_ROOT = CACHE_DIR.resolve()
THUMBNAILS_ROOT = THUMBNAILS_DIR.resolve()

# Configure via env in production
API_KEY = "{{API_KEY}}"
VPS_BASE_URL = "{{BASE_URL}}"
FFMPEG_BIN_ENV = os.getenv("FFMPEG_BIN")

# ---------------------------
# Resource limits
# ---------------------------
# Kept in step with `client_max_body_size` in the generated Nginx configuration.
MAX_UPLOAD_SIZE = int(os.getenv("MAX_UPLOAD_SIZE", 500 * 1024 * 1024))
UPLOAD_CHUNK_SIZE = 1024 * 1024

# Output bounds shared by every renderer.
MAX_DIMENSION = 4096
MAX_OUTPUT_PIXELS = 4096 * 4096

# Refuse decompression bombs before handing them to libvips/PyMuPDF/Pillow.
MAX_SOURCE_PIXELS = int(os.getenv("MAX_SOURCE_PIXELS", 200_000_000))
PILImage.MAX_IMAGE_PIXELS = MAX_SOURCE_PIXELS

MAX_PREVIEW_PAGES = 10

FFMPEG_TIMEOUT = 60
FFMPEG_PROBE_TIMEOUT = 15
FFMPEG_THREADS = "2"

# Bound the number of media jobs running at once. Requests beyond this wait
# briefly and then get 503 rather than exhausting CPU and memory.
MAX_CONCURRENT_JOBS = int(os.getenv("MAX_CONCURRENT_JOBS", max(2, min(8, os.cpu_count() or 2))))
JOB_WAIT_TIMEOUT = 30

# Supported formats
SUPPORTED_IMAGE_FORMATS = {'.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp', '.tiff', '.tif', '.svg'}
SUPPORTED_VIDEO_FORMATS = {'.mp4', '.mov', '.avi', '.mkv', '.webm', '.flv', '.wmv', '.m4v', '.3gp'}
SUPPORTED_PDF_FORMATS = {'.pdf'}
SUPPORTED_DOCUMENT_FORMATS = {'.pdf', '.doc', '.docx', '.txt', '.rtf'}
SUPPORTED_AUDIO_FORMATS = {'.mp3', '.wav', '.flac', '.aac', '.ogg', '.m4a', '.wma', '.opus', '.aiff', '.oga'}

ALL_SUPPORTED_FORMATS = SUPPORTED_IMAGE_FORMATS.union(SUPPORTED_VIDEO_FORMATS).union(SUPPORTED_DOCUMENT_FORMATS).union(SUPPORTED_AUDIO_FORMATS)

WAVEFORM_COLORS = {
    "blue": "#3B82F6",
    "green": "#10B981",
    "red": "#EF4444",
    "purple": "#8B5CF6",
    "orange": "#F97316",
    "pink": "#EC4899",
    "cyan": "#06B6D4",
}
DEFAULT_WAVEFORM_COLOR = "blue"

AUDIO_OUTPUT_FORMATS = {'mp3', 'wav', 'ogg', 'flac', 'm4a', 'aac'}

_BITRATE_PATTERN = re.compile(r"^[0-9]{1,4}k$")
# Accepts plain seconds, MM:SS and HH:MM:SS, each with optional fractional
# seconds. Anything else — notably values starting with "-", which ffmpeg would
# read as an option — is refused.
_TIMESTAMP_PATTERN = re.compile(
    r"^(?:\d{1,5}(?:\.\d{1,3})?|(?:\d{1,3}:)?[0-5]?\d:[0-5]?\d(?:\.\d{1,3})?)$"
)

# ---------------------------
# CORS
# ---------------------------
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ---------------------------
# Security & Utilities
# ---------------------------
def verify_api_key(x_api_key: str = Header(...)):
    if not API_KEY or API_KEY.startswith("{{"):
        logger.error("API_KEY was never substituted into main.py; refusing authenticated requests")
        raise HTTPException(status_code=500, detail="Service is not configured")
    try:
        matches = secrets.compare_digest(x_api_key.encode("utf-8"), API_KEY.encode("utf-8"))
    except (AttributeError, UnicodeEncodeError):
        matches = False
    if not matches:
        raise HTTPException(status_code=403, detail="Forbidden")
    return x_api_key


def _resolve_ffmpeg_binary() -> str:
    if FFMPEG_BIN_ENV:
        if os.path.isabs(FFMPEG_BIN_ENV) and os.path.isfile(FFMPEG_BIN_ENV):
            return FFMPEG_BIN_ENV
        found = shutil.which(FFMPEG_BIN_ENV)
        if found:
            return found
    found_default = shutil.which("ffmpeg")
    if found_default:
        return found_default
    for candidate in ("/usr/bin/ffmpeg", "/usr/local/bin/ffmpeg"):
        if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
            return candidate
    raise HTTPException(
        status_code=500,
        detail="ffmpeg not found. Install ffmpeg: apt update && apt install -y ffmpeg"
    )


def get_file_type(filename: str) -> str:
    ext = Path(filename).suffix.lower()
    if ext in SUPPORTED_IMAGE_FORMATS:
        return "image"
    elif ext in SUPPORTED_VIDEO_FORMATS:
        return "video"
    elif ext in SUPPORTED_PDF_FORMATS:
        return "pdf"
    elif ext in SUPPORTED_AUDIO_FORMATS:
        return "audio"
    elif ext in SUPPORTED_DOCUMENT_FORMATS:
        return "document"
    else:
        return "unknown"


# ---------------------------
# Path containment
#
# Every filesystem path derived from a request goes through these helpers. A
# prefix comparison is not a containment check: "/var/www/images/media-evil"
# starts with "/var/www/images/media" but belongs to a different service.
# ---------------------------
def _is_within(path: Path, base: Path) -> bool:
    try:
        path.resolve().relative_to(base.resolve())
        return True
    except (ValueError, OSError):
        return False


def _normalize_relative(raw: str, allow_empty: bool = False) -> str:
    """Reduce a request-supplied path to a clean relative path, or reject it."""
    if raw is None:
        raw = ""
    if "\x00" in raw:
        raise HTTPException(status_code=400, detail="Invalid path")

    segments: List[str] = []
    for segment in raw.replace("\\", "/").split("/"):
        if segment in ("", "."):
            continue
        if segment == "..":
            raise HTTPException(status_code=403, detail="Forbidden")
        segments.append(segment)

    if not segments:
        if allow_empty:
            return ""
        raise HTTPException(status_code=400, detail="Invalid path")
    return "/".join(segments)


def _safe_path(base: Path, relative: str, allow_empty: bool = False) -> Path:
    """Resolve `relative` under `base`, guaranteeing the result stays inside it."""
    normalized = _normalize_relative(relative, allow_empty=allow_empty)
    base_root = base.resolve()
    candidate = (base_root / normalized).resolve() if normalized else base_root
    if not _is_within(candidate, base_root):
        raise HTTPException(status_code=403, detail="Forbidden")
    return candidate


def _prune_empty_parents(start_dir: Path, stop_dir: Path) -> None:
    try:
        current = start_dir.resolve()
        stop = stop_dir.resolve()
        while current != stop and _is_within(current, stop) and current.is_dir():
            if any(current.iterdir()):
                break
            current.rmdir()
            current = current.parent
    except Exception:
        pass


# ---------------------------
# Derivative (cache) layout
#
# Derivatives live under <cache-or-thumbnails>/derivatives/<original relative
# path>/<kind>_<hash of parameters>.<ext>. The directory component comes from an
# already-validated original path and the file component is a hash, so no
# request value is ever interpolated into a filesystem path. It also makes
# invalidation exact: deleting an original removes one directory.
# ---------------------------
DERIVATIVES_SUBDIR = "derivatives"


def _relative_original(original_full_path: Path) -> Path:
    try:
        return original_full_path.resolve().relative_to(ORIGINALS_ROOT)
    except ValueError:
        raise HTTPException(status_code=403, detail="Forbidden")


def _derivative_dir(base_root: Path, original_full_path: Path) -> Path:
    directory = base_root / DERIVATIVES_SUBDIR / _relative_original(original_full_path)
    if not _is_within(directory, base_root):
        raise HTTPException(status_code=403, detail="Forbidden")
    return directory


def _derivative_path(base_root: Path, original_full_path: Path, kind: str, params: Iterable, extension: str) -> Path:
    digest = hashlib.sha256("\x1f".join(str(part) for part in params).encode("utf-8")).hexdigest()[:20]
    path = _derivative_dir(base_root, original_full_path) / f"{kind}_{digest}{extension}"
    if not _is_within(path, base_root):
        raise HTTPException(status_code=403, detail="Forbidden")
    return path


@contextlib.contextmanager
def _atomic_output(final_path: Path):
    """Render to a sibling temp file and rename, so concurrent requests never
    observe a half-written derivative. The temp name keeps the final suffix
    because libvips and ffmpeg both choose their encoder from it."""
    final_path.parent.mkdir(parents=True, exist_ok=True)
    temp_path = final_path.parent / f".{final_path.stem}.{uuid.uuid4().hex}.tmp{final_path.suffix}"
    try:
        yield temp_path
        os.replace(temp_path, final_path)
    finally:
        if temp_path.exists():
            try:
                temp_path.unlink()
            except OSError:
                pass


# ---------------------------
# Concurrency and subprocess control
# ---------------------------
_job_semaphore = threading.BoundedSemaphore(MAX_CONCURRENT_JOBS)


@contextlib.contextmanager
def _job_slot():
    if not _job_semaphore.acquire(timeout=JOB_WAIT_TIMEOUT):
        raise HTTPException(status_code=503, detail="Server is busy processing media. Please retry shortly.")
    try:
        yield
    finally:
        _job_semaphore.release()


def _run_ffmpeg(arguments: List[str], timeout: int = FFMPEG_TIMEOUT, check: bool = True):
    """Run ffmpeg with a hard timeout. Failure detail is logged, never returned:
    raw stderr discloses server paths and build configuration."""
    ffmpeg_bin = _resolve_ffmpeg_binary()
    command = [ffmpeg_bin, "-hide_banner", "-nostdin", "-threads", FFMPEG_THREADS] + arguments
    try:
        result = subprocess.run(command, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        logger.warning("ffmpeg timed out after %ss", timeout)
        raise HTTPException(status_code=504, detail="Media processing timed out")
    if check and result.returncode != 0:
        logger.error("ffmpeg exited %s: %s", result.returncode, result.stderr[-2000:])
        raise HTTPException(status_code=500, detail="Media processing failed")
    return result


def _validate_dimensions(width: int, height: int) -> None:
    if width < 1 or height < 1 or width > MAX_DIMENSION or height > MAX_DIMENSION:
        raise HTTPException(
            status_code=422,
            detail=f"Width and height must be between 1 and {MAX_DIMENSION}"
        )
    if width * height > MAX_OUTPUT_PIXELS:
        raise HTTPException(status_code=422, detail="Requested output is too large")


def _parse_size(size: str) -> tuple:
    """Parse `{size}` or `{width}x{height}` from a path segment."""
    try:
        normalized = size.lower().strip()
        if "x" in normalized:
            width_str, height_str = normalized.split("x", 1)
            width = int(width_str)
            height = int(height_str)
        else:
            width = height = int(normalized)
    except Exception:
        raise HTTPException(
            status_code=422,
            detail=f"Invalid size. Use {{size}} or {{width}}x{{height}} (maximum {MAX_DIMENSION})"
        )
    _validate_dimensions(width, height)
    return width, height


def _open_source_image(path: Path) -> "pyvips.Image":
    try:
        image = pyvips.Image.new_from_file(str(path))
    except Exception:
        logger.exception("libvips could not open %s", path)
        raise HTTPException(status_code=422, detail="Source image could not be decoded")
    if image.width * image.height > MAX_SOURCE_PIXELS:
        raise HTTPException(status_code=422, detail="Source image is too large to process")
    return image


def _strip_known_extension(path_str: str, extensions: set) -> str:
    lower = path_str.lower()
    for ext in extensions:
        if lower.endswith(ext):
            return path_str[: -len(ext)]
    return path_str


def _sanitize_video_path(path_str: str) -> str:
    return _strip_known_extension(path_str, SUPPORTED_VIDEO_FORMATS)


def _sanitize_audio_path(path_str: str) -> str:
    """Remove audio extension from path if present"""
    return _strip_known_extension(path_str, SUPPORTED_AUDIO_FORMATS)


def _resolve_media_original(relative_path: str, extensions: set) -> Path:
    """Find the original for an extension-less media path, staying inside
    ORIGINALS_DIR for every candidate that is tried."""
    normalized = _normalize_relative(relative_path)
    stem = _strip_known_extension(normalized, extensions)

    candidates = []
    for ext in sorted(extensions):
        candidates.append(f"{stem}{ext}")
        candidates.append(f"{stem}{ext.upper()}")
    candidates.append(normalized)

    for candidate in candidates:
        full_path = (ORIGINALS_ROOT / candidate).resolve()
        if _is_within(full_path, ORIGINALS_ROOT) and full_path.is_file():
            return full_path
    raise FileNotFoundError


def _require_original(relative_path: str) -> Path:
    original_full_path = _safe_path(ORIGINALS_DIR, relative_path)
    if not original_full_path.is_file():
        raise HTTPException(status_code=404, detail="File not found")
    return original_full_path


# ---------------------------
# Upload Endpoint (Enhanced)
# ---------------------------
@app.post("/upload/{section:path}")
async def upload_file(
    section: str,
    file: UploadFile = File(...),
    api_key: str = Depends(verify_api_key),
):
    # Validate file type
    source_name = Path((file.filename or "").replace("\\", "/")).name
    if not source_name or source_name in (".", ".."):
        raise HTTPException(status_code=400, detail="Invalid file name")
    if "\x00" in source_name:
        raise HTTPException(status_code=400, detail="Invalid file name")

    file_ext = Path(source_name).suffix.lower()
    if file_ext not in ALL_SUPPORTED_FORMATS:
        raise HTTPException(
            status_code=400,
            detail=f"Unsupported file format. Supported: {', '.join(ALL_SUPPORTED_FORMATS)}"
        )

    # `section` is caller-controlled; without containment it can create and
    # write into directories anywhere on the filesystem.
    section_dir = _safe_path(ORIGINALS_DIR, section, allow_empty=True)
    section_dir.mkdir(parents=True, exist_ok=True)

    filename = f"{uuid.uuid4().hex}_{source_name}"
    dest_path = section_dir / filename
    if not _is_within(dest_path, ORIGINALS_ROOT):
        raise HTTPException(status_code=403, detail="Forbidden")

    # Stream to disk. Reading the whole body into memory lets a few concurrent
    # 500 MB uploads exhaust RAM.
    temp_path = section_dir / f".{uuid.uuid4().hex}.upload"
    total_bytes = 0
    try:
        with open(temp_path, "wb") as buffer:
            while True:
                chunk = await file.read(UPLOAD_CHUNK_SIZE)
                if not chunk:
                    break
                total_bytes += len(chunk)
                if total_bytes > MAX_UPLOAD_SIZE:
                    raise HTTPException(
                        status_code=413,
                        detail=f"File exceeds the maximum upload size of {MAX_UPLOAD_SIZE // (1024 * 1024)} MB"
                    )
                buffer.write(chunk)

        if total_bytes == 0:
            raise HTTPException(status_code=400, detail="Uploaded file is empty")

        os.replace(temp_path, dest_path)
    except HTTPException:
        temp_path.unlink(missing_ok=True)
        raise
    except Exception:
        temp_path.unlink(missing_ok=True)
        logger.exception("Upload failed for section %r", section)
        raise HTTPException(status_code=500, detail="Upload failed")
    finally:
        await file.close()

    file_type = get_file_type(source_name)

    section_url = quote(_normalize_relative(section, allow_empty=True))
    url_path = f"{section_url}/{quote(filename)}" if section_url else quote(filename)

    # Generate appropriate URLs based on file type
    original_url = f"{VPS_BASE_URL}/originals/{url_path}"

    if file_type == "image":
        processed_url = f"{VPS_BASE_URL}/process/300/300/{url_path}"
        thumbnail_url = f"{VPS_BASE_URL}/thumbnail/150/150/{url_path}"
    elif file_type == "video":
        processed_url = f"{VPS_BASE_URL}/process/video/thumbnail/300x300/{url_path}"
        thumbnail_url = f"{VPS_BASE_URL}/process/video/thumbnail/150x150/{url_path}"
    elif file_type == "pdf":
        processed_url = f"{VPS_BASE_URL}/process/pdf/thumbnail/300x300/{url_path}"
        thumbnail_url = f"{VPS_BASE_URL}/process/pdf/thumbnail/150x150/{url_path}"
    elif file_type == "audio":
        processed_url = f"{VPS_BASE_URL}/process/audio/waveform/800x200/{url_path}"
        thumbnail_url = f"{VPS_BASE_URL}/process/audio/waveform/400x100/{url_path}"
    else:
        processed_url = original_url
        thumbnail_url = original_url

    return {
        "message": "Upload successful",
        "file_type": file_type,
        "file_name": filename,
        "original_url": original_url,
        "processed_url": processed_url,
        "thumbnail_url": thumbnail_url,
        "section": section
    }


# ---------------------------
# Image Processing (Enhanced)
#
# The processing routes are declared `def`, not `async def`: libvips, PyMuPDF,
# Pillow, Matplotlib and ffmpeg all block, and blocking inside a coroutine
# stalls the whole event loop. FastAPI runs sync handlers in its thread pool.
# ---------------------------
@app.get("/process/{width:int}/{height:int}/{image_path:path}")
def process_image(
    width: int,
    height: int,
    image_path: str,
    quality: int = Query(80, ge=1, le=100),
    format: str = Query("webp", pattern="^(webp|jpeg|png)$")
):
    _validate_dimensions(width, height)

    original_full_path = _safe_path(ORIGINALS_DIR, image_path)
    if not original_full_path.is_file():
        raise HTTPException(status_code=404, detail="Original image not found")

    # Determine output format and extension
    output_ext = f".{format}" if format != "jpeg" else ".jpg"
    media_type = f"image/{format}" if format != "jpeg" else "image/jpeg"
    cache_full_path = _derivative_path(
        CACHE_ROOT, original_full_path, "process", (width, height, quality, format), output_ext
    )

    if cache_full_path.exists():
        return FileResponse(cache_full_path, media_type=media_type)

    with _job_slot():
        if cache_full_path.exists():
            return FileResponse(cache_full_path, media_type=media_type)
        try:
            image = _open_source_image(original_full_path)

            # Resize with different strategies
            image = image.resize(
                width / image.width,
                vscale=height / image.height,
                kernel='lanczos3'  # Better quality scaling
            )

            # Save with specified format and quality
            with _atomic_output(cache_full_path) as temp_path:
                if format == "webp":
                    image.write_to_file(str(temp_path), Q=quality)
                elif format == "jpeg":
                    image.write_to_file(str(temp_path), Q=quality, optimize_coding=True)
                elif format == "png":
                    image.write_to_file(str(temp_path), compression=9)

            return FileResponse(cache_full_path, media_type=media_type)

        except HTTPException:
            raise
        except Exception:
            logger.exception("Image processing failed for %s", original_full_path)
            raise HTTPException(status_code=500, detail="Image processing error")


# ---------------------------
# Image Thumbnail (Preserve Aspect Ratio)
# ---------------------------
@app.get("/thumbnail/{width:int}/{height:int}/{image_path:path}")
def generate_thumbnail(
    width: int,
    height: int,
    image_path: str,
    quality: int = Query(80, ge=1, le=100)
):
    _validate_dimensions(width, height)

    original_full_path = _safe_path(ORIGINALS_DIR, image_path)
    if not original_full_path.is_file():
        raise HTTPException(status_code=404, detail="Original image not found")

    cache_full_path = _derivative_path(
        THUMBNAILS_ROOT, original_full_path, "thumb", (width, height, quality), ".webp"
    )

    if cache_full_path.exists():
        return FileResponse(cache_full_path, media_type="image/webp")

    with _job_slot():
        if cache_full_path.exists():
            return FileResponse(cache_full_path, media_type="image/webp")
        try:
            image = _open_source_image(original_full_path)

            # Preserve aspect ratio for thumbnails
            thumb = image.thumbnail_image(
                width,
                height=height,
                crop=True  # Crop to exact dimensions
            )

            with _atomic_output(cache_full_path) as temp_path:
                thumb.write_to_file(str(temp_path), Q=quality)

            return FileResponse(cache_full_path, media_type="image/webp")

        except HTTPException:
            raise
        except Exception:
            logger.exception("Thumbnail generation failed for %s", original_full_path)
            raise HTTPException(status_code=500, detail="Thumbnail generation error")


# ---------------------------
# Video Processing (Enhanced)
# ---------------------------
@app.get("/process/video/thumbnail/{size}/{video_path:path}")
def generate_video_thumbnail(
    size: str,
    video_path: str,
    timestamp: str = Query("00:00:01", description="Timestamp for thumbnail (HH:MM:SS)")
):
    width, height = _parse_size(size)

    timestamp = timestamp.strip()
    if not _TIMESTAMP_PATTERN.match(timestamp):
        raise HTTPException(status_code=422, detail="Invalid timestamp. Use SS, MM:SS or HH:MM:SS")

    decoded_path = unquote(unquote(video_path))

    try:
        original_full_path = _resolve_media_original(decoded_path, SUPPORTED_VIDEO_FORMATS)
    except FileNotFoundError:
        raise HTTPException(status_code=404, detail="Original video not found")

    # `timestamp` belongs in the cache key: without it every timestamp for a
    # video collapses onto whichever frame was rendered first.
    cache_full_path = _derivative_path(
        CACHE_ROOT, original_full_path, "video_thumb", (width, height, timestamp), ".jpg"
    )

    response_headers = {
        "Content-Disposition": f'inline; filename="video-thumbnail-{width}x{height}.jpg"',
        "X-Content-Type-Options": "nosniff",
    }

    if cache_full_path.exists():
        return FileResponse(cache_full_path, media_type="image/jpeg", headers=response_headers)

    with _job_slot():
        if cache_full_path.exists():
            return FileResponse(cache_full_path, media_type="image/jpeg", headers=response_headers)

        with _atomic_output(cache_full_path) as temp_path:
            _run_ffmpeg([
                "-ss", timestamp,
                "-i", str(original_full_path),
                "-vframes", "1",
                "-vf", f"scale={width}:{height}:force_original_aspect_ratio=increase,crop={width}:{height}",
                "-qscale:v", "2",
                "-y",
                str(temp_path),
            ])

        return FileResponse(cache_full_path, media_type="image/jpeg", headers=response_headers)


# ---------------------------
# PDF Processing
# ---------------------------
@app.get("/process/pdf/thumbnail/{size}/{pdf_path:path}")
def generate_pdf_thumbnail(
    size: str,
    pdf_path: str,
    page: int = Query(0, ge=0, description="Page number (0-based)")
):
    width, height = _parse_size(size)

    original_full_path = _safe_path(ORIGINALS_DIR, pdf_path)
    if not original_full_path.is_file():
        raise HTTPException(status_code=404, detail="Original PDF not found")

    cache_full_path = _derivative_path(
        CACHE_ROOT, original_full_path, "pdf_thumb", (width, height, page), ".jpg"
    )

    if cache_full_path.exists():
        return FileResponse(cache_full_path, media_type="image/jpeg")

    with _job_slot():
        if cache_full_path.exists():
            return FileResponse(cache_full_path, media_type="image/jpeg")

        pdf_document = None
        try:
            # Open PDF and get specified page
            pdf_document = fitz.open(original_full_path)

            if page >= len(pdf_document):
                raise HTTPException(status_code=400, detail=f"Page {page} not found. PDF has {len(pdf_document)} pages.")

            pil_image = _render_pdf_page(pdf_document, page, width, height, zoom=2.0)

            # Create background for exact size
            background = PILImage.new('RGB', (width, height), (255, 255, 255))

            # Calculate position to center the image
            img_width, img_height = pil_image.size
            x = (width - img_width) // 2
            y = (height - img_height) // 2

            # Paste image on background
            background.paste(pil_image, (x, y))

            # Save as JPEG
            with _atomic_output(cache_full_path) as temp_path:
                background.save(temp_path, "JPEG", quality=85)

            return FileResponse(cache_full_path, media_type="image/jpeg")

        except HTTPException:
            raise
        except Exception:
            logger.exception("PDF thumbnail failed for %s", original_full_path)
            raise HTTPException(status_code=500, detail="PDF thumbnail error")
        finally:
            if pdf_document is not None:
                pdf_document.close()


def _render_pdf_page(pdf_document, page_number: int, width: int, height: int, zoom: float):
    pdf_page = pdf_document[page_number]
    rect = pdf_page.rect
    if rect.width <= 0 or rect.height <= 0:
        raise HTTPException(status_code=422, detail="PDF page has no renderable area")

    # Never rasterise more than the caller can receive: scale the zoom down so
    # the intermediate pixmap cannot dwarf the requested output.
    effective_zoom = min(zoom, max(width / rect.width, height / rect.height, 0.1) * 2)
    if rect.width * effective_zoom * rect.height * effective_zoom > MAX_SOURCE_PIXELS:
        raise HTTPException(status_code=422, detail="PDF page is too large to render")

    pix = pdf_page.get_pixmap(matrix=fitz.Matrix(effective_zoom, effective_zoom))
    pil_image = PILImage.open(io.BytesIO(pix.tobytes("ppm")))
    pil_image.thumbnail((width, height), PILImage.Resampling.LANCZOS)
    return pil_image


# ---------------------------
# PDF Preview (Multiple Pages)
# ---------------------------
@app.get("/process/pdf/preview/{pdf_path:path}")
def generate_pdf_preview(
    pdf_path: str,
    pages: str = Query("0", description="Page numbers (comma-separated, 0-based)"),
    size: str = Query("300x300", description="Size for each page thumbnail")
):
    width, height = _parse_size(size)

    try:
        page_numbers = [int(p.strip()) for p in pages.split(",") if p.strip() != ""]
    except Exception:
        raise HTTPException(status_code=422, detail="Invalid parameters")

    if not page_numbers:
        raise HTTPException(status_code=422, detail="At least one page number is required")
    if any(number < 0 for number in page_numbers):
        raise HTTPException(status_code=422, detail="Page numbers must be zero or greater")
    if len(page_numbers) > MAX_PREVIEW_PAGES:
        raise HTTPException(
            status_code=422,
            detail=f"At most {MAX_PREVIEW_PAGES} pages can be previewed in one request"
        )
    if len(page_numbers) * width * height > MAX_OUTPUT_PIXELS:
        raise HTTPException(status_code=422, detail="Requested preview is too large")

    original_full_path = _safe_path(ORIGINALS_DIR, pdf_path)
    if not original_full_path.is_file():
        raise HTTPException(status_code=404, detail="Original PDF not found")

    # Create a unique cache key for this preview
    pages_key = "_".join(str(p) for p in page_numbers)
    cache_full_path = _derivative_path(
        CACHE_ROOT, original_full_path, "pdf_preview", (width, height, pages_key), ".jpg"
    )

    if cache_full_path.exists():
        return FileResponse(cache_full_path, media_type="image/jpeg")

    with _job_slot():
        if cache_full_path.exists():
            return FileResponse(cache_full_path, media_type="image/jpeg")

        pdf_document = None
        try:
            pdf_document = fitz.open(original_full_path)

            preview_images = []
            for page_num in page_numbers:
                if page_num >= len(pdf_document):
                    continue
                preview_images.append(_render_pdf_page(pdf_document, page_num, width, height, zoom=1.5))

            if not preview_images:
                raise HTTPException(status_code=400, detail="No valid pages found")

            # Compose the requested pages side by side. A single page yields the
            # same image this endpoint has always returned.
            combined_image = PILImage.new(
                'RGB', (width * len(preview_images), height), (255, 255, 255)
            )
            for index, page_image in enumerate(preview_images):
                offset_x = index * width + (width - page_image.size[0]) // 2
                offset_y = (height - page_image.size[1]) // 2
                combined_image.paste(page_image, (offset_x, offset_y))

            with _atomic_output(cache_full_path) as temp_path:
                combined_image.save(temp_path, "JPEG", quality=85)

            return FileResponse(cache_full_path, media_type="image/jpeg")

        except HTTPException:
            raise
        except Exception:
            logger.exception("PDF preview failed for %s", original_full_path)
            raise HTTPException(status_code=500, detail="PDF preview error")
        finally:
            if pdf_document is not None:
                pdf_document.close()


# ---------------------------
# Audio Processing - Waveform Generation
# ---------------------------
@app.get("/process/audio/waveform/{size}/{audio_path:path}")
def generate_audio_waveform(
    size: str,
    audio_path: str,
    color: str = Query("blue", description="Waveform color (blue, green, red, purple, orange)")
):
    """
    Generate a waveform visualization for an audio file
    """
    width, height = _parse_size(size)

    # Resolve to a known colour before it reaches the cache key, so unknown
    # names reuse the default entry instead of creating one each.
    color_name = color.lower().strip()
    if color_name not in WAVEFORM_COLORS:
        color_name = DEFAULT_WAVEFORM_COLOR
    waveform_color = WAVEFORM_COLORS[color_name]

    decoded_path = unquote(unquote(audio_path))

    try:
        original_full_path = _resolve_media_original(decoded_path, SUPPORTED_AUDIO_FORMATS)
    except FileNotFoundError:
        raise HTTPException(status_code=404, detail="Original audio file not found")

    cache_full_path = _derivative_path(
        CACHE_ROOT, original_full_path, "audio_waveform", (width, height, color_name), ".png"
    )

    if cache_full_path.exists():
        return FileResponse(cache_full_path, media_type="image/png")

    with _job_slot():
        if cache_full_path.exists():
            return FileResponse(cache_full_path, media_type="image/png")

        temp_wav_path = None
        try:
            # Convert audio to raw PCM data using FFmpeg
            handle = tempfile.NamedTemporaryFile(suffix=".wav", delete=False)
            temp_wav_path = handle.name
            handle.close()

            _run_ffmpeg([
                "-i", str(original_full_path),
                "-ac", "1",  # Convert to mono
                "-ar", "8000",  # Sample rate 8kHz for faster processing
                "-f", "wav",
                "-y",
                temp_wav_path,
            ])

            # Read WAV file and extract audio data
            with wave.open(temp_wav_path, 'r') as wav_file:
                frames = wav_file.readframes(wav_file.getnframes())
                sample_width = wav_file.getsampwidth()

                # Convert bytes to numpy array
                if sample_width == 1:
                    dtype = np.uint8
                elif sample_width == 2:
                    dtype = np.int16
                else:
                    dtype = np.int32

                audio_data = np.frombuffer(frames, dtype=dtype).astype(np.float64)

            if audio_data.size == 0:
                raise HTTPException(status_code=422, detail="Audio file contains no decodable samples")

            # Downsample for visualization
            samples_per_pixel = max(1, len(audio_data) // width)
            usable = (len(audio_data) // samples_per_pixel) * samples_per_pixel
            downsampled = audio_data[:usable].reshape(-1, samples_per_pixel).mean(axis=1)

            # Normalize
            if downsampled.size > 0:
                max_val = np.max(np.abs(downsampled))
                if max_val > 0:
                    downsampled = downsampled / max_val

            # Create waveform visualization
            fig = Figure(figsize=(width / 100, height / 100), dpi=100)
            canvas = FigureCanvasAgg(fig)
            ax = fig.add_subplot(111)

            # Plot waveform
            x = np.linspace(0, len(downsampled), len(downsampled))
            ax.fill_between(x, downsampled, 0, color=waveform_color, alpha=0.7)
            ax.plot(x, downsampled, color=waveform_color, linewidth=0.5)

            # Style
            ax.set_ylim(-1, 1)
            ax.set_xlim(0, max(len(downsampled), 1))
            ax.axis('off')
            fig.patch.set_facecolor('#1F2937')
            ax.set_facecolor('#1F2937')

            # Remove margins
            fig.tight_layout(pad=0)

            # Save to file
            with _atomic_output(cache_full_path) as temp_path:
                with open(temp_path, "wb") as output:
                    canvas.print_png(output)

            return FileResponse(cache_full_path, media_type="image/png")

        except HTTPException:
            raise
        except Exception:
            logger.exception("Waveform generation failed for %s", original_full_path)
            raise HTTPException(status_code=500, detail="Audio waveform generation error")
        finally:
            # Cleaning up only on success leaked a WAV per failed request.
            if temp_wav_path:
                try:
                    os.unlink(temp_wav_path)
                except OSError:
                    pass


# ---------------------------
# Audio Streaming
# ---------------------------
@app.get("/stream/audio/{audio_path:path}")
def stream_audio(audio_path: str):
    """
    Stream audio file with proper headers for browser playback
    """
    decoded_path = unquote(unquote(audio_path))
    original_full_path = _safe_path(ORIGINALS_DIR, decoded_path)

    if not original_full_path.is_file():
        raise HTTPException(status_code=404, detail="Audio file not found")

    # Determine MIME type
    file_ext = original_full_path.suffix.lower()
    mime_types = {
        '.mp3': 'audio/mpeg',
        '.wav': 'audio/wav',
        '.ogg': 'audio/ogg',
        '.oga': 'audio/ogg',
        '.flac': 'audio/flac',
        '.m4a': 'audio/mp4',
        '.aac': 'audio/aac',
        '.opus': 'audio/opus',
        '.wma': 'audio/x-ms-wma',
        '.aiff': 'audio/aiff'
    }

    media_type = mime_types.get(file_ext, 'audio/mpeg')

    return FileResponse(
        original_full_path,
        media_type=media_type,
        headers={
            "Accept-Ranges": "bytes",
            "Content-Disposition": f'inline; filename="{quote(original_full_path.name)}"',
            "X-Content-Type-Options": "nosniff",
        }
    )


# ---------------------------
# Audio Format Conversion
# ---------------------------
@app.get("/process/audio/convert/{format}/{audio_path:path}")
def convert_audio_format(
    format: str,
    audio_path: str,
    bitrate: str = Query("192k", description="Audio bitrate (e.g., 128k, 192k, 320k)")
):
    """
    Convert audio file to different format (mp3, wav, ogg, flac, m4a)
    """
    # Validate format
    format = format.lower()
    if format not in AUDIO_OUTPUT_FORMATS:
        raise HTTPException(
            status_code=400,
            detail=f"Unsupported output format. Supported: {', '.join(sorted(AUDIO_OUTPUT_FORMATS))}"
        )

    bitrate = bitrate.lower().strip()
    if not _BITRATE_PATTERN.match(bitrate):
        raise HTTPException(status_code=422, detail="Invalid bitrate. Use a value such as 128k, 192k or 320k")

    decoded_path = unquote(unquote(audio_path))

    try:
        original_full_path = _resolve_media_original(decoded_path, SUPPORTED_AUDIO_FORMATS)
    except FileNotFoundError:
        raise HTTPException(status_code=404, detail="Original audio file not found")

    # Create cache path for converted file
    mime_type = f"audio/{format}" if format != 'mp3' else "audio/mpeg"
    response_headers = {"Content-Disposition": f'attachment; filename="converted.{format}"'}
    cache_full_path = _derivative_path(
        CACHE_ROOT, original_full_path, "audio_convert", (format, bitrate), f".{format}"
    )

    if cache_full_path.exists():
        return FileResponse(cache_full_path, media_type=mime_type, headers=response_headers)

    with _job_slot():
        if cache_full_path.exists():
            return FileResponse(cache_full_path, media_type=mime_type, headers=response_headers)

        # Build FFmpeg command based on output format
        arguments = ["-i", str(original_full_path)]

        if format == 'mp3':
            arguments.extend(["-codec:a", "libmp3lame", "-b:a", bitrate])
        elif format == 'wav':
            arguments.extend(["-codec:a", "pcm_s16le"])
        elif format == 'ogg':
            arguments.extend(["-codec:a", "libvorbis", "-b:a", bitrate])
        elif format == 'flac':
            arguments.extend(["-codec:a", "flac"])
        elif format in ('m4a', 'aac'):
            arguments.extend(["-codec:a", "aac", "-b:a", bitrate])

        with _atomic_output(cache_full_path) as temp_path:
            # ffmpeg selects the container from the output suffix.
            _run_ffmpeg(arguments + ["-y", str(temp_path)])

        return FileResponse(cache_full_path, media_type=mime_type, headers=response_headers)


# ---------------------------
# File Information Endpoint
# ---------------------------
@app.get("/info/{file_path:path}")
def get_file_info(file_path: str):
    original_full_path = _safe_path(ORIGINALS_DIR, file_path)
    if not original_full_path.is_file():
        raise HTTPException(status_code=404, detail="File not found")

    try:
        file_type = get_file_type(file_path)
        file_stats = original_full_path.stat()

        info = {
            "file_name": original_full_path.name,
            "file_path": str(file_path),
            "file_type": file_type,
            "file_size": file_stats.st_size,
            "file_size_mb": round(file_stats.st_size / (1024 * 1024), 2),
            "created_time": file_stats.st_ctime,
            "modified_time": file_stats.st_mtime,
        }

        # Add type-specific information
        if file_type == "image":
            try:
                image = pyvips.Image.new_from_file(str(original_full_path))
                info.update({
                    "width": image.width,
                    "height": image.height,
                    "format": image.format,
                    "bands": image.bands
                })
            except Exception:
                pass

        elif file_type == "pdf":
            try:
                pdf_document = fitz.open(original_full_path)
                info.update({
                    "page_count": len(pdf_document),
                    "is_encrypted": pdf_document.is_encrypted
                })
                pdf_document.close()
            except Exception:
                pass

        elif file_type == "video":
            try:
                with _job_slot():
                    _run_ffmpeg(
                        ["-i", str(original_full_path)],
                        timeout=FFMPEG_PROBE_TIMEOUT,
                        check=False,
                    )
                info["video_info"] = "Available (needs parsing)"
            except HTTPException:
                pass
            except Exception:
                pass

        elif file_type == "audio":
            try:
                with _job_slot():
                    result = _run_ffmpeg(
                        ["-i", str(original_full_path)],
                        timeout=FFMPEG_PROBE_TIMEOUT,
                        check=False,
                    )

                # Parse audio metadata from FFmpeg output
                audio_info = {}
                stderr = result.stderr

                # Extract duration
                if "Duration:" in stderr:
                    duration_line = [line for line in stderr.split('\n') if 'Duration:' in line]
                    if duration_line:
                        duration_str = duration_line[0].split('Duration:')[1].split(',')[0].strip()
                        audio_info["duration"] = duration_str

                # Extract bitrate
                if "bitrate:" in stderr:
                    bitrate_parts = stderr.split('bitrate:')[1].split()[0]
                    audio_info["bitrate"] = bitrate_parts

                # Extract sample rate and channels
                if "Audio:" in stderr:
                    audio_line = [line for line in stderr.split('\n') if 'Audio:' in line]
                    if audio_line:
                        audio_details = audio_line[0]
                        # Extract codec
                        if "Audio:" in audio_details:
                            codec = audio_details.split('Audio:')[1].split(',')[0].strip()
                            audio_info["codec"] = codec
                        # Extract sample rate
                        if "Hz" in audio_details:
                            sample_rate = audio_details.split('Hz')[0].split()[-1]
                            audio_info["sample_rate"] = f"{sample_rate} Hz"
                        # Extract channels
                        if "stereo" in audio_details.lower():
                            audio_info["channels"] = "stereo"
                        elif "mono" in audio_details.lower():
                            audio_info["channels"] = "mono"

                info["audio_metadata"] = audio_info
            except HTTPException:
                info["audio_metadata"] = {"error": "Metadata unavailable"}
            except Exception:
                logger.exception("Audio metadata failed for %s", original_full_path)
                info["audio_metadata"] = {"error": "Metadata unavailable"}

        return info

    except HTTPException:
        raise
    except Exception:
        logger.exception("File info failed for %s", original_full_path)
        raise HTTPException(status_code=500, detail="Error getting file info")


# ---------------------------
# Delete Endpoint (Enhanced)
# ---------------------------
# Cache files written by earlier Tixa versions used
# "<prefix>_<original path>.<ext>" names. Match those exactly rather than by
# substring, which also removed derivatives of similarly named originals.
_LEGACY_CACHE_PREFIX = re.compile(
    r"^(?:"
    r"\d+x\d+_\d+_"
    r"|thumb_\d+x\d+_"
    r"|video_thumb_\d+x\d+_"
    r"|pdf_thumb_\d+x\d+_"
    r"|pdf_preview_\d+x\d+_"
    r"|audio_waveform_\d+x\d+_[A-Za-z]+_"
    r"|audio_convert_[A-Za-z0-9]+_\d+k_"
    r")"
)
_LEGACY_CACHE_SUFFIX = re.compile(r"_pages?[\d_]*$")


def _legacy_matches(relative_cache_path: str, accepted_bodies: set) -> bool:
    stripped = _LEGACY_CACHE_PREFIX.sub("", relative_cache_path, count=1)
    if stripped == relative_cache_path:
        return False
    body = stripped.rsplit(".", 1)[0]
    body = _LEGACY_CACHE_SUFFIX.sub("", body)
    return body in accepted_bodies


def _remove_derivatives(base_root: Path, original_relative: Path) -> int:
    removed = 0

    derivative_dir = base_root / DERIVATIVES_SUBDIR / original_relative
    if _is_within(derivative_dir, base_root) and derivative_dir.is_dir():
        for entry in derivative_dir.iterdir():
            if entry.is_file():
                try:
                    entry.unlink()
                    removed += 1
                except OSError:
                    pass
        try:
            derivative_dir.rmdir()
            _prune_empty_parents(derivative_dir.parent, base_root / DERIVATIVES_SUBDIR)
        except OSError:
            pass

    # Some legacy names embedded the original path with its extension
    # ("pdf_thumb_300x300_docs/a.pdf_page0.jpg"), others without it
    # ("300x300_80_docs/a.webp"). Accept either, and only either.
    accepted_bodies = {
        original_relative.as_posix().strip("/"),
        (original_relative.parent / original_relative.stem).as_posix().strip("/"),
    }
    for candidate in base_root.rglob("*"):
        if not candidate.is_file():
            continue
        try:
            relative_cache_path = candidate.relative_to(base_root).as_posix()
        except ValueError:
            continue
        if relative_cache_path.startswith(f"{DERIVATIVES_SUBDIR}/"):
            continue
        if _legacy_matches(relative_cache_path, accepted_bodies):
            parent_dir = candidate.parent
            try:
                candidate.unlink()
                removed += 1
                _prune_empty_parents(parent_dir, base_root)
            except OSError:
                pass

    return removed


@app.delete("/delete/{asset_path:path}")
def delete_asset(asset_path: str, api_key: str = Depends(verify_api_key)):
    decoded = unquote(unquote(asset_path))
    original_full_path = _safe_path(ORIGINALS_DIR, decoded)

    if not original_full_path.is_file():
        raise HTTPException(status_code=404, detail="Original file not found")

    original_relative = _relative_original(original_full_path)

    # Attempt to delete original
    try:
        original_parent = original_full_path.parent
        original_full_path.unlink()
        _prune_empty_parents(original_parent, ORIGINALS_DIR)
    except Exception:
        logger.exception("Failed to delete original %s", original_full_path)
        raise HTTPException(status_code=500, detail="Failed to delete original")

    # Delete cached derivatives
    deleted_cache = 0
    for base_root in (CACHE_ROOT, THUMBNAILS_ROOT):
        try:
            deleted_cache += _remove_derivatives(base_root, original_relative)
        except Exception:
            logger.exception("Derivative cleanup failed under %s", base_root)

    return {"message": "Delete successful", "deleted_cache_files": deleted_cache}


# ---------------------------
# List Files Endpoint (NEW)
# ---------------------------
def _build_file_entry(file_path: Path, section: str, section_dir: Path, file_stats) -> dict:
    relative_path = file_path.relative_to(section_dir)

    # Get file type
    file_type = get_file_type(file_path.name)

    # Generate URLs
    file_url_path = f"{section}/{relative_path}" if section else str(relative_path)
    quoted = quote(str(file_url_path))
    original_url = f"{VPS_BASE_URL}/originals/{quoted}"

    # Generate appropriate processed URLs based on file type
    if file_type == "image":
        processed_url = f"{VPS_BASE_URL}/process/300/300/{quoted}"
        thumbnail_url = f"{VPS_BASE_URL}/thumbnail/150/150/{quoted}"
    elif file_type == "video":
        processed_url = f"{VPS_BASE_URL}/process/video/thumbnail/300x300/{quoted}"
        thumbnail_url = f"{VPS_BASE_URL}/process/video/thumbnail/150x150/{quoted}"
    elif file_type == "pdf":
        processed_url = f"{VPS_BASE_URL}/process/pdf/thumbnail/300x300/{quoted}"
        thumbnail_url = f"{VPS_BASE_URL}/process/pdf/thumbnail/150x150/{quoted}"
    elif file_type == "audio":
        processed_url = f"{VPS_BASE_URL}/process/audio/waveform/800x200/{quoted}"
        thumbnail_url = f"{VPS_BASE_URL}/process/audio/waveform/400x100/{quoted}"
    else:
        processed_url = original_url
        thumbnail_url = original_url

    file_info = {
        "name": file_path.name,
        "path": str(relative_path),
        "full_path": str(file_url_path),
        "type": file_type,
        "size": file_stats.st_size,
        "size_mb": round(file_stats.st_size / (1024 * 1024), 2),
        "size_kb": round(file_stats.st_size / 1024, 2),
        "created_time": file_stats.st_ctime,
        "modified_time": file_stats.st_mtime,
        "urls": {
            "original": original_url,
            "processed": processed_url,
            "thumbnail": thumbnail_url,
            "delete": f"{VPS_BASE_URL}/delete/{quoted}"
        }
    }

    # Add type-specific metadata
    if file_type == "image":
        try:
            image = pyvips.Image.new_from_file(str(file_path))
            file_info["metadata"] = {
                "width": image.width,
                "height": image.height,
                "format": image.format,
                "bands": image.bands
            }
        except Exception:
            file_info["metadata"] = {"error": "Could not read image metadata"}

    elif file_type == "pdf":
        try:
            pdf_document = fitz.open(str(file_path))
            file_info["metadata"] = {
                "page_count": len(pdf_document),
                "is_encrypted": pdf_document.is_encrypted
            }
            pdf_document.close()
        except Exception:
            file_info["metadata"] = {"error": "Could not read PDF metadata"}

    return file_info


@app.get("/list/{section:path}")
def list_files(
    section: str,
    api_key: str = Depends(verify_api_key),
    page: int = Query(1, ge=1, description="Page number"),
    limit: int = Query(50, ge=1, le=100, description="Items per page")
):
    """
    List all files in a specific section with pagination and file metadata
    """
    section_dir = _safe_path(ORIGINALS_DIR, section, allow_empty=True)

    if not section_dir.is_dir():
        raise HTTPException(status_code=404, detail=f"Section '{section}' not found")

    try:
        # Stat every file so the listing can be ordered, but decode image and
        # PDF metadata only for the requested page.
        entries = []
        for file_path in section_dir.rglob("*"):
            try:
                if not file_path.is_file():
                    continue
                entries.append((file_path, file_path.stat()))
            except OSError:
                continue

        # Sort files by modification time (newest first)
        entries.sort(key=lambda item: item[1].st_mtime, reverse=True)

        # Pagination
        total_files = len(entries)
        total_pages = (total_files + limit - 1) // limit
        start_idx = (page - 1) * limit
        end_idx = start_idx + limit

        normalized_section = _normalize_relative(section, allow_empty=True)
        paginated_files = []
        for file_path, file_stats in entries[start_idx:end_idx]:
            try:
                paginated_files.append(
                    _build_file_entry(file_path, normalized_section, section_dir, file_stats)
                )
            except Exception:
                logger.exception("Skipping unreadable file %s", file_path)
                continue

        return {
            "section": section,
            "total_files": total_files,
            "total_pages": total_pages,
            "current_page": page,
            "limit": limit,
            "files": paginated_files
        }

    except HTTPException:
        raise
    except Exception:
        logger.exception("Listing failed for section %r", section)
        raise HTTPException(status_code=500, detail="Error listing files")


# ---------------------------
# List Sections Endpoint (NEW)
# ---------------------------
@app.get("/sections")
def list_sections(api_key: str = Depends(verify_api_key)):
    """
    List all available sections (subdirectories in originals)
    """
    try:
        sections = []
        for item in ORIGINALS_DIR.iterdir():
            if item.is_dir():
                file_count = 0
                section_size = 0
                for entry in item.rglob("*"):
                    try:
                        if entry.is_file():
                            file_count += 1
                            section_size += entry.stat().st_size
                    except OSError:
                        continue

                sections.append({
                    "name": item.name,
                    "file_count": file_count,
                    "size_mb": round(section_size / (1024 * 1024), 2),
                    "path": str(item.relative_to(ORIGINALS_DIR))
                })

        # Sort sections by name
        sections.sort(key=lambda x: x["name"])

        return {
            "total_sections": len(sections),
            "sections": sections
        }

    except Exception:
        logger.exception("Listing sections failed")
        raise HTTPException(status_code=500, detail="Error listing sections")


# ---------------------------
# Health Check
# ---------------------------
def _storage_is_writable() -> bool:
    try:
        probe = CACHE_DIR / f".healthcheck-{uuid.uuid4().hex}"
        probe.write_bytes(b"")
        probe.unlink()
        return True
    except Exception:
        return False


@app.get("/health")
def health_check():
    checks = {"storage_writable": _storage_is_writable(), "ffmpeg": True, "libvips": True}

    try:
        _resolve_ffmpeg_binary()
    except Exception:
        checks["ffmpeg"] = False

    try:
        pyvips.Image.black(1, 1)
    except Exception:
        checks["libvips"] = False

    # Only unusable storage makes the service unable to serve; a missing codec
    # degrades it. Reporting 503 for the latter would block key rotation and
    # updates on hosts that simply lack ffmpeg.
    status_code = 503 if not checks["storage_writable"] else 200
    status = "healthy" if all(checks.values()) else "degraded"

    payload = {
        "status": status,
        "service": "Media Processor",
        "checks": checks,
        "supported_formats": {
            "images": list(SUPPORTED_IMAGE_FORMATS),
            "videos": list(SUPPORTED_VIDEO_FORMATS),
            "documents": list(SUPPORTED_DOCUMENT_FORMATS),
            "audio": list(SUPPORTED_AUDIO_FORMATS)
        }
    }

    if status_code != 200:
        raise HTTPException(status_code=status_code, detail=payload)
    return payload
