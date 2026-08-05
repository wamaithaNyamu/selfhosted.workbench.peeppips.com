#!/bin/bash

# Peeppips Workbench Selfhosted Update Script
# This script pulls the latest images and seamlessly restarts enabled services.

echo "🔄 Starting Workbench Update Process..."

TARGET_VERSION=$1
if [ -n "$TARGET_VERSION" ]; then
    echo "🎯 Target version provided: $TARGET_VERSION. Updating .env..."
    # Support rollback/upgrades by setting the new IMAGE_TAG
    sed -i "s/^IMAGE_TAG=.*/IMAGE_TAG=$TARGET_VERSION/" .env
fi

# 1. Update the selfhosted repository itself to get the latest compose files
echo "[1/4] Pulling latest compose files..."
git pull origin main || echo "Git pull failed, continuing with current compose files..."

# 2. Pull the latest images and restart stacks
echo "[2/4] Building unified compose command..."
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

echo "[3/4] Pulling and restarting services in dependency-aware order..."
$COMPOSE_CMD pull
$COMPOSE_CMD up -d --remove-orphans

# 4. Cleanup old dangling images to save disk space
echo "[4/4] Cleaning up old images..."
docker image prune -f >/dev/null 2>&1 || true

echo "✅ Update complete! System is running the latest version."
