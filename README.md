<p align="center">
  <h1 align="center">bg-pdf-service</h1>
  <p align="center">Self-hosted HTML-to-PDF service powered by Gotenberg.<br/>One command. Production ready. Zero vendor lock-in.</p>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green" alt="MIT License" /></a>
  <a href="https://hub.docker.com/r/gotenberg/gotenberg"><img src="https://img.shields.io/badge/Gotenberg-v8-blue" alt="Gotenberg v8" /></a>
  <a href="https://hub.docker.com/r/gotenberg/gotenberg"><img src="https://img.shields.io/docker/image-size/gotenberg/gotenberg/8?label=image%20size" alt="Docker Image Size" /></a>
</p>

---

## Why

Cloud PDF APIs charge per conversion. Self-hosting is cheaper and gives you full control.

| Provider | Cost | Control | Privacy |
|----------|------|---------|---------|
| PDFShift | ~$24/month | API-dependent | Data leaves your server |
| DocRaptor | ~$29/month | API-dependent | Data leaves your server |
| **bg-pdf-service** | **~$4/month** (any VPS) | **Full control** | **Your server, your data** |

## Quick Start

```bash
git clone https://github.com/Kanevry/bg-pdf-service.git
cd bg-pdf-service
cp .env.example .env
# Edit .env with your basic auth credentials
docker compose up -d
```

Verify it works:

```bash
# With basic auth
curl -sf -u "your-username:your-password" http://localhost:3001/health
# {"status":"up"}
```

Convert HTML to PDF:

```bash
echo '<h1>Hello, World!</h1>' > index.html
curl -sf -u "your-username:your-password" \
  -F files=@index.html \
  http://localhost:3001/forms/chromium/convert/html \
  -o output.pdf
```

## Features

- **Gotenberg v8** -- Chromium + LibreOffice under the hood
- **Three-layer security** -- TLS + Bearer Token + Basic Auth
- **Localhost-only binding** -- Docker port bound to 127.0.0.1
- **Caddy reverse proxy** -- Auto-TLS, security headers, rate limiting
- **Docker hardening** -- no-new-privileges, resource limits, tmpfs
- **systemd service** -- Auto-start on boot, auto-restart on failure
- **Health checks** -- Container-level and application-level monitoring
- **Memory limits** -- 2GB cap with 512MB reservation (prevents OOM)
- **Secrets protection** -- Pre-commit hooks prevent accidental credential leaks

## Security Architecture

```
Client (HTTPS)
    |
    v
[Caddy Reverse Proxy]     Port 443 (TLS 1.3, auto-cert via Let's Encrypt)
    |  - Bearer Token validation
    |  - Security headers (HSTS, X-Frame-Options, CSP)
    |  - Request size limit (50MB)
    |  - /health passes through without auth
    v
[Gotenberg v8]             Port 3001 (localhost only, 127.0.0.1)
    |  - Basic Auth (username + password)
    |  - JS disabled, download-from disabled
    |  - Chromium sandboxed, cache cleared per request
    v
[PDF Output]
```

### Three-Layer Authentication

| Layer | Component | Auth Method | Purpose |
|-------|-----------|-------------|---------|
| 1 | Caddy | Bearer Token | API key validation, TLS termination |
| 2 | Gotenberg | Basic Auth | Defense-in-depth, direct access protection |
| 3 | Docker | localhost bind | Network isolation, no external port exposure |

### Security Hardening

- **TLS 1.3** with auto-renewed Let's Encrypt certificates
- **HSTS** with 1-year max-age
- **no-new-privileges** Docker security option
- **Chromium sandboxed** with JS disabled and cache/cookies cleared per request
- **Download-from disabled** (prevents SSRF attacks)
- **Webhooks disabled** (reduces attack surface)
- **UFW firewall**: Only ports 22 (SSH) and 443 (HTTPS) open

## API Endpoints

bg-pdf-service exposes the native Gotenberg API:

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/forms/chromium/convert/html` | POST | Convert HTML file to PDF |
| `/forms/chromium/convert/url` | POST | Convert URL to PDF |
| `/forms/chromium/convert/markdown` | POST | Convert Markdown to PDF |
| `/forms/libreoffice/convert` | POST | Convert Office documents (docx, xlsx, pptx) to PDF |
| `/forms/chromium/screenshot/html` | POST | Take screenshot of HTML |
| `/health` | GET | Health check (no auth required) |

### Example: HTML to PDF with Bearer Token

```bash
curl \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -F files=@index.html \
  -F marginTop=0.5 \
  -F marginBottom=0.5 \
  -F paperWidth=8.27 \
  -F paperHeight=11.69 \
  -F printBackground=true \
  https://pdf.example.com/forms/chromium/convert/html \
  -o document.pdf
