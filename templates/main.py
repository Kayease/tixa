from fastapi import FastAPI, HTTPException, UploadFile, File, Depends, Header, Query
from fastapi.responses import FileResponse, StreamingResponse
from fastapi.middleware.cors import CORSMiddleware
import pyvips
import subprocess
import uuid
import os
import shutil
import tempfile
from pathlib import Path
from urllib.parse import quote, unquote
from typing import Optional
import mimetypes
import fitz  # PyMuPDF for PDF processing
from PIL import Image as PILImage
import io
import json

app = FastAPI(title="Advanced Media Processing Service")

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

# Configure via env in production
API_KEY = "{{API_KEY}}"
VPS_BASE_URL = "{{BASE_URL}}"
FFMPEG_BIN_ENV = os.getenv("FFMPEG_BIN")

# Supported formats
SUPPORTED_IMAGE_FORMATS = {'.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp', '.tiff', '.tif', '.svg'}
SUPPORTED_VIDEO_FORMATS = {'.mp4', '.mov', '.avi', '.mkv', '.webm', '.flv', '.wmv', '.m4v', '.3gp'}
SUPPORTED_PDF_FORMATS = {'.pdf'}
SUPPORTED_DOCUMENT_FORMATS = {'.pdf', '.doc', '.docx', '.txt', '.rtf'}

ALL_SUPPORTED_FORMATS = SUPPORTED_IMAGE_FORMATS.union(SUPPORTED_VIDEO_FORMATS).union(SUPPORTED_DOCUMENT_FORMATS)

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
    if x_api_key != API_KEY:
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
    elif ext in SUPPORTED_DOCUMENT_FORMATS:
        return "document"
    else:
        return "unknown"

def _safe_within_base(path: Path) -> bool:
    return str(path).startswith(str(BASE_PATH))

def _prune_empty_parents(start_dir: Path, stop_dir: Path) -> None:
    try:
        current = start_dir
        while current != stop_dir and current.is_dir():
            if any(current.iterdir()):
                break
            current.rmdir()
            current = current.parent
    except Exception:
        pass

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
    file_ext = Path(file.filename).suffix.lower()
    if file_ext not in ALL_SUPPORTED_FORMATS:
        raise HTTPException(
            status_code=400,
            detail=f"Unsupported file format. Supported: {', '.join(ALL_SUPPORTED_FORMATS)}"
        )

    section_dir = ORIGINALS_DIR / section
    section_dir.mkdir(parents=True, exist_ok=True)

    filename = f"{uuid.uuid4().hex}_{file.filename}"
    dest_path = section_dir / filename

    contents = await file.read()
    with open(dest_path, "wb") as f:
        f.write(contents)
    await file.close()

    file_type = get_file_type(file.filename)

    # Generate appropriate URLs based on file type
    original_url = f"{VPS_BASE_URL}/originals/{quote(section)}/{quote(filename)}"

    if file_type == "image":
        processed_url = f"{VPS_BASE_URL}/process/300/300/{quote(section)}/{quote(filename)}"
        thumbnail_url = f"{VPS_BASE_URL}/thumbnail/150/150/{quote(section)}/{quote(filename)}"
    elif file_type == "video":
        processed_url = f"{VPS_BASE_URL}/process/video/thumbnail/300x300/{quote(section)}/{quote(filename)}"
        thumbnail_url = f"{VPS_BASE_URL}/process/video/thumbnail/150x150/{quote(section)}/{quote(filename)}"
    elif file_type == "pdf":
        processed_url = f"{VPS_BASE_URL}/process/pdf/thumbnail/300x300/{quote(section)}/{quote(filename)}"
        thumbnail_url = f"{VPS_BASE_URL}/process/pdf/thumbnail/150x150/{quote(section)}/{quote(filename)}"
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
# ---------------------------
@app.get("/process/{width}/{height}/{image_path:path}")
async def process_image(
    width: int,
    height: int,
    image_path: str,
    quality: int = Query(80, ge=1, le=100),
    format: str = Query("webp", regex="^(webp|jpeg|png)$")
):
    original_full_path = (ORIGINALS_DIR / image_path).resolve()

    if not _safe_within_base(original_full_path):
        raise HTTPException(status_code=403, detail="Forbidden")
    if not original_full_path.exists():
        raise HTTPException(status_code=404, detail="Original image not found")

    # Determine output format and extension
    output_ext = f".{format}" if format != "jpeg" else ".jpg"
    cache_full_path = (CACHE_DIR / f"{width}x{height}_{quality}_{image_path}").with_suffix(output_ext)
    cache_full_path.parent.mkdir(parents=True, exist_ok=True)

    if cache_full_path.exists():
        media_type = f"image/{format}" if format != "jpeg" else "image/jpeg"
        return FileResponse(cache_full_path, media_type=media_type)

    try:
        image = pyvips.Image.new_from_file(str(original_full_path))

        # Resize with different strategies
        image = image.resize(
            width / image.width,
            vscale=height / image.height,
            kernel='lanczos3'  # Better quality scaling
        )

        # Save with specified format and quality
        if format == "webp":
            image.write_to_file(str(cache_full_path), Q=quality)
        elif format == "jpeg":
            image.write_to_file(str(cache_full_path), Q=quality, optimize_coding=True)
        elif format == "png":
            image.write_to_file(str(cache_full_path), compression=9)

        media_type = f"image/{format}" if format != "jpeg" else "image/jpeg"
        return FileResponse(cache_full_path, media_type=media_type)

    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Image processing error: {str(e)}")

