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

SCRIPT_START=$SECONDS
echo "Installation started at: $(date '+%Y-%m-%d %H:%M:%S')"

PROJECT_ROOT="/opt/peeppips-workbench"
REPO_URL="https://github.com/wamaithaNyamu/selfhosted.workbench.peeppips.com.git"

if [ "$EUID" -ne 0 ]; then
  echo "Error: Please run this script as root or using sudo."
  echo "Example: curl -sSL https://get.peeppips.org | sudo bash -s -- <license_key>"
  exit 1
fi

echo "Checking system requirements..."
# Require at least 15GB of free disk space (15360 MB)
AVAILABLE_SPACE_MB=$(df -m / | tail -1 | awk '{print $4}')
REQUIRED_SPACE_MB=15360

if [ "$AVAILABLE_SPACE_MB" -lt "$REQUIRED_SPACE_MB" ]; then
    echo "❌ Error: Insufficient disk space."
    echo "You have $((AVAILABLE_SPACE_MB / 1024))GB available, but Peeppips AI Workbench requires at least 15GB of free space to download all models and containers."
    echo "Please free up some space and try again."
    exit 1
else
    echo "✅ Disk space check passed ($((AVAILABLE_SPACE_MB / 1024))GB available)."
fi

# Require at least 8GB of RAM (~7500 MB to account for OS overhead on 8GB VMs)
TOTAL_RAM_MB=$(free -m | awk '/^Mem:/{print $2}')
REQUIRED_RAM_MB=7500

if [ "$TOTAL_RAM_MB" -lt "$REQUIRED_RAM_MB" ]; then
    echo "❌ Error: Insufficient RAM."
    echo "You have $((TOTAL_RAM_MB / 1024))GB of RAM, but Peeppips AI Workbench requires at least 8GB of RAM to run all ML models and backend services reliably."
    echo "Please upgrade your server and try again."
    exit 1
else
    echo "✅ RAM check passed ($((TOTAL_RAM_MB / 1024))GB total)."
fi

echo "[1/7] Installing prerequisbbbbbbbnites..."
apt-get update -y -q >/dev/null 2>&1 || true
apt-get install -y -q git curl openssl jq >/dev/null 2>&1 || true

echo "[2/7] Verifying License Key..."

ACTUAL_JWT="$LICENSE_KEY"
if [[ "$LICENSE_KEY" == peep_* ]]; then
    echo "Short token detected. Fetching offline JWT from central server..."
    FETCH_RESPONSE=$(curl -sSL -w "%{http_code}" -o /tmp/fetch_payload.json "https://license.peeppips.com/licenses/fetch?token=$LICENSE_KEY")
    if [ "$FETCH_RESPONSE" != "200" ]; then
        echo "❌ Error: Invalid or expired short token."
        rm -f /tmp/fetch_payload.json
        exit 1
    fi
    ACTUAL_JWT=$(jq -r '.jwt_license' /tmp/fetch_payload.json)
    rm -f /tmp/fetch_payload.json
fi

LICENSE_RESPONSE=$(curl -sSL -w "%{http_code}" -o /tmp/license_payload.json -H "Authorization: Bearer $ACTUAL_JWT" "https://license.peeppips.com/licenses/verify")

if [ "$LICENSE_RESPONSE" != "200" ]; then
    echo "❌ Error: Invalid, expired, or deactivated license key."
    echo "Please check your key or visit peeppips.com to renew."
    rm -f /tmp/license_payload.json
    exit 1
fi

TUNNEL_TOKEN=$(jq -r '.tunnel_token' /tmp/license_payload.json)
PLAN=$(jq -r '.plan' /tmp/license_payload.json)
MAX_ACCOUNTS=$(jq -r '.max_accounts' /tmp/license_payload.json)
ADMIN_EMAIL=$(jq -r '.email' /tmp/license_payload.json)
SUBDOMAIN=$(jq -r '.subdomain' /tmp/license_payload.json)

echo "✅ License verified! Plan: $PLAN (Max Accounts: $MAX_ACCOUNTS, Admin: $ADMIN_EMAIL)"
rm -f /tmp/license_payload.json

