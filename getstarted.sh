#!/bin/bash
# =============================================================================
# EdgeTelemetry - Get Started Script
# Validates mount points, installs all required software for deployment
# Target OS: Debian/Ubuntu, RHEL/Rocky/Alma/CentOS/Fedora, or SLES/openSUSE
# Usage:     sudo bash getstarted.sh
# =============================================================================

set -e

# -----------------------------------------------------------------------------
# Colours
# -----------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}    $1"; }
success() { echo -e "${GREEN}[OK]${NC}      $1"; }
warning() { echo -e "${YELLOW}[WARN]${NC}    $1"; }
error()   { echo -e "${RED}[ERROR]${NC}   $1"; exit 1; }
section() {
  echo ""
  echo -e "${CYAN}╔══════════════════════════════════════════════════╗${NC}"
  echo -e "${CYAN}║${NC}  $1"
  echo -e "${CYAN}╚══════════════════════════════════════════════════╝${NC}"
}

# --detect-only prints what this host was detected as and exits (no root needed)
DETECT_ONLY=false
[ "${1:-}" = "--detect-only" ] && DETECT_ONLY=true

if [ "$DETECT_ONLY" = false ] && [ "$EUID" -ne 0 ]; then
  error "Please run this script with sudo: sudo bash getstarted.sh"
fi

INVOKING_USER=${SUDO_USER:-$USER}

# =============================================================================
# SECTION 1 — Pre-flight Checks
# =============================================================================
section "Pre-flight Checks"

# OS_RELEASE is overridable so the detection matrix can be tested against fixtures
OS_RELEASE="${OS_RELEASE:-/etc/os-release}"
if [ -f "$OS_RELEASE" ]; then
  . "$OS_RELEASE"
  success "OS: $PRETTY_NAME"
else
  error "Cannot detect OS ($OS_RELEASE missing)."
fi

# -----------------------------------------------------------------------------
# Distro detection — family drives package manager, ID drives the Docker repo.
# Covers Ubuntu/Debian/Mint, RHEL/Rocky/Alma/CentOS/Fedora/Amazon, SLES/openSUSE.
# -----------------------------------------------------------------------------
case " ${ID:-} ${ID_LIKE:-} " in
  *" debian "*|*" ubuntu "*)          PKG_FAMILY=debian ;;
  *" rhel "*|*" centos "*|*" fedora "*) PKG_FAMILY=rhel ;;
  *" suse "*|*" sles "*|*" opensuse "*) PKG_FAMILY=suse ;;
  *) error "Unsupported distro: ${PRETTY_NAME:-unknown}. Supported families: debian, rhel, suse." ;;
esac

case "$PKG_FAMILY" in
  debian) PKG_MGR=apt-get ;;
  rhel)   PKG_MGR=$(command -v dnf > /dev/null && echo dnf || echo yum) ;;
  suse)   PKG_MGR=zypper ;;
esac

# Docker publishes repos per distro; map ours onto the closest one.
# Empty = no upstream repo, fall back to the distro's own docker package.
case "${ID:-}" in
  ubuntu)              DOCKER_REPO_OS=ubuntu ;;
  debian|raspbian)     DOCKER_REPO_OS=debian ;;
  linuxmint|pop)       DOCKER_REPO_OS=ubuntu ;;
  rhel)                DOCKER_REPO_OS=rhel ;;
  centos|rocky|almalinux|ol) DOCKER_REPO_OS=centos ;;
  fedora)              DOCKER_REPO_OS=fedora ;;
  sles|opensuse-leap)  DOCKER_REPO_OS=sles ;;
  *)                   DOCKER_REPO_OS="" ;;
esac

# Ubuntu derivatives report their own codename, which Docker's repo doesn't know
DEB_CODENAME="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"

success "Distro: ${ID:-unknown} (family: $PKG_FAMILY, package manager: $PKG_MGR)"

if [ "$DETECT_ONLY" = true ]; then
  echo "family=$PKG_FAMILY pkg=$PKG_MGR docker_repo=${DOCKER_REPO_OS:-none} codename=${DEB_CODENAME:-none}"
  exit 0
fi

pkg_refresh() {
  case "$PKG_FAMILY" in
    debian) apt-get update -y ;;
    rhel)   $PKG_MGR makecache -y ;;
    suse)   zypper --non-interactive refresh ;;
  esac
}