# ---------------------------
# Image Thumbnail (Preserve Aspect Ratio)
# ---------------------------
@app.get("/thumbnail/{width}/{height}/{image_path:path}")
async def generate_thumbnail(
    width: int,
    height: int,
    image_path: str,
    quality: int = Query(80, ge=1, le=100)
):
    original_full_path = (ORIGINALS_DIR / image_path).resolve()

    if not _safe_within_base(original_full_path):
        raise HTTPException(status_code=403, detail="Forbidden")
    if not original_full_path.exists():
        raise HTTPException(status_code=404, detail="Original image not found")

    cache_full_path = (THUMBNAILS_DIR / f"thumb_{width}x{height}_{image_path}").with_suffix(".webp")
    cache_full_path.parent.mkdir(parents=True, exist_ok=True)

    if cache_full_path.exists():
        return FileResponse(cache_full_path, media_type="image/webp")

    try:
        image = pyvips.Image.new_from_file(str(original_full_path))

        # Preserve aspect ratio for thumbnails
        thumb = image.thumbnail_image(
            width,
            height=height,
            crop=True  # Crop to exact dimensions
        )

        thumb.write_to_file(str(cache_full_path), Q=quality)
        return FileResponse(cache_full_path, media_type="image/webp")

    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Thumbnail generation error: {str(e)}")

# ---------------------------
# Video Processing (Enhanced)
# ---------------------------
def _sanitize_video_path(path_str: str) -> str:
    lower = path_str.lower()
    for ext in SUPPORTED_VIDEO_FORMATS:
        if lower.endswith(ext):
            return path_str[: -len(ext)]
    return path_str

def _resolve_video_original_path(base_dir: Path, safe_video_path: str) -> Path:
    candidate_stems = [safe_video_path]
    exts = list(SUPPORTED_VIDEO_FORMATS) + [ext.upper() for ext in SUPPORTED_VIDEO_FORMATS]
    for ext in exts:
        candidate = (base_dir / f"{safe_video_path}{ext}").resolve()
        if candidate.exists():
            return candidate
    direct = (base_dir / safe_video_path).resolve()
    if direct.exists():
        return direct
    raise FileNotFoundError