echo "[2.5/7] Fetching Public Key..."
PUBLIC_KEY_RESP=$(curl -s "https://license.peeppips.com/public-key")
PUBLIC_KEY=$(echo "$PUBLIC_KEY_RESP" | jq -r '.public_key')
if [ -z "$PUBLIC_KEY" ] || [ "$PUBLIC_KEY" = "null" ]; then
    echo "❌ Error: Could not fetch public key from licensing server."
    exit 1
fi

echo "[2.6/7] Fetching Latest Stable Version..."
LATEST_VERSION_RESP=$(curl -s -H "Authorization: Bearer $ACTUAL_JWT" "https://license.peeppips.com/latest-version")
LATEST_VERSION=$(echo "$LATEST_VERSION_RESP" | jq -r '.latest_version')
if [ -z "$LATEST_VERSION" ] || [ "$LATEST_VERSION" = "null" ]; then
    echo "⚠️ Warning: Could not fetch latest version from licensing server. Defaulting to 'latest'."
    LATEST_VERSION="latest"
else
    echo "✅ Target version dynamically set to: $LATEST_VERSION"
fi

echo "[3/7] Checking and installing Docker..."
if ! command -v docker >/dev/null 2>&1; then
    echo "Docker not found. Installing..."
    curl -fsSL https://get.docker.com | sh >/dev/null 2>&1
else
    echo "Docker is already installed."
fi

echo "Configuring Docker daemon to prevent network timeouts..."
mkdir -p /etc/docker
if [ ! -f /etc/docker/daemon.json ]; then
    echo '{"max-concurrent-downloads": 1}' > /etc/docker/daemon.json
    systemctl restart docker || true
elif ! grep -q "max-concurrent-downloads" /etc/docker/daemon.json; then
    jq '. + {"max-concurrent-downloads": 1}' /etc/docker/daemon.json > /tmp/daemon.json.tmp && mv /tmp/daemon.json.tmp /etc/docker/daemon.json
    systemctl restart docker || true
fi

systemctl start docker || true
systemctl enable docker || true

echo "[4/7] Cloning the repository to $PROJECT_ROOT..."
if [ ! -d "$PROJECT_ROOT" ]; then
    git clone -q "$REPO_URL" "$PROJECT_ROOT"
else
    echo "Directory $PROJECT_ROOT already exists. Pulling latest changes..."
    cd "$PROJECT_ROOT" && git pull -q || true
fi

cd "$PROJECT_ROOT"
chmod +x update.sh uninstall.sh || true