pkg_install() {
  case "$PKG_FAMILY" in
    debian) DEBIAN_FRONTEND=noninteractive apt-get install -y "$@" ;;
    rhel)   $PKG_MGR install -y "$@" ;;
    suse)   zypper --non-interactive install "$@" ;;
  esac
}

TOTAL_RAM=$(free -g | awk '/^Mem:/{print $2}')
if [ "$TOTAL_RAM" -lt 4 ]; then
  warning "RAM: ${TOTAL_RAM}GB detected — 4GB+ recommended."
else
  success "RAM: ${TOTAL_RAM}GB total"
fi

SWAP_GB=$(free -g | awk '/^Swap:/{print $2}')
if [ "$SWAP_GB" -lt 16 ]; then
  warning "Swap: ${SWAP_GB}GB — 16GB recommended (equal to RAM)."
else
  success "Swap: ${SWAP_GB}GB configured"
fi

# =============================================================================
# SECTION 2 — Mount Point Validation & Directory Creation
# =============================================================================
section "Mount Point Validation"

MOUNT_PATHS=("/" "/var" "/opt" "/home" "/tmp" "/data")
MOUNT_MIN_GBS=("40" "100" "80" "40" "20" "200")
MOUNT_PURPOSES=(
  "Root filesystem"
  "Application logs and telemetry data"
  "Docker Engine, Compose, and custom packages"
  "User files and configurations"
  "Temporary files"
  "Edge telemetry data storage, buffer, and archive"
)

MOUNT_WARNINGS=false

for i in "${!MOUNT_PATHS[@]}"; do
  MOUNT="${MOUNT_PATHS[$i]}"
  MIN_GB="${MOUNT_MIN_GBS[$i]}"
  PURPOSE="${MOUNT_PURPOSES[$i]}"

  if [ ! -d "$MOUNT" ]; then
    warning "$MOUNT does not exist — creating directory..."
    mkdir -p "$MOUNT"
    success "Created: $MOUNT  ($PURPOSE)"
    warning "  ⚠  $MOUNT is a plain directory, NOT a dedicated mount point."
    warning "     Provision and mount a dedicated volume (${MIN_GB}GB) at $MOUNT for production."
    MOUNT_WARNINGS=true
    continue
  fi

  IS_MOUNTED=false
  if [ "$MOUNT" = "/" ]; then
    IS_MOUNTED=true
  elif grep -qs " ${MOUNT} " /proc/mounts; then
    IS_MOUNTED=true
  fi

  if [ "$IS_MOUNTED" = false ]; then
    warning "$MOUNT exists but has NO dedicated volume (sharing root filesystem)."
    warning "  Purpose:          $PURPOSE"
    warning "  Recommended size: ${MIN_GB}GB"
    warning "  Action needed:    Provision and mount a dedicated volume at $MOUNT."
    MOUNT_WARNINGS=true
  else
    AVAIL_GB=$(df "$MOUNT" --output=avail -BG 2>/dev/null | tail -1 | tr -d 'G ')
    TOTAL_GB=$(df "$MOUNT" --output=size  -BG 2>/dev/null | tail -1 | tr -d 'G ')
    if [ "$AVAIL_GB" -lt "$MIN_GB" ]; then
      warning "$MOUNT — only ${AVAIL_GB}GB free of ${TOTAL_GB}GB  (min required: ${MIN_GB}GB)"
      warning "  Purpose: $PURPOSE"
      MOUNT_WARNINGS=true
    else
      success "$MOUNT — ${AVAIL_GB}GB free / ${TOTAL_GB}GB total  [min: ${MIN_GB}GB]  |  $PURPOSE"
    fi
  fi
done

echo ""
info "Current disk layout:"
echo ""
printf "  %-18s %-8s %-8s %-8s %s\n" "Mount" "Size" "Used" "Avail" "Use%"
printf "  %-18s %-8s %-8s %-8s %s\n" "─────────────────" "────────" "────────" "────────" "────"
for MOUNT in "${MOUNT_PATHS[@]}"; do
  if [ -d "$MOUNT" ]; then
    LINE=$(df -h "$MOUNT" 2>/dev/null | tail -1)
    TOTAL=$(echo "$LINE" | awk '{print $2}')
    USED=$(echo  "$LINE" | awk '{print $3}')
    AVAIL=$(echo "$LINE" | awk '{print $4}')
    PCT=$(echo   "$LINE" | awk '{print $5}')
    printf "  %-18s %-8s %-8s %-8s %s\n" "$MOUNT" "$TOTAL" "$USED" "$AVAIL" "$PCT"
  else
    printf "  %-18s %s\n" "$MOUNT" "(not found)"
  fi
