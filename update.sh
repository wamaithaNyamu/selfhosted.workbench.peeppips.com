#!/bin/bash

# Peeppips Workbench Selfhosted Update Script
# This script pulls the latest images and seamlessly restarts enabled services.


set -e

PROJECT_ROOT="/opt/peeppips-workbench"
cd "$PROJECT_ROOT"

echo "================================================="
echo "   Peeppips AI Workbench - Update         "
echo "================================================="


# --- SELF-UPDATE MECHANISM ---
# If this variable isn't set, it means this is the first pass.
if [ "$SELF_UPDATED" != "1" ]; then
    echo "🔄 Fetching latest deployment scripts..."
    git fetch origin main -q && git reset --hard origin/main -q
    
    # Set the flag so it doesn't infinite-loop
    export SELF_UPDATED="1"
    
    # Re-execute this exact script with the new code, passing along any arguments (like $1)
    exec "$0" "$@"
fi

echo "🔄 Starting Workbench Update Process..."

TARGET_VERSION="$1"
if [ -n "$TARGET_VERSION" ]; then
    # STRICT INPUT VALIDATION: Ensure TARGET_VERSION only contains safe characters
    if [[ ! "$TARGET_VERSION" =~ ^[a-zA-Z0-9_.-]+$ ]]; then
        echo "❌ Error: Invalid target version format. Only alphanumeric characters, dots, dashes, and underscores are allowed."
        exit 1
    fi

    # Check currently running Docker images for all custom containers
    if command -v docker >/dev/null 2>&1 && [ -f .env ]; then
        GHCR_USERNAME=$(grep "^GHCR_USERNAME=" .env | cut -d '=' -f2-)
        if [ -n "$GHCR_USERNAME" ]; then
            # Extracts the tags of all running containers under our custom ghcr.io namespace
            RUNNING_TAGS=$(docker ps --format "{{.Image}}" | grep "ghcr.io/$GHCR_USERNAME/" | awk -F':' '{print $2}' | sort | uniq)
            
            # If the only tag running across all custom containers is the target version, we're good
            if [ "$RUNNING_TAGS" == "$TARGET_VERSION" ]; then
                echo "✅ All custom containers are already running version $TARGET_VERSION. No update needed."
                # Ensure .env is still in sync just in case
                grep -v "^IMAGE_TAG=" .env > .env.tmp || true
                echo "IMAGE_TAG=${TARGET_VERSION}" >> .env.tmp
                mv .env.tmp .env
                chmod 0600 .env
                exit 0
            fi
        fi
    fi

    echo "🎯 Target version provided: $TARGET_VERSION. Updating .env..."
    # Support rollback/upgrades by safely setting the new IMAGE_TAG
    grep -v "^IMAGE_TAG=" .env > .env.tmp || true
    echo "IMAGE_TAG=${TARGET_VERSION}" >> .env.tmp
    mv .env.tmp .env
    chmod 0600 .env
fi

# 1. Update the selfhosted repository itself to get the latest compose files
echo "[1/4] Pulling latest compose files..."
git fetch origin main && git reset --hard origin/main || echo "Git pull failed, continuing with current compose files..."

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

MAX_RETRIES=3

echo "[3/5] Pulling latest images with retries..."
export COMPOSE_PARALLEL_LIMIT=3
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    echo "Pulling compose services (this may take a minute, please wait)..."
    if $COMPOSE_CMD pull -q; then
        echo "Images pulled successfully!"
        break
    else
        RETRY_COUNT=$((RETRY_COUNT+1))
        if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
            echo "❌ Failed to pull images after $MAX_RETRIES attempts. Please check your network."
            exit 1
        fi
        echo "⚠️ Docker pull failed (likely a network timeout). Retrying in 10 seconds... (Attempt $RETRY_COUNT of $MAX_RETRIES)"
        sleep 10
    fi
done

echo "[4/5] Restarting services in dependency-aware order..."
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if $COMPOSE_CMD up -d --force-recreate --remove-orphans; then
        echo "Services restarted successfully!"
        break
    else
        RETRY_COUNT=$((RETRY_COUNT+1))
        if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
            echo "❌ Failed to start services after $MAX_RETRIES attempts. Please check your network."
            exit 1
        fi
        echo "⚠️ Docker Compose up failed (likely a network timeout). Retrying in 10 seconds... (Attempt $RETRY_COUNT of $MAX_RETRIES)"
        sleep 10
    fi
done

# 5. Cleanup old dangling images to save disk space
echo "[5/5] Cleaning up old images..."
docker image prune -f >/dev/null 2>&1 || true

echo "✅ Update complete! System is running the latest version."