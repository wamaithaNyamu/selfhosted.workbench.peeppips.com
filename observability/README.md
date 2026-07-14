docker compose -f docker-compose.logs.yml down
docker compose -f docker-compose.metrics.yml down
docker compose -f docker-compose.otel.yml down
docker compose -f docker-compose.tracing.yml down



docker compose -f docker-compose.logs.yml up -d
docker compose -f docker-compose.metrics.yml up -d
docker compose -f docker-compose.otel.yml up -d
docker compose -f docker-compose.tracing.yml up -d


# 1. Kill the logging stack
docker compose -f docker-compose.logs.yml down

# 2. Nuke the specific persistent volume state
docker volume rm backendworkbenchclient_grafana_data

# 3. Bring it back up clean
docker compose -f docker-compose.logs.yml up -d