done
echo ""

if [ "$MOUNT_WARNINGS" = true ]; then
  warning "Mount point issues detected — resolve before going to production."
fi

# =============================================================================
# SECTION 3 — System Update
# =============================================================================
section "Step 1 — Updating System Packages"

info "Refreshing and upgrading packages ($PKG_MGR)..."
pkg_refresh
case "$PKG_FAMILY" in
  debian) DEBIAN_FRONTEND=noninteractive apt-get upgrade -y ;;
  rhel)   $PKG_MGR upgrade -y ;;
  suse)   zypper --non-interactive update ;;
esac
success "System packages updated"

# =============================================================================
# SECTION 4 — Install Utilities
# =============================================================================
section "Step 2 — Installing Utilities"

info "Installing make, unzip, curl, net-tools..."
case "$PKG_FAMILY" in
  debian) pkg_install make unzip curl net-tools ca-certificates gnupg lsb-release ;;
  rhel)   pkg_install make unzip curl net-tools ca-certificates gnupg2 dnf-plugins-core ;;
  suse)   pkg_install make unzip curl net-tools ca-certificates gpg2 ;;
esac
success "Utilities installed (make, unzip, curl, net-tools)"

# =============================================================================
# SECTION 5 — Install Docker
# =============================================================================
section "Step 3 — Installing Docker"

if command -v docker &> /dev/null; then
  warning "Docker already installed: $(docker --version)"
  info "Skipping Docker installation."
else
  DOCKER_PKGS="docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"

  if [ -z "$DOCKER_REPO_OS" ]; then
    # No upstream Docker repo for this distro (Amazon Linux, openSUSE Tumbleweed, ...)
    warning "No Docker CE repo for '${ID:-unknown}' — using the distro's own docker package."
    pkg_install docker || pkg_install docker.io
  elif [ "$PKG_FAMILY" = debian ]; then
    info "Adding Docker GPG key..."
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL "https://download.docker.com/linux/${DOCKER_REPO_OS}/gpg" | \
      gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    info "Adding Docker apt repository..."
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
      https://download.docker.com/linux/${DOCKER_REPO_OS} \
      ${DEB_CODENAME} stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null

    info "Installing Docker Engine and Compose plugin..."
    apt-get update -y
    # shellcheck disable=SC2086
    pkg_install $DOCKER_PKGS
  elif [ "$PKG_FAMILY" = rhel ]; then
    # RHEL ships podman-docker, which shadows the docker CLI — remove it first
    $PKG_MGR remove -y podman-docker runc &> /dev/null || true

    info "Adding Docker $PKG_MGR repository..."
    if command -v dnf > /dev/null; then
      dnf config-manager --add-repo "https://download.docker.com/linux/${DOCKER_REPO_OS}/docker-ce.repo"
    else
      yum-config-manager --add-repo "https://download.docker.com/linux/${DOCKER_REPO_OS}/docker-ce.repo"
    fi

    info "Installing Docker Engine and Compose plugin..."
    # shellcheck disable=SC2086
    pkg_install $DOCKER_PKGS
  else
    # SUSE: docker.com publishes an SLES repo; openSUSE uses the distro package
    info "Adding Docker repository..."
    zypper --non-interactive addrepo --gpgcheck-allow-unsigned \
      "https://download.docker.com/linux/${DOCKER_REPO_OS}/docker-ce.repo" docker-ce &> /dev/null || \
      warning "Docker repo add failed — falling back to distro packages."
    zypper --non-interactive --gpg-auto-import-keys refresh
    # shellcheck disable=SC2086
    pkg_install $DOCKER_PKGS || pkg_install docker
  fi

  # Compose plugin is missing from some distro docker packages — install the binary
  if ! docker compose version &> /dev/null; then
    warning "Compose plugin not present — installing the standalone plugin binary..."
    CLI_PLUGINS=/usr/local/lib/docker/cli-plugins
    mkdir -p "$CLI_PLUGINS"
    curl -fsSL "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
      -o "$CLI_PLUGINS/docker-compose"
    chmod +x "$CLI_PLUGINS/docker-compose"
  fi

  success "Docker installed:         $(docker --version)"
  success "Docker Compose installed: $(docker compose version)"
fi

# Some distro packages ship no 'docker' group until the service first starts
getent group docker > /dev/null || groupadd docker

