#!/usr/bin/env bash
set -euo pipefail

label="${1:-daily}"

set -a
# shellcheck disable=SC1091
source /opt/outline/instance.env
set +a

ts="$(date -u +%Y%m%dT%H%M%SZ)"

docker compose -p outline \
  -f /opt/outline/current/docker-compose.yml \
  --env-file /opt/outline/.env \
  exec -T postgres pg_dump -U outline -Fc outline \
  | aws s3 cp - "s3://${BACKUP_BUCKET}/${ts}-${label}.dump" --region "${AWS_REGION}"

echo "backup uploaded: ${ts}-${label}.dump"
