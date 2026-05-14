#!/usr/bin/env bash
set -e

ENV_FILE="${ENV_FILE:-.env}"
NETWORK_NAME="${NETWORK_NAME:-workbench-net}"

INFRA_COMPOSE="${INFRA_COMPOSE:-docker-compose.infra.yml}"
APP_COMPOSE="${APP_COMPOSE:-docker-compose.app.yml}"

ACTIVE_FILE=".active_color"

BLUE="workbench-blue"
GREEN="workbench-green"

echo "🚀 Starting Workbench Blue/Green Deployment"

if ! command -v docker >/dev/null 2>&1; then
  echo "❌ Docker is not installed"
  exit 1
fi

if docker info >/dev/null 2>&1; then
  DOCKER_CMD="docker"
elif sudo docker info >/dev/null 2>&1; then
  DOCKER_CMD="sudo docker"
else
  echo "❌ Docker daemon unavailable"
  exit 1
fi

for FILE in "$INFRA_COMPOSE" "$APP_COMPOSE" "$ENV_FILE"; do
  if [ ! -f "$FILE" ]; then
    echo "❌ Missing required file: $FILE"
    exit 1
  fi
done

echo "🌐 Ensuring Docker network exists..."
if ! $DOCKER_CMD network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
  $DOCKER_CMD network create "$NETWORK_NAME"
  echo "✅ Created network: $NETWORK_NAME"
else
  echo "✅ Network already exists"
fi

echo "🏗️ Starting infra stack..."
$DOCKER_CMD compose \
  -f "$INFRA_COMPOSE" \
  --env-file "$ENV_FILE" \
  up -d

if [ ! -f "$ACTIVE_FILE" ]; then
  echo "blue" > "$ACTIVE_FILE"
fi

CURRENT=$(cat "$ACTIVE_FILE")

if [ "$CURRENT" = "blue" ]; then
  NEW_COLOR="green"
  OLD_PROJECT="$BLUE"
  NEW_PROJECT="$GREEN"
else
  NEW_COLOR="blue"
  OLD_PROJECT="$GREEN"
  NEW_PROJECT="$BLUE"
fi

echo "🎨 Current active: $CURRENT"
echo "🎨 Deploying new stack: $NEW_COLOR"

echo "📦 Pulling latest images..."
$DOCKER_CMD compose \
  -p "$NEW_PROJECT" \
  -f "$APP_COMPOSE" \
  --env-file "$ENV_FILE" \
  pull

echo "🚀 Starting new stack..."
$DOCKER_CMD compose \
  -p "$NEW_PROJECT" \
  -f "$APP_COMPOSE" \
  --env-file "$ENV_FILE" \
  up -d --remove-orphans

echo "⏳ Waiting for backend health..."

ATTEMPTS=30
HEALTHY=false

for ((i=1; i<=ATTEMPTS; i++)); do
  if $DOCKER_CMD exec workbench-nginx \
    wget -qO- "http://${NEW_PROJECT}-server-1:8080/health" >/dev/null 2>&1; then
    echo "✅ Backend healthy"
    HEALTHY=true
    break
  fi

  echo "⌛ Attempt $i/$ATTEMPTS..."
  sleep 2
done

if [ "$HEALTHY" != "true" ]; then
  echo "❌ New backend did not become healthy. Keeping old stack live."
  echo "🧪 Check logs:"
  echo "$DOCKER_CMD compose -p $NEW_PROJECT -f $APP_COMPOSE --env-file $ENV_FILE logs -f"
  exit 1
fi

echo "🔄 Switching nginx to $NEW_COLOR"

cat > nginx.conf <<EOF
upstream frontend_active {
  server ${NEW_PROJECT}-frontend-1:3000;
}

upstream backend_active {
  server ${NEW_PROJECT}-server-1:8080;
}

server {
  listen 80;

  location /api/ {
    proxy_pass http://backend_active/api/;

    proxy_http_version 1.1;

    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
  }

  location / {
    proxy_pass http://frontend_active;

    proxy_http_version 1.1;

    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
  }
}
EOF

echo "♻️ Validating nginx config..."
$DOCKER_CMD exec workbench-nginx nginx -t

echo "♻️ Restarting nginx to apply switch..."
$DOCKER_CMD restart workbench-nginx >/dev/null

echo "$NEW_COLOR" > "$ACTIVE_FILE"

echo "🧹 Removing old stack: $CURRENT"

$DOCKER_CMD compose \
  -p "$OLD_PROJECT" \
  -f "$APP_COMPOSE" \
  --env-file "$ENV_FILE" \
  down --remove-orphans || true

echo ""
echo "✅ Deployment complete"
echo "🌍 App: http://localhost:8088"
echo "🎨 Active stack: $NEW_COLOR"

echo ""
echo "📊 Running containers:"
$DOCKER_CMD ps

echo ""
echo "🧪 Logs:"
echo "$DOCKER_CMD compose -p $NEW_PROJECT -f $APP_COMPOSE --env-file $ENV_FILE logs -f"