if id -nG "$INVOKING_USER" | grep -qw docker; then
  info "User '$INVOKING_USER' is already in the docker group."
else
  usermod -aG docker "$INVOKING_USER"
  success "User '$INVOKING_USER' added to the docker group."
  warning "Run 'newgrp docker' or log out/in before using Docker commands."
fi

systemctl enable docker
systemctl start docker
success "Docker service enabled and running"

# Open the service ports on whichever firewall this distro runs
# (firewalld on RHEL/SUSE, ufw on Ubuntu). 6379 stays closed — Redis is internal.
SERVICE_PORTS="80 443 8001 8002 8003 8080"
if systemctl is-active --quiet firewalld 2>/dev/null; then
  info "firewalld is active — opening service ports..."
  for P in $SERVICE_PORTS; do
    firewall-cmd --permanent --add-port="${P}/tcp" > /dev/null
  done
  firewall-cmd --reload > /dev/null
  success "Ports opened via firewalld: $SERVICE_PORTS"
elif command -v ufw &> /dev/null && ufw status 2>/dev/null | grep -q "^Status: active"; then
  info "ufw is active — opening service ports..."
  for P in $SERVICE_PORTS; do
    ufw allow "${P}/tcp" > /dev/null
  done
  success "Ports opened via ufw: $SERVICE_PORTS"
else
  info "No active host firewall detected — no ports opened."
fi

# =============================================================================
# SECTION 6 — Install Nginx
# =============================================================================
section "Step 4 — Installing Nginx"

if command -v nginx &> /dev/null; then
  warning "Nginx already installed: $(nginx -v 2>&1)"
  info "Skipping Nginx installation."
else
  info "Installing Nginx..."
  pkg_install nginx
  success "Nginx installed: $(nginx -v 2>&1)"
fi

systemctl enable nginx
systemctl start nginx
success "Nginx service enabled and running"

# =============================================================================
# SECTION 7 — Port Availability Check
# =============================================================================
section "Step 5 — Checking Port Availability"

PORT_NUMS=(80 443 8001 8002 8003 8080 6379)
PORT_LABELS=(
  "Nginx HTTP"
  "Nginx HTTPS"
  "Telemetry Collector"
  "Telemetry Processor"
  "RUM Analytics API"
  "Kafka UI"
  "Redis"
)
ALL_PORTS_CLEAR=true

for i in "${!PORT_NUMS[@]}"; do
  PORT="${PORT_NUMS[$i]}"
  LABEL="${PORT_LABELS[$i]}"
  if ss -tulpn 2>/dev/null | grep -q ":${PORT} "; then
    warning "Port $PORT ($LABEL) is already in use!"
    ALL_PORTS_CLEAR=false
  else
    success "Port $PORT ($LABEL) is free"
  fi
done

if [ "$ALL_PORTS_CLEAR" = false ]; then
  warning "Resolve port conflicts before deploying."
  warning "Run: sudo ss -tulpn | grep -E ':(80|443|8001|8002|8003|8080|6379)'"
else
  success "All required ports are available"
fi

# =============================================================================
# SECTION 8 — PostgreSQL Connectivity Check
# =============================================================================
section "Step 6 — PostgreSQL Connectivity Check"

info "You will need the DB host and port from your infrastructure/config team."
echo ""

if [ -z "$PG_HOST" ]; then
  read -rp "  Enter PostgreSQL host (e.g. 192.168.1.100): " PG_HOST
fi
if [ -z "$PG_PORT" ]; then
  read -rp "  Enter PostgreSQL port (default 5432): " PG_PORT
  PG_PORT="${PG_PORT:-5432}"
fi

echo ""
if nc -zv -w 5 "$PG_HOST" "$PG_PORT" 2>&1 | grep -q "succeeded\|open"; then
  success "PostgreSQL is reachable at $PG_HOST:$PG_PORT"
else
  warning "Could not reach PostgreSQL at $PG_HOST:$PG_PORT"
  warning "Check that:"
  warning "  - The DB host and port from your team are correct"
  warning "  - This server's IP is whitelisted on the database firewall"
  warning "  - Network routing between this server and the DB is configured"
  warning "Deployment can continue but processor and RUM Analytics will fail to connect."
fi

# =============================================================================
# SECTION 9 — Create Deployment Directories
# =============================================================================
section "Step 7 — Creating Deployment Directories"

# Project extract directory
DEPLOY_DIR="/opt/edgetelemetry"
if [ -d "$DEPLOY_DIR" ]; then
  warning "$DEPLOY_DIR already exists. Skipping creation."