@app.get("/process/video/thumbnail/{size}/{video_path:path}")
async def generate_video_thumbnail(
    size: str,
    video_path: str,
    timestamp: str = Query("00:00:01", description="Timestamp for thumbnail (HH:MM:SS)")
):
    try:
        width_str, height_str = size.lower().split("x", 1)
        width = int(width_str)
        height = int(height_str)
    except Exception:
        raise HTTPException(status_code=422, detail="Invalid size format. Use {width}x{height}")

    decoded_path = unquote(unquote(video_path))
    safe_video_path = _sanitize_video_path(decoded_path)

    try:
        original_full_path = _resolve_video_original_path(ORIGINALS_DIR, safe_video_path)
    except FileNotFoundError:
        raise HTTPException(status_code=404, detail="Original video not found")

    if not _safe_within_base(original_full_path):
        raise HTTPException(status_code=403, detail="Forbidden")

    cache_full_path = (CACHE_DIR / f"video_thumb_{width}x{height}_{safe_video_path}.jpg").resolve()
    cache_full_path.parent.mkdir(parents=True, exist_ok=True)

    if cache_full_path.exists():
        return FileResponse(cache_full_path, media_type="image/jpeg")

    try:
        ffmpeg_bin = _resolve_ffmpeg_binary()
        command = [
            ffmpeg_bin, "-i", str(original_full_path),
            "-ss", timestamp,
            "-vframes", "1",
            "-vf", f"scale={width}:{height}:force_original_aspect_ratio=increase,crop={width}:{height}",
            "-qscale:v", "2",
            "-y",  # Overwrite output file
            str(cache_full_path),
        ]
        result = subprocess.run(command, capture_output=True, text=True)

        if result.returncode != 0:
            raise Exception(f"FFmpeg error: {result.stderr}")

        return FileResponse(cache_full_path, media_type="image/jpeg")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Video thumbnail error: {str(e)}")

# ---------------------------
# PDF Processing
# ---------------------------
@app.get("/process/pdf/thumbnail/{size}/{pdf_path:path}")
async def generate_pdf_thumbnail(
    size: str,
    pdf_path: str,
    page: int = Query(0, description="Page number (0-based)")
):
    try:
        width_str, height_str = size.lower().split("x", 1)
        width = int(width_str)
        height = int(height_str)
    except Exception:
        raise HTTPException(status_code=422, detail="Invalid size format. Use {width}x{height}")

    original_full_path = (ORIGINALS_DIR / pdf_path).resolve()

    if not _safe_within_base(original_full_path):
        raise HTTPException(status_code=403, detail="Forbidden")
    if not original_full_path.exists():
        raise HTTPException(status_code=404, detail="Original PDF not found")

    cache_full_path = (CACHE_DIR / f"pdf_thumb_{width}x{height}_{pdf_path}_page{page}.jpg").resolve()
    cache_full_path.parent.mkdir(parents=True, exist_ok=True)

    if cache_full_path.exists():
        return FileResponse(cache_full_path, media_type="image/jpeg")

    try:
        # Open PDF and get specified page
        pdf_document = fitz.open(original_full_path)

        if page >= len(pdf_document):
            raise HTTPException(status_code=400, detail=f"Page {page} not found. PDF has {len(pdf_document)} pages.")

        pdf_page = pdf_document[page]

        # Render page to image
        mat = fitz.Matrix(2.0, 2.0)  # Zoom factor for better quality
        pix = pdf_page.get_pixmap(matrix=mat)

        # Convert to PIL Image for processing
        img_data = pix.tobytes("ppm")
        pil_image = PILImage.open(io.BytesIO(img_data))

        # Resize to target dimensions
        pil_image.thumbnail((width, height), PILImage.Resampling.LANCZOS)

        # Create background for exact size
        background = PILImage.new('RGB', (width, height), (255, 255, 255))

        # Calculate position to center the image
        img_width, img_height = pil_image.size
        x = (width - img_width) // 2
        y = (height - img_height) // 2

        # Paste image on background
        background.paste(pil_image, (x, y))

        # Save as JPEG
        background.save(cache_full_path, "JPEG", quality=85)

        pdf_document.close()

        return FileResponse(cache_full_path, media_type="image/jpeg")

    except Exception as e:
        raise HTTPException(status_code=500, detail=f"PDF thumbnail error: {str(e)}")

