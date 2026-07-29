<div align="center">

# Tixa

### Your media infrastructure, on your own VPS

Self-hosted image, video, PDF, and audio processing with automatic HTTPS,
on-demand transformations, caching, and a friendly server-management CLI.

[![License: MIT](https://img.shields.io/badge/License-MIT-22c55e.svg)](LICENSE)
[![Python](https://img.shields.io/badge/Python-3.8%2B-3776AB?logo=python&logoColor=white)](https://www.python.org/)
[![FastAPI](https://img.shields.io/badge/FastAPI-powered-009688?logo=fastapi&logoColor=white)](https://fastapi.tiangolo.com/)
[![Platform](https://img.shields.io/badge/Platform-Ubuntu%20%7C%20Debian-E95420?logo=ubuntu&logoColor=white)](#requirements)

**[Quick start](#quick-start) · [Features](#features) · [API](#api-reference) · [CLI](#cli-reference) · [Contributing](CONTRIBUTING.md)**

</div>

---

## Why Tixa?

Tixa turns a fresh VPS into a private media service. Upload an original once,
then request resized images, thumbnails, video frames, PDF previews, audio
waveforms, or converted audio through predictable URLs. Generated assets are
cached on disk for fast repeat requests.

- **Own your data** — files remain on infrastructure you control.
- **No per-request fee** — Tixa is free and open source under the MIT License.
- **Production setup included** — Nginx, systemd, API keys, and Let's Encrypt.
- **Multiple services** — host separate projects and domains on one VPS.
- **Simple operations** — create, verify, update, migrate, rotate keys, or remove
  services from one CLI.

You still pay your own VPS, domain, storage, and bandwidth costs.

## Features

| Capability | What Tixa provides |
|---|---|
| Images | Resize, crop, optimize, thumbnail, and convert to WebP/JPEG/PNG |
| Video | Extract cached JPEG thumbnails at a chosen timestamp with FFmpeg |
| PDF | Generate page thumbnails and multi-page previews |
| Audio | Stream, convert formats, extract metadata, and generate waveforms |
| Storage | Original files plus separate derivative caches and thumbnails |
| Delivery | Nginx reverse proxy, long-lived cache headers, and automatic HTTPS |
| Security | Generated API keys, protected writes, and path traversal checks |
| Operations | Health checks, backups, updates, migrations, and key rotation |

### Supported formats

| Media | Formats |
|---|---|
| Images | JPG, JPEG, PNG, WebP, GIF, BMP, TIFF, TIF, SVG |
| Video | MP4, MOV, AVI, MKV, WebM, FLV, WMV, M4V, 3GP |
| Documents | PDF, DOC, DOCX, TXT, RTF |
| Audio | MP3, WAV, FLAC, AAC, OGG, OGA, M4A, WMA, OPUS, AIFF |

> Some document formats can be stored and listed, while PDF has dedicated
> rendering endpoints.

## Requirements

Tixa currently targets a dedicated or compatible VPS with:

- Ubuntu or Debian
- Root or `sudo` access
- systemd running as PID 1
- A public IPv4 address
- A real domain with an `A` record pointing to the VPS
- Inbound ports `80` and `443`
- No active Apache, Caddy, or Lighttpd conflict

The installer checks compatibility first, simulates package installation, and
then installs only missing packages. It manages Python, Nginx, Certbot, FFmpeg,
libvips, and supporting command-line tools.

Tixa does not automatically stop or reconfigure another web server.

## Quick start

### 1. Point a domain to the VPS

Create a public DNS record before creating a service:

```text
Type: A
Name: img
Value: YOUR_VPS_PUBLIC_IP
```

For example, `img.example.com` must resolve directly to the VPS. Private names
such as `.local` cannot receive Let's Encrypt certificates.

### 2. Install Tixa

Install directly without keeping a repository clone:

```bash
curl -fsSL https://raw.githubusercontent.com/Kayease/tixa/main/bootstrap.sh | sudo bash
```

Because this executes a remote script as root, security-conscious users should
download and inspect it first:

```bash
curl -fsSLO https://raw.githubusercontent.com/Kayease/tixa/main/bootstrap.sh
less bootstrap.sh
sudo bash bootstrap.sh
rm bootstrap.sh
```

To install a tagged release instead of the latest `main` branch:

```bash
curl -fsSL https://raw.githubusercontent.com/Kayease/tixa/main/bootstrap.sh \
  | sudo TIXA_VERSION=v1.0.0 bash
```

For unattended provisioning, supply the certificate email explicitly:

```bash
curl -fsSL https://raw.githubusercontent.com/Kayease/tixa/main/bootstrap.sh \
  | sudo TIXA_SSL_EMAIL=admin@example.com bash
```

Alternatively, install from a clone:

```bash
git clone https://github.com/Kayease/tixa.git
cd tixa
sudo bash install.sh
```

The clone can be located anywhere. Runtime files are installed in `/opt/tixa`,
while persistent state is stored separately in `/var/lib/tixa`.

### 3. Check the server

```bash
sudo tixa doctor
```

A compatible server reports:

```text
READY: this server is compatible with Tixa
```

### 4. Create a service

```bash
sudo tixa create
```

Enter a project name and domain, review the generated port and API key, then
type `CREATE`. Tixa creates the Python environment, storage, systemd unit,
Nginx site, and HTTPS certificate.

### 5. Verify it

```bash
sudo tixa list
sudo tixa verify your-project
curl https://img.example.com/health
```

Interactive API documentation is available at:

```text
https://img.example.com/docs
```

## Five-minute API tour

Set your service values:

```bash
export TIXA_URL="https://img.example.com"
export TIXA_API_KEY="replace-with-your-api-key"
```

### Upload a file

Uploads and deletes require the `X-API-Key` header:

```bash
curl -X POST "$TIXA_URL/upload/products" \
  -H "X-API-Key: $TIXA_API_KEY" \
  -F "file=@product.jpg"
```

The response includes the original, processed, and thumbnail URLs.

### Resize an image

```text
GET /process/800/600/products/product.jpg?quality=85&format=webp
```

### Generate an image thumbnail

```text
GET /thumbnail/300/300/products/product.jpg
```

### Extract a video thumbnail

Square shorthand:

```text
GET /process/video/thumbnail/300/videos/demo.mp4
```

Explicit dimensions and timestamp:

```text
GET /process/video/thumbnail/640x360/videos/demo.mp4?timestamp=00:00:05
```

The source path may end in `.mp4`, but the response is an inline JPEG with
`Content-Type: image/jpeg`.

### Generate a PDF thumbnail

```text
GET /process/pdf/thumbnail/600x800/documents/catalog.pdf?page=0
```

### Generate an audio waveform

```text
GET /process/audio/waveform/800x200/podcasts/episode.mp3?color=blue
```

### Stream or convert audio

```text
GET /stream/audio/podcasts/episode.mp3
GET /process/audio/convert/mp3/podcasts/episode.wav?bitrate=320k
```

## API reference

| Method | Endpoint | Purpose | API key |
|---|---|---|---|
| `POST` | `/upload/{section}` | Upload a supported file | Required |
| `GET` | `/originals/{path}` | Serve an original file through Nginx | No |
| `GET` | `/process/{width}/{height}/{path}` | Resize or convert an image | No |
| `GET` | `/thumbnail/{width}/{height}/{path}` | Create an image thumbnail | No |
| `GET` | `/process/video/thumbnail/{size}/{path}` | Extract a video frame | No |
| `GET` | `/process/pdf/thumbnail/{size}/{path}` | Render a PDF page thumbnail | No |
| `GET` | `/process/pdf/preview/{path}` | Generate a PDF preview | No |
| `GET` | `/process/audio/waveform/{size}/{path}` | Generate an audio waveform | No |
| `GET` | `/stream/audio/{path}` | Stream audio with the correct MIME type | No |
| `GET` | `/process/audio/convert/{format}/{path}` | Convert and cache audio | No |
| `GET` | `/info/{path}` | Read file and media metadata | No |
| `GET` | `/list/{section}` | List files in a section | No |
| `GET` | `/sections` | List storage sections | No |
| `DELETE` | `/delete/{path}` | Delete an original and derivatives | Required |
| `GET` | `/health` | Check service health | No |

Use `/docs` on a running service for its generated OpenAPI interface. More
audio examples are available in the [audio API guide](docs/audio-api.md).

## CLI reference

### Service management

| Command | Purpose |
|---|---|
| `sudo tixa doctor` | Check OS, packages, ports, web server, and SSL tooling |
| `sudo tixa create` | Create a media service interactively |
| `sudo tixa list` | List services, domains, ports, and API keys |
| `sudo tixa verify NAME` | Verify systemd, Nginx, port, and health status |
| `sudo tixa delete NAME` | Permanently delete a service and its media |
| `sudo tixa migrate NAME` | Rename a service and migrate it to a new domain |

### Updates and backups

```bash
# Update the CLI and templates
sudo tixa self-update

# Deploy the latest template to one service
sudo tixa update my-service

# Update every service
sudo tixa update --all

# Do not create a new rollback archive
sudo tixa update my-service --skip-backup
sudo tixa update --all --skip-backup

# Non-interactive update
sudo tixa update --all --skip-backup --yes
```

Update archives are stored under `/var/backups/tixa-updates`. Skipping a backup
does not delete archives from earlier updates.

### API keys and SSL

```bash
sudo tixa apikey rotate my-service
sudo tixa apikey rotate --all
sudo tixa sslemail show
sudo tixa sslemail set
sudo tixa ssl renew my-service
sudo tixa ssl renew --all
```

Key rotation validates and health-checks the service before committing the new
key. A successful rotation immediately invalidates the previous key.

### Uninstall

```bash
# Remove only the Tixa CLI/runtime; keep services and state
sudo tixa uninstall

# Permanently remove Tixa, registered services, state, and media
sudo tixa uninstall --hard
```

The hard uninstall and `tixa delete` are destructive. Back up originals first.

## Service migration

Point the new domain to the VPS, then run:

```bash
sudo tixa migrate current-service
```

Migration preserves the API key and internal port, creates a validated runtime,
obtains the new certificate before cutover, renames the media folder and
systemd service, checks health, and retains a rollback copy under
`/var/backups/tixa-migrations`.

## Filesystem layout

```text
/opt/tixa/                         Installed CLI and templates
/var/lib/tixa/                     Persistent registry and SSL email
/var/backups/tixa-updates/         Service update archives
/var/backups/tixa-migrations/      Migration rollback copies
/opt/<project>-processor/          Generated application and virtualenv
/var/www/images/<project>/
├── originals/                     Uploaded source files
├── cache/                         Generated and converted assets
└── thumbnails/                    Image thumbnails
```

## Architecture

```text
Client
  │ HTTPS
  ▼
Nginx + Let's Encrypt
  ├── /originals/* ───────────────► Original file storage
  └── API and processing routes
                 │
                 ▼
          FastAPI service
          ├── libvips ────────────► Images
          ├── FFmpeg ─────────────► Video and audio
          ├── PyMuPDF ────────────► PDF
          └── cache directories ──► Reusable derivatives
```

Each project runs as its own systemd service on a generated local port.

## Security notes

- Keep `/var/lib/tixa/registry.json` private; it contains service API keys.
- Upload and delete operations use `X-API-Key`; public read endpoints are
  intentional for media delivery.
- Rotate a key immediately if it appears in logs, screenshots, or chat.
- Keep Ubuntu/Debian and Tixa updated.
- Back up `/var/www/images` and `/var/lib/tixa` regularly.
- Configure firewall access for SSH, HTTP, and HTTPS only as appropriate.
- Tixa currently generates services that run as `root`; review this before
  using Tixa in a high-security or multi-tenant environment.

Please report vulnerabilities privately according to [SECURITY.md](SECURITY.md).

## Troubleshooting

```bash
# General compatibility
sudo tixa doctor

# Service status
sudo tixa verify my-service
sudo systemctl status my-service-processor --no-pager -l

# Recent application logs
sudo journalctl -u my-service-processor -n 100 --no-pager

# Nginx validation
sudo nginx -t

# Internal health check (use the port from tixa list)
curl http://127.0.0.1:PORT/health
```

When a public request fails but the internal health check succeeds, inspect
Nginx, DNS, firewall, and any CDN cache in front of the VPS.

## Documentation

- [Documentation index](docs/README.md)
- [Audio API guide](docs/audio-api.md)
- [Audio processing architecture](docs/audio-architecture.md)
- [Contributing](CONTRIBUTING.md)
- [Security policy](SECURITY.md)

## Contributing

Bug reports, documentation improvements, and code contributions are welcome.
Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request and use the
provided GitHub issue templates when possible.

## License

Tixa is free and open-source software licensed under the
[MIT License](LICENSE).

Copyright © 2026 Kayease.
