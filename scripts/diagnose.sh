#!/usr/bin/env bash
set -euo pipefail

log() { printf "\n==> %s\n" "$*"; }
warn() { printf "\n[warn] %s\n" "$*" >&2; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "Missing required command: $1"; exit 1; }; }

require_cmd docker
require_cmd bash
require_cmd curl

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

log "Using project directory: $PROJECT_DIR"

log "Resetting Docker stack (removing volumes so init SQL runs cleanly)..."
docker compose down -v || true

log "Starting Docker stack..."
docker compose up -d

log "Waiting for 'db' to become healthy..."
DB_CID="$(docker compose ps -q db)"
if [ -z "${DB_CID:-}" ]; then
  echo "Failed to find DB container ID. Is docker compose running?" && exit 1
fi

ATTEMPTS=0
until [ "$(docker inspect -f '{{ if .State.Health }}{{ .State.Health.Status }}{{ else }}starting{{ end }}' "$DB_CID")" = "healthy" ]; do
  ATTEMPTS=$((ATTEMPTS+1))
  if [ "$ATTEMPTS" -gt 60 ]; then
    warn "DB did not become healthy within timeout. Recent logs:"
    docker compose logs --no-color --tail 200 db || true
    exit 1
  fi
  sleep 2
done
log "DB is healthy."

log "Applying SQL (idempotent attempts; errors ignored if already applied)..."
# Apply schema and dummy data from inside the container
docker compose exec -T db psql -U postgres -d postgres -f /docker-entrypoint-initdb.d/00-schema.sql || true
docker compose exec -T db psql -U postgres -d postgres -f /docker-entrypoint-initdb.d/01-dummy-data.sql || true

log "Listing tables to verify schema load..."
docker compose exec -T db psql -U postgres -d postgres -c "\dt"

log "Waiting for PostgREST (http://localhost:3000) to respond 200..."
HTTP_OK=0
for i in $(seq 1 60); do
  CODE="$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000 || true)"
  if [ "$CODE" = "200" ]; then
    HTTP_OK=1
    break
  fi
  sleep 1
done
if [ "$HTTP_OK" -ne 1 ]; then
  warn "PostgREST didn't return 200 in time. Recent logs:"
  docker compose logs --no-color --tail 200 rest || true
  exit 1
fi
log "PostgREST is responding."

log "Querying existing table 'users' via PostgREST..."
set +e
USERS_RESP="$(curl -s -w '\nHTTP_CODE:%{http_code}\n' 'http://localhost:3000/users?select=username,status&limit=3')"
set -e
echo "$USERS_RESP"
if ! echo "$USERS_RESP" | grep -q "HTTP_CODE:200"; then
  warn "Users endpoint did not return 200. Inspecting 'rest' logs:"
  docker compose logs --no-color --tail 200 rest || true
  exit 1
fi

log "Attempting RPC call 'get_status'..."
set +e
RPC_RESP="$(curl -s -X POST -H 'Content-Type: application/json' -d '{"name_param":"supabot"}' -w '\nHTTP_CODE:%{http_code}\n' 'http://localhost:3000/rpc/get_status')"
set -e
echo "$RPC_RESP"
if ! echo "$RPC_RESP" | grep -q "HTTP_CODE:200"; then
  warn "RPC did not return 200. See logs:"
  docker compose logs --no-color --tail 200 rest || true
  exit 1
fi

log "Done. Basic DB and API checks passed."
echo "Tip: If you need the 'actor' table specifically, create it and try:"
echo "  docker compose exec -T db psql -U postgres -d postgres -c \"CREATE TABLE IF NOT EXISTS public.actor (actor_id serial PRIMARY KEY, first_name text);\""
echo "  curl 'http://localhost:3000/actor?select=actor_id,first_name&limit=3'"


