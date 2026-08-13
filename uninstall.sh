#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
  echo "Error: Please run this script as root or using sudo."
  exit 1
fi

echo "================================================="
echo "   Peeppips AI Workbench - Uninstaller         "
echo "================================================="
echo "WARNING: This will completely stop all services, delete all containers, volumes (including databases), and remove the project directory."

PROJECT_ROOT="/opt/peeppips-workbench"

if [ "$SELF_UPDATED" != "1" ] && [ -d "$PROJECT_ROOT/.git" ]; then
    cd "$PROJECT_ROOT"
    echo "🔄 Fetching latest uninstaller..."
    git fetch origin main -q && git reset --hard origin/main -q
    
    export SELF_UPDATED="1"
    exec "$0" "$@"
fi



read -p "Do you want to proceed with the uninstallation? [y/N]: " proceed
if [[ ! "$proceed" =~ ^[Yy]$ ]]; then
    echo "Uninstallation aborted."
    exit 0
fi

# Changed default to 'N' for safety so users don't accidentally nuke Docker/Git
read -p "Do you also want to remove Docker and Git from your system? [y/N]: " remove_deps
remove_deps=${remove_deps:-N}

PROJECT_ROOT="/opt/peeppips-workbench"

echo "[1/5] Stopping and removing containers..."
if [ -d "$PROJECT_ROOT" ]; then
    cd "$PROJECT_ROOT"
    
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
    
    # The -v flag here safely deletes ONLY the volumes associated with this compose project
    $COMPOSE_CMD down -v --remove-orphans || true
fi

echo "[2/5] Removing docker networks and project images..."
docker network rm workbench-net 2>/dev/null || true
docker container prune -f >/dev/null 2>&1 || true
# REMOVED global volume prune to prevent destroying unrelated user data

if [[ "$remove_deps" =~ ^[Yy]$ ]]; then
    docker image prune -a -f >/dev/null 2>&1 || true
else
    # Remove specifically pulled base images
    echo "Removing specific base images used by Peeppips..."
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
      "alpine:latest"
    )
    for img in "${IMAGES[@]}"; do
        docker rmi -f "$img" >/dev/null 2>&1 || true
    done

    # Remove dynamically built project images
    docker rmi -f $(docker images --filter "reference=*backendworkbenchclient*" -q) >/dev/null 2>&1 || true
    docker rmi -f $(docker images --filter "reference=*peeppips*" -q) >/dev/null 2>&1 || true

    # Only remove dangling images safely
    docker image prune -f >/dev/null 2>&1 || true
fi

echo "[3/5] Removing project directories..."
rm -rf "$PROJECT_ROOT"
rm -rf /var/lib/workbench
rm -rf /var/lib/grafana

echo "[4/5] Removing background tasks..."
# Clean up the auto-updater cron job created during installation
rm -f /etc/cron.d/peeppips_updater
# Reload cron to apply the deletion immediately
systemctl restart cron || systemctl restart crond || true

echo "[5/5] Processing dependencies..."
if [[ "$remove_deps" =~ ^[Yy]$ ]]; then
    echo "Uninstalling Docker and Git..."
    apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin git docker.io docker-doc docker-compose podman-docker containerd runc >/dev/null 2>&1 || true
    apt-get autoremove -y >/dev/null 2>&1 || true
    rm -rf /var/lib/docker
    rm -rf /var/lib/containerd
    rm -rf /etc/docker
else
    echo "Skipping removal of Docker and Git."
fi

echo "================================================="
echo "   Uninstallation Complete.                      "
echo "================================================="