# ---------------------------
# PDF Preview (Multiple Pages)
# ---------------------------
@app.get("/process/pdf/preview/{pdf_path:path}")
async def generate_pdf_preview(
    pdf_path: str,
    pages: str = Query("0", description="Page numbers (comma-separated, 0-based)"),
    size: str = Query("300x300", description="Size for each page thumbnail")
):
    try:
        width_str, height_str = size.lower().split("x", 1)
        width = int(width_str)
        height = int(height_str)
        page_numbers = [int(p.strip()) for p in pages.split(",")]
    except Exception:
        raise HTTPException(status_code=422, detail="Invalid parameters")

    original_full_path = (ORIGINALS_DIR / pdf_path).resolve()

    if not _safe_within_base(original_full_path):
        raise HTTPException(status_code=403, detail="Forbidden")
    if not original_full_path.exists():
        raise HTTPException(status_code=404, detail="Original PDF not found")

    # Create a unique cache key for this preview
    pages_key = "_".join(str(p) for p in page_numbers)
    cache_full_path = (CACHE_DIR / f"pdf_preview_{width}x{height}_{pdf_path}_pages{pages_key}.jpg").resolve()
    cache_full_path.parent.mkdir(parents=True, exist_ok=True)

    if cache_full_path.exists():
        return FileResponse(cache_full_path, media_type="image/jpeg")

    try:
        pdf_document = fitz.open(original_full_path)

        # Create a combined image for all requested pages
        preview_images = []

        for page_num in page_numbers:
            if page_num >= len(pdf_document):
                continue

            pdf_page = pdf_document[page_num]
            mat = fitz.Matrix(1.5, 1.5)
            pix = pdf_page.get_pixmap(matrix=mat)

            img_data = pix.tobytes("ppm")
            pil_image = PILImage.open(io.BytesIO(img_data))
            pil_image.thumbnail((width, height), PILImage.Resampling.LANCZOS)

            preview_images.append(pil_image)

        if not preview_images:
            raise HTTPException(status_code=400, detail="No valid pages found")

        # Create combined preview (for now, just return first page)
        # You can enhance this to create a grid of multiple pages
        combined_image = preview_images[0]

        # Save combined preview
        combined_image.save(cache_full_path, "JPEG", quality=85)
        pdf_document.close()

        return FileResponse(cache_full_path, media_type="image/jpeg")

    except Exception as e:
        raise HTTPException(status_code=500, detail=f"PDF preview error: {str(e)}")

# ---------------------------
# File Information Endpoint
# ---------------------------
@app.get("/info/{file_path:path}")
async def get_file_info(file_path: str):
    original_full_path = (ORIGINALS_DIR / file_path).resolve()

    if not _safe_within_base(original_full_path):
        raise HTTPException(status_code=403, detail="Forbidden")
    if not original_full_path.exists():
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
                ffmpeg_bin = _resolve_ffmpeg_binary()
                command = [
                    ffmpeg_bin, "-i", str(original_full_path),
                    "-hide_banner"
                ]
                result = subprocess.run(command, capture_output=True, text=True)
                # Parse FFmpeg output for video info (simplified)
                info["video_info"] = "Available (needs parsing)"
            except Exception:
                pass

        return info

    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error getting file info: {str(e)}")

