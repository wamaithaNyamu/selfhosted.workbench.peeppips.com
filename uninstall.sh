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

read -p "Do you want to proceed with the uninstallation? [y/N]: " proceed
if [[ ! "$proceed" =~ ^[Yy]$ ]]; then
    echo "Uninstallation aborted."
    exit 0
fi

read -p "Do you also want to remove Docker and Git from your system? [Y/n]: " remove_deps
remove_deps=${remove_deps:-Y}

PROJECT_ROOT="/opt/peeppips-workbench"

echo "[1/4] Stopping and removing containers..."
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
    
    $COMPOSE_CMD down -v --remove-orphans || true
fi

echo "[2/4] Removing docker networks, volumes, and images..."
docker network rm workbench-net 2>/dev/null || true
docker container prune -f >/dev/null 2>&1 || true
docker volume prune -f >/dev/null 2>&1 || true
# Optionally remove all images if requested, or just dangling ones
if [[ "$remove_deps" =~ ^[Yy]$ ]]; then
    docker image prune -a -f >/dev/null 2>&1 || true
else
    docker image prune -f >/dev/null 2>&1 || true
fi

echo "[3/4] Removing project directories..."
rm -rf "$PROJECT_ROOT"
rm -rf /var/lib/workbench
rm -rf /var/lib/grafana

echo "[4/4] Processing dependencies..."
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