else
  mkdir -p "$DEPLOY_DIR"
  success "Created: $DEPLOY_DIR  (project directory)"
fi
chown "$INVOKING_USER":"$INVOKING_USER" "$DEPLOY_DIR"
success "Ownership of $DEPLOY_DIR set to '$INVOKING_USER'"

# Makefile data/log directories — owned 1000:1000 for Docker compatibility
EDGE_DATA_ROOT="/opt/edge-telemetry"
for SUBDIR in data/kafka data/zookeeper data/redis logs/zookeeper logs/redis; do
  FULL_PATH="$EDGE_DATA_ROOT/$SUBDIR"
  if [ ! -d "$FULL_PATH" ]; then
    mkdir -p "$FULL_PATH"
    success "Created: $FULL_PATH"
  else
    info "$FULL_PATH already exists"
  fi
done
chown -R 1000:1000 "$EDGE_DATA_ROOT"
success "Ownership of $EDGE_DATA_ROOT set to 1000:1000 (Docker compatibility)"

# Telemetry data storage on the /data mount
DATA_DIR="/data/edgetelemetry"
if [ -d "$DATA_DIR" ]; then
  warning "$DATA_DIR already exists. Skipping creation."
else
  mkdir -p "$DATA_DIR"
  success "Created: $DATA_DIR  (telemetry data storage)"
fi
chown "$INVOKING_USER":"$INVOKING_USER" "$DATA_DIR"
success "Ownership of $DATA_DIR set to '$INVOKING_USER'"

# =============================================================================
# SECTION 10 — Final Summary
# =============================================================================
section "Installation Complete"

echo ""
echo -e "  ${GREEN}Software installed:${NC}"
echo -e "    ✓ Docker          $(docker --version)"
echo -e "    ✓ Docker Compose  $(docker compose version)"
echo -e "    ✓ Nginx           $(nginx -v 2>&1)"
echo -e "    ✓ Make            $(make --version | head -1)"
echo -e "    ✓ Unzip           $(unzip -v 2>&1 | head -1)"
echo ""
echo -e "  ${GREEN}Directories ready:${NC}"
echo -e "    ✓ $DEPLOY_DIR              (project directory)"
echo -e "    ✓ $EDGE_DATA_ROOT/data     (Kafka, Zookeeper, Redis volumes)"
echo -e "    ✓ $EDGE_DATA_ROOT/logs     (Zookeeper, Redis logs)"
echo -e "    ✓ $DATA_DIR         (telemetry data storage)"
echo ""

if [ "$MOUNT_WARNINGS" = true ] || [ "$ALL_PORTS_CLEAR" = false ]; then
  echo -e "  ${YELLOW}⚠  Warnings were raised — review output above before deploying to production.${NC}"
  echo ""
fi

echo -e "  ${CYAN}Next steps:${NC}"
echo -e "    1.  From your local machine, copy the project to the server:"
echo -e "        ${BLUE}scp EdgeTelemetryDeployment.zip user@<server-ip>:/opt/edgetelemetry/${NC}"
echo -e "    2.  Extract:"
echo -e "        ${BLUE}cd /opt/edgetelemetry && unzip EdgeTelemetryDeployment.zip${NC}"
echo -e "    3.  Enter the project directory:"
echo -e "        ${BLUE}cd EdgeTelemetryDeployment${NC}"
echo -e ""
echo -e "    Then pick one deployment:"
echo -e ""
echo -e "    ${GREEN}A. Single-host${NC} (everything on this server):"
echo -e "        ${BLUE}cp deployments/single-host/configs/single-host.env.example deployments/single-host/configs/single-host.env${NC}"
echo -e "        ${BLUE}nano deployments/single-host/configs/single-host.env${NC}  # set DATABASE_URL"
echo -e "        ${BLUE}make deploy-single-host${NC}"
echo -e ""
echo -e "    ${GREEN}B. Segmented${NC} (DMZ + Bank split — run on each host separately):"
echo -e "         See shared/README.md for the full mTLS + JWT key setup,"
echo -e "         then run ${BLUE}make deploy-dmz${NC} on the DMZ host and"
echo -e "         ${BLUE}make deploy-bank${NC} on the bank host."
echo ""
echo -e "  ${YELLOW}NOTE:${NC} If you were added to the docker group during this run, run:"
echo -e "        ${BLUE}newgrp docker${NC}  (or log out and back in)"
echo ""
