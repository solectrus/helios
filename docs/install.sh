#!/bin/bash
set -e

INSTALL_DIR="/opt/solectrus"
HELIOS_PORT="3999"

echo ""
echo "=========================================="
echo "  SOLECTRUS Installation"
echo "=========================================="
echo ""
echo "This will install SOLECTRUS in: $INSTALL_DIR"
echo ""

# Check for Docker
if ! command -v docker &> /dev/null; then
  echo "ERROR: Docker is not installed."
  echo "Please install Docker first: https://docs.docker.com/get-docker/"
  exit 1
fi

# Check for Docker Compose
if ! docker compose version &> /dev/null; then
  echo "ERROR: Docker Compose is not available."
  echo "Please install Docker Compose: https://docs.docker.com/compose/install/"
  exit 1
fi

# Detect architecture
ARCH=$(uname -m)
case $ARCH in
  x86_64) PLATFORM="amd64" ;;
  aarch64|arm64) PLATFORM="arm64" ;;
  *)
    echo "ERROR: Unsupported architecture: $ARCH"
    exit 1
    ;;
esac

echo "Detected architecture: $PLATFORM"
echo ""

# Check if installation directory exists
if [ -d "$INSTALL_DIR" ]; then
  echo "WARNING: $INSTALL_DIR already exists."
  read -p "Overwrite? [y/N] " -n 1 -r
  echo ""
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Installation cancelled."
    exit 0
  fi
fi

# Ask for confirmation
read -p "Continue with installation? [y/N] " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Installation cancelled."
  exit 0
fi

# Create installation directory
echo ""
echo "Creating installation directory..."
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Create data directories
mkdir -p helios

# Create minimal compose.yaml with only Helios
cat > compose.yaml << 'EOF'
name: solectrus

services:
  helios:
    image: ghcr.io/solectrus/helios:latest
    ports:
      - "3999:3000"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - .:/app/solectrus
      - ./helios:/app/data
    environment:
      - HELIOS_STACK_PATH=/app/solectrus
    restart: unless-stopped
EOF

# Pull and start Helios
echo "Pulling Helios image..."
docker compose pull

echo "Starting Helios..."
docker compose up -d

# Wait for Helios to be ready
echo "Waiting for Helios to start..."
sleep 5

# Get IP address
if command -v hostname &> /dev/null; then
  IP=$(hostname -I 2>/dev/null | awk '{print $1}' || hostname)
else
  IP="localhost"
fi

echo ""
echo "=========================================="
echo "  Installation complete!"
echo ""
echo "  Open in your browser:"
echo "  http://${IP}:${HELIOS_PORT}"
echo ""
echo "  You will be asked to set an admin password."
echo "=========================================="