# ---------------------------
# Delete Endpoint (Enhanced)
# ---------------------------
@app.delete("/delete/{asset_path:path}")
async def delete_asset(asset_path: str, api_key: str = Depends(verify_api_key)):
    decoded = unquote(unquote(asset_path))
    original_full_path = (ORIGINALS_DIR / decoded).resolve()

    if not _safe_within_base(original_full_path):
        raise HTTPException(status_code=403, detail="Forbidden")
    if not original_full_path.exists():
        raise HTTPException(status_code=404, detail="Original file not found")

    # Attempt to delete original
    try:
        original_parent = original_full_path.parent
        original_full_path.unlink()
        _prune_empty_parents(original_parent, ORIGINALS_DIR)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to delete original: {str(e)}")

    # Delete cached derivatives
    deleted_cache = 0
    try:
        rel_decoded_posix = Path(decoded).as_posix()

        # Build patterns for all cached file types
        patterns = [
            rel_decoded_posix,  # Original processed images
            Path(rel_decoded_posix).with_suffix(".webp").as_posix(),
            Path(rel_decoded_posix).with_suffix(".jpg").as_posix(),
            Path(rel_decoded_posix).with_suffix(".png").as_posix(),
        ]

        # Add video thumbnail patterns
        video_safe_stem = _sanitize_video_path(rel_decoded_posix)
        patterns.append(f"{video_safe_stem}.jpg")

        # Add PDF thumbnail patterns
        patterns.append(f"pdf_thumb_.*_{rel_decoded_posix}.*\\.jpg")
        patterns.append(f"pdf_preview_.*_{rel_decoded_posix}.*\\.jpg")

        for p in CACHE_DIR.rglob("*"):
            if not p.is_file():
                continue
            sp = p.as_posix()
            if any(pattern in sp for pattern in patterns):
                try:
                    parent_dir = p.parent
                    p.unlink()
                    deleted_cache += 1
                    _prune_empty_parents(parent_dir, CACHE_DIR)
                except Exception:
                    pass

        # Clean thumbnails directory too
        # Thumbnails are stored as: thumb_{width}x{height}_{image_path}.webp
        # Only delete specific thumbnail files, not directories (like cache deletion)
        for p in THUMBNAILS_DIR.rglob("*"):
            if not p.is_file():
                continue
            try:
                # Get relative path from THUMBNAILS_DIR
                rel_thumb_path = p.relative_to(THUMBNAILS_DIR).as_posix()

                # Check if this is a thumbnail file matching our pattern
                # Pattern: thumb_{width}x{height}_{original_path}.webp
                if rel_thumb_path.startswith("thumb_") and rel_thumb_path.endswith(".webp"):
                    # Extract the path part after thumb_{width}x{height}_
                    # Example: "thumb_150x150_testing/image.webp"
                    parts = rel_thumb_path.split("_", 2)
                    if len(parts) >= 3:
                        # parts[0] = "thumb"
                        # parts[1] = "150x150" (or similar)
                        # parts[2] = "testing/image.webp"
                        thumb_path_part = parts[2]

                        # Remove .webp extension
                        if thumb_path_part.endswith(".webp"):
                            thumb_path_part = thumb_path_part[:-5]  # Remove .webp

                        # Normalize both paths for comparison
                        # Remove file extensions from both paths since thumbnail is always .webp
                        thumb_path_normalized = thumb_path_part.strip("/")

                        # Remove extension from decoded path for comparison
                        decoded_path_obj = Path(rel_decoded_posix)
                        decoded_path_normalized = (decoded_path_obj.parent / decoded_path_obj.stem).as_posix().strip("/")

                        # Only delete if paths match exactly (ignoring file extensions)
                        if thumb_path_normalized == decoded_path_normalized:
                            parent_dir = p.parent
                            p.unlink()
                            deleted_cache += 1
                            _prune_empty_parents(parent_dir, THUMBNAILS_DIR)
            except (ValueError, Exception):
                # Fallback: if path parsing fails, check if decoded path (without extension) appears in thumbnail path
                try:
                    decoded_path_obj = Path(rel_decoded_posix)
                    decoded_path_no_ext = (decoded_path_obj.parent / decoded_path_obj.stem).as_posix()
                    sp = p.as_posix()
                    # Check if the path without extension matches
                    if decoded_path_no_ext in sp and p.is_file():
                        parent_dir = p.parent
                        p.unlink()
                        deleted_cache += 1
                        _prune_empty_parents(parent_dir, THUMBNAILS_DIR)
                except Exception:
                    pass

    except Exception:
        pass

    return {"message": "Delete successful", "deleted_cache_files": deleted_cache}