echo "[5/7] Setting up Environment Variables..."
if [ ! -f .env ]; then
    echo "Generating secure passwords and encryption keys..."
    # Generate random passwords
    PG_PASS=$(openssl rand -hex 16)
    AUTH_PASS=$(openssl rand -hex 16)
    MINIO_SECRET=$(openssl rand -hex 16)
    GRAFANA_PASS=$(openssl rand -hex 16)
    CRED_ENC_KEY=$(openssl rand -hex 16)
    INTERNAL_API_KEY=$(openssl rand -hex 32)
    
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
MINIO_ACCESS_KEY=admin
MINIO_SECRET_KEY=${MINIO_SECRET}
GF_SECURITY_ADMIN_USER=admin
GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_PASS}
LICENSE_KEY="${LICENSE_KEY}"
LICENSE_PUBLIC_KEY="${PUBLIC_KEY}"
TUNNEL_TOKEN=${TUNNEL_TOKEN}
MAX_ACCOUNTS=${MAX_ACCOUNTS}
CREDENTIALS_ENCRYPTION_KEY=${CRED_ENC_KEY}
INTERNAL_SERVICE_API_KEY=${INTERNAL_API_KEY}
ADMIN_EMAIL=${ADMIN_EMAIL}
GHCR_USERNAME=wamaithanyamu
IMAGE_TAG=${LATEST_VERSION}
NODE_ENV=production
NEXT_TELEMETRY_DISABLED="1"
INTERNAL_API_URL=http://caddy-waf:18081/api
INTERNAL_DERIV_API_URL=http://caddy-waf:18090
INTERNAL_MT5_API_URL=http://caddy-waf:19090
INTERNAL_ML_API_URL=http://caddy-waf:18000/api/v1
TEMPORAL_GATEWAY_URL=http://workbench-go-temporal-api-gateway:8110
PROMETHEUS_URL=http://workbench-prometheus:9090
OTEL_EXPORTER_OTLP_ENDPOINT=otel-collector:4317
COMPOSE_PROJECT_NAME=backendworkbenchclient
TEMPORAL_CORS_ORIGINS=https://${SUBDOMAIN}
TEMPORAL_CSRF_COOKIE_INSECURE=true
TEMPORAL_VERSION=1.27.2
TEMPORAL_ADMINTOOLS_VERSION=1.27.2-tctl-1.18.2-cli-1.3.0
TEMPORAL_DB=temporal
TEMPORAL_VISIBILITY_DB=temporal_visibility
TEMPORAL_UI_VERSION=2.34.0
TEMPORAL_HOST=workbench-temporal
TEMPORAL_DEFAULT_NAMESPACE=default
TEMPORAL_DEFAULT_NAMESPACE_RETENTION=30d
TARGET_NETWORK=workbench-net
POSTGRES_HOST_SEEDS=postgres
MT5_DOCKER_HOST_WINE_ROOT=/var/lib/workbench/wine
EOF
else
    echo ".env already exists, ensuring licensing and encryption keys are set..."
    
    # Ensure LICENSE_KEY
    if ! grep -q "^LICENSE_KEY=" .env; then
        echo "LICENSE_KEY=${LICENSE_KEY}" >> .env
    else
        sed -i "s/^LICENSE_KEY=.*/LICENSE_KEY=${LICENSE_KEY}/" .env
    fi

    # Ensure LICENSE_PUBLIC_KEY
    if ! grep -q "^LICENSE_PUBLIC_KEY=" .env; then
        echo "LICENSE_PUBLIC_KEY=\"${PUBLIC_KEY}\"" >> .env
    else
        # We must use perl instead of sed because PUBLIC_KEY contains newlines
        perl -0777 -pi -e "s/^LICENSE_PUBLIC_KEY=.*?(?=^([A-Z_]+=|\\z))/LICENSE_PUBLIC_KEY=\"${PUBLIC_KEY}\"\\n/ms" .env
    fi

    # Ensure TUNNEL_TOKEN
    if ! grep -q "^TUNNEL_TOKEN=" .env; then
        echo "TUNNEL_TOKEN=${TUNNEL_TOKEN}" >> .env
    else
        sed -i "s|^TUNNEL_TOKEN=.*|TUNNEL_TOKEN=${TUNNEL_TOKEN}|" .env
    fi

    # Ensure CREDENTIALS_ENCRYPTION_KEY
    if ! grep -q "^CREDENTIALS_ENCRYPTION_KEY=" .env; then
        CRED_ENC_KEY=$(openssl rand -hex 16)
        echo "CREDENTIALS_ENCRYPTION_KEY=${CRED_ENC_KEY}" >> .env
    fi

    # Ensure INTERNAL_SERVICE_API_KEY
    if ! grep -q "^INTERNAL_SERVICE_API_KEY=" .env; then
        INTERNAL_API_KEY=$(openssl rand -hex 32)
        echo "INTERNAL_SERVICE_API_KEY=${INTERNAL_API_KEY}" >> .env
    fi

   
    # Ensure IMAGE_TAG is set to the latest version
    if ! grep -q "^IMAGE_TAG=" .env; then
        echo "IMAGE_TAG=${LATEST_VERSION}" >> .env
    else
        sed -i "s/^IMAGE_TAG=.*/IMAGE_TAG=${LATEST_VERSION}/" .env
    fi
fi

echo "[6/7] Setting up Docker networks and volumes..."
docker network create workbench-net 2>/dev/null || true

mkdir -p /var/lib/workbench/mt5
mkdir -p /var/lib/workbench/wine
mkdir -p /var/lib/grafana
chmod 0777 /var/lib/workbench/mt5
chmod 0777 /var/lib/workbench/wine
chmod 0777 /var/lib/grafana

docker container prune -f >/dev/null 2>&1 || true
docker image prune -f >/dev/null 2>&1 || true