```

For the full API reference, see the [Gotenberg documentation](https://gotenberg.dev/docs/getting-started).

## Configuration

### Environment Variables (.env)

| Variable | Default | Description |
|----------|---------|-------------|
| `GOTENBERG_PORT` | `3001` | Host port mapping (bound to 127.0.0.1) |
| `GOTENBERG_API_BASIC_AUTH_USERNAME` | - | Basic auth username (required) |
| `GOTENBERG_API_BASIC_AUTH_PASSWORD` | - | Basic auth password (required) |
| `CHROMIUM_RESTART_AFTER` | `50` | Restart Chromium after N conversions (prevents memory leaks) |
| `CHROMIUM_AUTO_START` | `true` | Start Chromium on boot (faster first request) |
| `LOG_LEVEL` | `info` | Log verbosity: `error`, `warn`, `info`, `debug` |
| `API_TIMEOUT` | `120s` | Maximum time for a single conversion request |

### Reverse Proxy (Caddy)

A `Caddyfile.example` is included for setting up Caddy as a reverse proxy with:
- Auto-TLS via Let's Encrypt
- Bearer Token authentication
- Security headers
- Request size limits
- Access logging

```bash
sudo cp Caddyfile.example /etc/caddy/Caddyfile
# Edit with your domain, Bearer Token, and Basic Auth credentials
sudo systemctl reload caddy
```

## Production Deployment

### Option 1: One-line setup (recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/Kanevry/bg-pdf-service/main/scripts/setup.sh | bash
```

This installs Docker (if needed), clones the repo, starts the service, and enables auto-start.

### Option 2: Manual setup

```bash
# 1. Clone repository
git clone https://github.com/Kanevry/bg-pdf-service.git /opt/bg-pdf-service

# 2. Configure environment
cd /opt/bg-pdf-service
cp .env.example .env
nano .env  # Set basic auth credentials

# 3. Start the service
docker compose up -d

# 4. Install systemd service (auto-start on boot)
cp systemd/bg-pdf-service.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable bg-pdf-service
systemctl start bg-pdf-service

# 5. Install Caddy reverse proxy (optional, for external access)
cp Caddyfile.example /etc/caddy/Caddyfile
# Edit Caddyfile with your domain and credentials
systemctl reload caddy

# 6. Verify
curl -sf http://localhost:3001/health  # Direct (localhost only)
curl -sf https://pdf.example.com/health  # Via Caddy (if configured)
```

### Recommended Server Specs

| Spec | Minimum | Recommended |
|------|---------|-------------|
| CPU | 1 vCPU | 2 vCPU |
| RAM | 2 GB | 4 GB |
| Disk | 10 GB | 20 GB |
| OS | Ubuntu 22.04+ | Ubuntu 24.04 |

Gotenberg uses ~1.5 GB RAM (Chromium + LibreOffice). A 4 GB VPS (~$4/month) is the sweet spot.

## Health Monitoring

### Basic health check

```bash
./scripts/health-check.sh
# OK: Gotenberg is healthy (chromium: up, libreoffice: up)
```

### JSON output (for monitoring systems)

```bash
./scripts/health-check.sh --json
# {"status":"healthy","chromium":"up","libreoffice":"up","timestamp":"2026-02-07T22:00:00Z"}
```

### Full check with PDF test

```bash
./scripts/health-check.sh --full
# OK: Gotenberg is healthy, PDF generation verified
```

### Cron-based monitoring

```bash
# Check every 5 minutes, alert on failure
*/5 * * * * /opt/bg-pdf-service/scripts/health-check.sh || echo "PDF Service DOWN" | mail -s "Alert" admin@example.com
```

## Development

For local development with debug logging:

```bash
docker compose -f docker-compose.dev.yml up
```

## Service Management

```bash
# Start
systemctl start bg-pdf-service

# Stop
systemctl stop bg-pdf-service

# Restart
systemctl restart bg-pdf-service

# Status
systemctl status bg-pdf-service

# Logs
docker compose logs -f gotenberg
```

## Contributing

Contributions are welcome! Please open an issue or submit a pull request.

## License

[MIT](LICENSE) -- Bernhard Goetzendorfer