# ---------------------------
# List Files Endpoint (NEW)
# ---------------------------
@app.get("/list/{section:path}")
async def list_files(
    section: str,
    api_key: str = Depends(verify_api_key),
    page: int = Query(1, ge=1, description="Page number"),
    limit: int = Query(50, ge=1, le=100, description="Items per page")
):
    """
    List all files in a specific section with pagination and file metadata
    """
    section_dir = ORIGINALS_DIR / section

    if not section_dir.exists():
        raise HTTPException(status_code=404, detail=f"Section '{section}' not found")

    if not _safe_within_base(section_dir):
        raise HTTPException(status_code=403, detail="Forbidden")

    try:
        # Get all files recursively in the section
        all_files = []
        for file_path in section_dir.rglob("*"):
            if file_path.is_file():
                try:
                    file_stats = file_path.stat()
                    relative_path = file_path.relative_to(section_dir)

                    # Get file type
                    file_type = get_file_type(file_path.name)

                    # Generate URLs
                    file_url_path = f"{section}/{relative_path}"
                    original_url = f"{VPS_BASE_URL}/originals/{quote(str(file_url_path))}"

                    # Generate appropriate processed URLs based on file type
                    if file_type == "image":
                        processed_url = f"{VPS_BASE_URL}/process/300/300/{quote(str(file_url_path))}"
                        thumbnail_url = f"{VPS_BASE_URL}/thumbnail/150/150/{quote(str(file_url_path))}"
                    elif file_type == "video":
                        processed_url = f"{VPS_BASE_URL}/process/video/thumbnail/300x300/{quote(str(file_url_path))}"
                        thumbnail_url = f"{VPS_BASE_URL}/process/video/thumbnail/150x150/{quote(str(file_url_path))}"
                    elif file_type == "pdf":
                        processed_url = f"{VPS_BASE_URL}/process/pdf/thumbnail/300x300/{quote(str(file_url_path))}"
                        thumbnail_url = f"{VPS_BASE_URL}/process/pdf/thumbnail/150x150/{quote(str(file_url_path))}"
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
                            "delete": f"{VPS_BASE_URL}/delete/{quote(str(file_url_path))}"
                        }
                    }

                    # Add type-specific metadata
                    if file_type == "image":
                        try:
                            image = pyvips.Image.new_from_file(str(file_path))
                            file_info.update({
                                "metadata": {
                                    "width": image.width,
                                    "height": image.height,
                                    "format": image.format,
                                    "bands": image.bands
                                }
                            })
                        except Exception:
                            file_info["metadata"] = {"error": "Could not read image metadata"}

                    elif file_type == "pdf":
                        try:
                            pdf_document = fitz.open(str(file_path))
                            file_info.update({
                                "metadata": {
                                    "page_count": len(pdf_document),
                                    "is_encrypted": pdf_document.is_encrypted
                                }
                            })
                            pdf_document.close()
                        except Exception:
                            file_info["metadata"] = {"error": "Could not read PDF metadata"}

                    all_files.append(file_info)

                except Exception as e:
                    # Skip files that can't be processed but continue with others
                    print(f"Error processing file {file_path}: {e}")
                    continue

        # Sort files by modification time (newest first)
        all_files.sort(key=lambda x: x["modified_time"], reverse=True)

        # Pagination
        total_files = len(all_files)
        total_pages = (total_files + limit - 1) // limit
        start_idx = (page - 1) * limit
        end_idx = start_idx + limit
        paginated_files = all_files[start_idx:end_idx]

        return {
            "section": section,
            "total_files": total_files,
            "total_pages": total_pages,
            "current_page": page,
            "limit": limit,
            "files": paginated_files
        }

    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error listing files: {str(e)}")


# ---------------------------
# List Sections Endpoint (NEW)
# ---------------------------
@app.get("/sections")
async def list_sections(api_key: str = Depends(verify_api_key)):
    """
    List all available sections (subdirectories in originals)
    """
    try:
        sections = []
        for item in ORIGINALS_DIR.iterdir():
            if item.is_dir():
                # Count files in section
                file_count = sum(1 for _ in item.rglob("*") if _.is_file())

                # Get section size
                section_size = sum(f.stat().st_size for f in item.rglob("*") if f.is_file())

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

    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error listing sections: {str(e)}")

# ---------------------------
# Health Check
# ---------------------------
@app.get("/health")
async def health_check():
    return {
        "status": "healthy",
        "service": "Impexinfo Media Processor",
        "supported_formats": {
            "images": list(SUPPORTED_IMAGE_FORMATS),
            "videos": list(SUPPORTED_VIDEO_FORMATS),
            "documents": list(SUPPORTED_DOCUMENT_FORMATS)
        }
    }
