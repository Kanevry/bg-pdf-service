#!/usr/bin/env bash
# One-Line Server Setup for BG PDF Service
#
# Installs and configures bg-pdf-service on a fresh Ubuntu/Debian server.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/Kanevry/bg-pdf-service/main/scripts/setup.sh | bash
#
# Or manual:
#   wget -qO- https://raw.githubusercontent.com/Kanevry/bg-pdf-service/main/scripts/setup.sh | bash
#
# What it does:
#   1. Installs Docker + Docker Compose if not present
#   2. Clones/updates repo to /opt/bg-pdf-service
#   3. Creates .env from .env.example
#   4. Starts services via docker compose
#   5. Installs and enables systemd service
#   6. Verifies health check

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

INSTALL_DIR="/opt/bg-pdf-service"
REPO_URL="https://github.com/Kanevry/bg-pdf-service.git"
SYSTEMD_SERVICE="/etc/systemd/system/bg-pdf-service.service"
HEALTH_CHECK_RETRIES=5
HEALTH_CHECK_DELAY=5

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

error() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
  exit 1
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# ============================================================================
# ROOT CHECK
# ============================================================================

if [[ $EUID -ne 0 ]]; then
  error "This script must be run as root (use sudo)"
fi

log "Starting BG PDF Service setup..."

# ============================================================================
# INSTALL DOCKER
# ============================================================================

if ! command_exists docker; then
  log "Docker not found, installing..."

  # Update package index
  apt-get update -qq

  # Install prerequisites
  apt-get install -y -qq \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

  # Add Docker GPG key
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg

  # Add Docker repository
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

  # Install Docker Engine
  apt-get update -qq
  apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  log "✓ Docker installed successfully"
else
  log "✓ Docker already installed ($(docker --version))"
fi

# Verify Docker Compose plugin
if ! docker compose version >/dev/null 2>&1; then
  error "Docker Compose plugin not available. Install with: apt-get install docker-compose-plugin"
fi

log "✓ Docker Compose plugin available ($(docker compose version))"

# ============================================================================
# CLONE/UPDATE REPOSITORY
# ============================================================================

if [[ -d "$INSTALL_DIR" ]]; then
  log "Repository exists at $INSTALL_DIR, updating..."
  cd "$INSTALL_DIR"

  # Stash any local changes
  git stash --quiet || true

  # Pull latest
  git pull --quiet origin main || error "Failed to update repository"

  log "✓ Repository updated"
else
  log "Cloning repository to $INSTALL_DIR..."

  # Create parent directory
  mkdir -p "$(dirname "$INSTALL_DIR")"

  # Clone repository
  git clone --quiet "$REPO_URL" "$INSTALL_DIR" || error "Failed to clone repository"

  cd "$INSTALL_DIR"
  log "✓ Repository cloned"
fi

# ============================================================================
# CONFIGURE ENVIRONMENT
# ============================================================================

if [[ ! -f "$INSTALL_DIR/.env" ]]; then
  log "Creating .env from .env.example..."

  if [[ ! -f "$INSTALL_DIR/.env.example" ]]; then
    error ".env.example not found in repository"
  fi

  cp "$INSTALL_DIR/.env.example" "$INSTALL_DIR/.env"
  log "✓ .env created (customize if needed)"
else
  log "✓ .env already exists"
fi

# ============================================================================
# START DOCKER COMPOSE SERVICES
# ============================================================================

log "Starting services with docker compose..."

# Pull latest images
docker compose pull --quiet

# Start services
docker compose up -d --remove-orphans

log "✓ Services started"

# ============================================================================
# WAIT FOR HEALTH CHECK
# ============================================================================

log "Waiting for service to become healthy (up to $((HEALTH_CHECK_RETRIES * HEALTH_CHECK_DELAY))s)..."

HEALTH_CHECK_PASSED=false

for i in $(seq 1 $HEALTH_CHECK_RETRIES); do
  log "Health check attempt $i/$HEALTH_CHECK_RETRIES..."

  if bash "$INSTALL_DIR/scripts/health-check.sh" >/dev/null 2>&1; then
    HEALTH_CHECK_PASSED=true
    break
  fi

  if [[ $i -lt $HEALTH_CHECK_RETRIES ]]; then
    sleep $HEALTH_CHECK_DELAY
  fi
done

if [[ "$HEALTH_CHECK_PASSED" == "false" ]]; then
  error "Service did not become healthy. Check logs: docker compose logs"
fi

log "✓ Service is healthy"

# ============================================================================
# INSTALL SYSTEMD SERVICE
# ============================================================================

log "Installing systemd service..."

# Copy service file
if [[ ! -f "$INSTALL_DIR/systemd/bg-pdf-service.service" ]]; then
  error "systemd/bg-pdf-service.service not found in repository"
fi

cp "$INSTALL_DIR/systemd/bg-pdf-service.service" "$SYSTEMD_SERVICE"

# Reload systemd
systemctl daemon-reload

# Enable service (start on boot)
systemctl enable bg-pdf-service.service

# Start service (redundant but ensures systemd tracking)
systemctl start bg-pdf-service.service

log "✓ Systemd service installed and enabled"

# ============================================================================
# SUCCESS SUMMARY
# ============================================================================

log ""
log "════════════════════════════════════════════════════════════════"
log "✅ BG PDF Service setup complete!"
log "════════════════════════════════════════════════════════════════"
log ""
log "Service Details:"
log "  Install Directory:  $INSTALL_DIR"
log "  Systemd Service:    bg-pdf-service.service"
log "  Gotenberg URL:      http://localhost:3001"
log ""
log "Management Commands:"
log "  sudo systemctl status bg-pdf-service   # Check status"
log "  sudo systemctl restart bg-pdf-service  # Restart service"
log "  sudo systemctl stop bg-pdf-service     # Stop service"
log "  docker compose logs -f                 # View logs (in $INSTALL_DIR)"
log ""
log "Health Check:"
log "  bash $INSTALL_DIR/scripts/health-check.sh"
log "  bash $INSTALL_DIR/scripts/health-check.sh --full"
log ""
log "Configuration:"
log "  Edit: $INSTALL_DIR/.env"
log "  Apply changes: sudo systemctl restart bg-pdf-service"
log ""
log "════════════════════════════════════════════════════════════════"

exit 0
