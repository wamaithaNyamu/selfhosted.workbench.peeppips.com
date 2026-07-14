#!/bin/bash
set -e

# Check if license key is provided via argument or environment variable
if [ -n "$1" ]; then
  LICENSE_KEY="$1"
fi

if [ -z "$LICENSE_KEY" ]; then
  echo "Error: License key is required."
  echo "Usage: curl -sSL https://get.peeppips.org | sudo bash -s -- <license_key>"
  echo "Or:    curl -sSL https://get.peeppips.org | sudo LICENSE_KEY=<key> bash"
  exit 1
fi

echo "================================================="
echo "   Peeppips AI Workbench - One-Command Install   "
echo "================================================="

PROJECT_ROOT="/opt/peeppips-workbench"
REPO_URL="https://github.com/wamaithaNyamu/selfhosted.workbench.peeppips.com.git"

if [ "$EUID" -ne 0 ]; then
  echo "Error: Please run this script as root or using sudo."
  echo "Example: curl -sSL https://get.peeppips.org | sudo bash -s -- <license_key>"
  exit 1
fi

echo "[1/6] Installing prerequisites..."
apt-get update -y -q >/dev/null 2>&1 || true
apt-get install -y -q git curl openssl >/dev/null 2>&1 || true

echo "[2/6] Checking and installing Docker..."
if ! command -v docker >/dev/null 2>&1; then
    echo "Docker not found. Installing..."
    curl -fsSL https://get.docker.com | sh >/dev/null 2>&1
else
    echo "Docker is already installed."
fi
systemctl start docker || true
systemctl enable docker || true

echo "[3/6] Cloning the repository to $PROJECT_ROOT..."
if [ ! -d "$PROJECT_ROOT" ]; then
    git clone -q "$REPO_URL" "$PROJECT_ROOT"
else
    echo "Directory $PROJECT_ROOT already exists. Pulling latest changes..."
    cd "$PROJECT_ROOT" && git pull -q || true
fi

cd "$PROJECT_ROOT"

echo "[4/6] Setting up Environment Variables..."
if [ ! -f .env ]; then
    echo "Generating secure passwords..."
    # Generate random passwords
    PG_PASS=$(openssl rand -hex 16)
    AUTH_PASS=$(openssl rand -hex 16)
    MINIO_SECRET=$(openssl rand -hex 16)
    GRAFANA_PASS=$(openssl rand -hex 16)
    
    cat <<EOF > .env
POSTGRES_HOST=postgres
POSTGRES_PORT=5432
POSTGRES_DB=workbench
POSTGRES_USER=workbench
POSTGRES_PASSWORD=${PG_PASS}
POSTGRES_SSLMODE=disable
DATABASE_URL=postgres://workbench:${PG_PASS}@postgres:5432/workbench?sslmode=disable
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_ADDR=redis:6379
SERVER_PORT=8080
PORT=8080
AUTH_PASSWORD=${AUTH_PASS}
MINIO_SECRET_KEY=${MINIO_SECRET}
GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_PASS}
LICENSE_KEY=${LICENSE_KEY}
EOF
else
    echo ".env already exists, ensuring LICENSE_KEY is set..."
    if ! grep -q "^LICENSE_KEY=" .env; then
        echo "LICENSE_KEY=${LICENSE_KEY}" >> .env
    else
        sed -i "s/^LICENSE_KEY=.*/LICENSE_KEY=${LICENSE_KEY}/" .env
    fi
fi

echo "[5/6] Setting up Docker networks and volumes..."
docker network create workbench-net 2>/dev/null || true

mkdir -p /var/lib/workbench/mt5
mkdir -p /var/lib/workbench/wine
chmod 0777 /var/lib/workbench/mt5
chmod 0777 /var/lib/workbench/wine

docker container prune -f >/dev/null 2>&1 || true
docker image prune -f >/dev/null 2>&1 || true

echo "[6/6] Starting infrastructure..."

# Core Infrastructure (Postgres, Redis)
if [ -f docker-compose.infra.yml ]; then
    docker compose -f docker-compose.infra.yml up -d
fi

# Application (Server, Frontend)
if [ -f docker-compose.app.yml ]; then
    docker compose -f docker-compose.app.yml up -d
fi

# Optional/Advanced Stacks (Copied from ansible structure)
if [ -f docker-compose.temporal.yml ]; then
    docker compose -f docker-compose.temporal.yml up -d
fi

if [ -f docker-compose.ml.prod.yml ]; then
    docker compose -f docker-compose.ml.prod.yml up -d
fi

if [ -f docker-compose.logs.yml ]; then
    docker compose -f docker-compose.logs.yml up -d
    docker compose -f docker-compose.metrics.yml up -d
    docker compose -f docker-compose.tracing.yml up -d
    docker compose -f docker-compose.otel.yml up -d
fi

# If using docker-compose.prod.yml from the ansible format
if [ -f docker-compose.prod.yml ]; then
    docker compose -f docker-compose.prod.yml up -d --pull always server cloudflared
fi

echo "================================================="
echo " Installation completed successfully!            "
echo " Your workbench is now running at $PROJECT_ROOT  "
echo "================================================="