echo "[6.5/7] Pulling required base images... (Started at $(date '+%Y-%m-%d %H:%M:%S'))"
IMAGES=(
  "golang:1.25"
  "golang:1.25-alpine"
  "scottyhardy/docker-wine:latest"
  "timescale/timescaledb:2.19.1-pg17"
  "redis:7-alpine"
  "temporalio/auto-setup:1.27.2"
  "temporalio/ui:2.34.0"
  "temporalio/admin-tools:1.27.2-tctl-1.18.2-cli-1.3.0"
  "grafana/loki:3.2.1"
  "grafana/promtail:3.2.1"
  "grafana/grafana:11.2.2"
  "prom/prometheus"
  "prom/node-exporter"
  "grafana/tempo:latest"
  "otel/opentelemetry-collector-contrib:latest"
  "node:22-alpine"
)
for img in "${IMAGES[@]}"; do
  echo "Pulling $img..."
  IMG_START=$SECONDS
  docker pull "$img" >/dev/null 2>&1 || true
  IMG_TIME=$((SECONDS - IMG_START))
  echo "  └─ Took ${IMG_TIME}s"
done

echo "[6.9/7] Building unified compose command..."
COMPOSE_CMD="docker compose -f docker-compose.prod.yml"

if [ -f docker-compose.temporal.yml ]; then
    COMPOSE_CMD="$COMPOSE_CMD -f docker-compose.temporal.yml"
fi
if [ -f docker-compose.ml.prod.yml ]; then
    COMPOSE_CMD="$COMPOSE_CMD -f docker-compose.ml.prod.yml"
fi
if [ -f docker-compose.logs.yml ]; then
    COMPOSE_CMD="$COMPOSE_CMD -f docker-compose.logs.yml -f docker-compose.metrics.yml -f docker-compose.tracing.yml -f docker-compose.otel.yml"
fi

echo "Stopping any conflicting containers..."
$COMPOSE_CMD down --remove-orphans || true

echo "[7/8] Pulling images safely to avoid network saturation..."
export COMPOSE_PARALLEL_LIMIT=3
MAX_RETRIES=3
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    echo "Pulling compose services (this may take a minute, please wait)..."
    if $COMPOSE_CMD pull -q; then
        echo "Images pulled successfully!"
        break
    else
        RETRY_COUNT=$((RETRY_COUNT+1))
        if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
            echo "❌ Failed to pull images after $MAX_RETRIES attempts. Please check your network connection."
            exit 1
        fi
        echo "⚠️ Docker pull failed (likely a network timeout). Retrying in 10 seconds... (Attempt $RETRY_COUNT of $MAX_RETRIES)"
        sleep 10
    fi
done

echo "[8/8] Starting infrastructure in dependency-aware order..."
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if $COMPOSE_CMD up -d --remove-orphans; then
        echo "Infrastructure started successfully!"
        break
    else
        RETRY_COUNT=$((RETRY_COUNT+1))
        if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
            echo "❌ Failed to start infrastructure after $MAX_RETRIES attempts. Please check your network connection and try again."
            exit 1
        fi
        echo "⚠️ Docker Compose failed to start. Retrying in 10 seconds... (Attempt $RETRY_COUNT of $MAX_RETRIES)"
        sleep 10
    fi
done

echo "[9/9] Setting up Auto-Updater Cron Job..."
cat << 'EOF' > /etc/cron.d/peeppips_updater
* * * * * root if [ -f /opt/peeppips-workbench/update_requested ]; then TARGET_VERSION=$(cat /opt/peeppips-workbench/update_requested); rm /opt/peeppips-workbench/update_requested && cd /opt/peeppips-workbench && ./update.sh $TARGET_VERSION >> /var/log/peeppips-update.log 2>&1; fi
EOF
chmod 0644 /etc/cron.d/peeppips_updater

# Verify the cron file was created
if [ -f /etc/cron.d/peeppips_updater ]; then
    echo "✅ Cron job file created successfully."
else
    echo "❌ Error: Failed to create cron job file."
    exit 1
fi

echo "🔄 Enabling and restarting cron daemon to apply changes..."
systemctl enable cron || systemctl enable crond || true
systemctl restart cron || systemctl restart crond || true

if systemctl is-active --quiet cron || systemctl is-active --quiet crond; then
    echo "✅ Cron daemon is active and running."
else
    echo "⚠️ Warning: Cron daemon does not appear to be running. Auto-updates may not trigger automatically."
fi

TOTAL_TIME=$((SECONDS - SCRIPT_START))
TOTAL_MINS=$((TOTAL_TIME / 60))
TOTAL_SECS=$((TOTAL_TIME % 60))

echo "================================================================"
echo " Installation completed successfully!                           "
echo " Total time taken: ${TOTAL_MINS}m ${TOTAL_SECS}s              "
echo " Your workbench is now running at https://$SUBDOMAIN            "
echo "================================================================"
