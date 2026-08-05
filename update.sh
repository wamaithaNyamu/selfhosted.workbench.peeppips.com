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

# 2. Pull the latest images for all enabled stacks
echo "[2/4] Pulling latest Docker images from ghcr.io..."
if [ -f docker-compose.temporal.yml ]; then
    docker compose -f docker-compose.temporal.yml pull
fi
if [ -f docker-compose.ml.prod.yml ]; then
    docker compose -f docker-compose.ml.prod.yml pull
fi
if [ -f docker-compose.logs.yml ]; then
    docker compose -f docker-compose.logs.yml pull
    docker compose -f docker-compose.metrics.yml pull
    docker compose -f docker-compose.tracing.yml pull
    docker compose -f docker-compose.otel.yml pull
fi
if [ -f docker-compose.prod.yml ]; then
    docker compose -f docker-compose.prod.yml pull
fi

# 3. Restart enabled stacks (docker compose up -d automatically recreates changed containers)
echo "[3/4] Restarting services with latest images..."
if [ -f docker-compose.temporal.yml ]; then
    docker compose -f docker-compose.temporal.yml up -d --remove-orphans
fi
if [ -f docker-compose.ml.prod.yml ]; then
    docker compose -f docker-compose.ml.prod.yml up -d --remove-orphans
fi
if [ -f docker-compose.logs.yml ]; then
    docker compose -f docker-compose.logs.yml up -d --remove-orphans
    docker compose -f docker-compose.metrics.yml up -d --remove-orphans
    docker compose -f docker-compose.tracing.yml up -d --remove-orphans
    docker compose -f docker-compose.otel.yml up -d --remove-orphans
fi
if [ -f docker-compose.prod.yml ]; then
    docker compose -f docker-compose.prod.yml up -d --remove-orphans
fi

# 4. Cleanup old dangling images to save disk space
echo "[4/4] Cleaning up old images..."
docker image prune -f >/dev/null 2>&1 || true

echo "✅ Update complete! System is running the latest version."
