#!/bin/bash
set -e

INSTALL_DIR="/opt/solectrus"

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

# Ask for confirmation
read -p "Continue with installation? [y/N] " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Installation cancelled."
  exit 0
fi

# Generate SECRET_KEY_BASE
SECRET_KEY_BASE=$(openssl rand -hex 64)

# Create installation directory
echo ""
echo "Creating installation directory..."
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Create HELIOS data directory
mkdir -p helios

# Create minimal compose.yaml with only HELIOS
cat > compose.yaml << EOF
name: solectrus

services:
  helios:
    image: ghcr.io/solectrus/helios:develop
    ports:
      - "3999:3000"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - .:/app/solectrus
      - ./helios:/app/storage
    environment:
      - SECRET_KEY_BASE=${SECRET_KEY_BASE}
    restart: unless-stopped
EOF

# Start HELIOS
echo "Starting HELIOS..."
docker compose up -d

# Get IP address
IP=$(hostname -I | awk '{print $1}')

echo ""
echo "=========================================="
echo "  Installation complete!"
echo ""
echo "  Open in your browser:"
echo "  http://$IP:3999"
echo "=========================================="
