# Architecture Overview

## Technology Stack

See [ADR-0007: Technology Stack](../adr/0007-technology-stack.md) for details and rationale.

---

## System Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                         Host System                              │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │                     Docker Engine                          │  │
│  │                                                            │  │
│  │  ┌──────────┐ ┌────────────┐ ┌──────────┐ ┌─────────────┐  │  │
│  │  │  Helios  │ │ Watchtower │ │ InfluxDB │ │  SOLECTRUS  │  │  │
│  │  │  :3999   │ │ (updates)  │ │  :8086   │ │  Dashboard  │  │  │
│  │  └────┬─────┘ └──────┬─────┘ └──────────┘ │   :3000     │  │  │
│  │       │              │                    └─────────────┘  │  │
│  │       │              │        ┌──────────┐ ┌─────────────┐ │  │
│  │       │              │        │ Postgres │ │    Redis    │ │  │
│  │       │              │        │  :5432   │ │   :6379     │ │  │
│  │       │              │        └──────────┘ └─────────────┘ │  │
│  │       │ manages      │ updates                             │  │
│  │       ▼              ▼                                     │  │
│  │  ┌─────────────────────────┐                               │  │
│  │  │     compose.yaml        │                               │  │
│  │  │         .env            │                               │  │
│  │  └─────────────────────────┘                               │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│  /var/run/docker.sock ◄─── Helios + Watchtower access Docker API │
└──────────────────────────────────────────────────────────────────┘
```

---

## Helios Internal Storage

Helios uses SQLite for its own data:

| Data                | Purpose                          |
| ------------------- | -------------------------------- |
| Admin password hash | Authentication                   |
| Setup state         | Track if initial setup completed |
| Service registry    | Which services Helios manages    |

**Location:** `/app/data/helios.sqlite3` (inside container, persisted via bind mount to `./helios/`)

---

## Directory Structure

```
/opt/solectrus/              # Installation directory (host)
├── compose.yaml             # Docker Compose file (managed by Helios)
├── .env                     # Environment variables (managed by Helios)
├── helios/                  # Helios data (bind mount)
│   └── helios.sqlite3       # Helios internal database
├── postgresql/              # PostgreSQL data (bind mount)
├── redis/                   # Redis data (bind mount)
└── influxdb/                # InfluxDB data (bind mount)
```

**Note:** All data directories are bind mounts (local folders), not Docker volumes. This makes backup and inspection easier.

---

## Install Script (install.sh)

**Prerequisites:** Docker must be installed. The script does not install Docker automatically (different systems require different installation methods).

```bash
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

# Create installation directory
echo ""
echo "Creating installation directory..."
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

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
    restart: unless-stopped
EOF

# Start Helios
echo "Starting Helios..."
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
```
