#!/usr/bin/env bash
set -euo pipefail

TAG="${1:?usage: deploy.sh <image-tag>}"
if [[ ! "$TAG" =~ ^[A-Za-z0-9_.-]+$ ]]; then
  echo "invalid tag" >&2
  exit 2
fi

export HOME="${HOME:-/root}"

OPT=/opt/outline
ENV_FILE="$OPT/.env"
STATE_DIR="$OPT/state"
CURRENT_LINK="$OPT/current"

set -a
# shellcheck disable=SC1091
source "$OPT/instance.env"
set +a

REL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "$STATE_DIR"

dc() {
  docker compose -p outline -f "$CURRENT_LINK/docker-compose.yml" --env-file "$ENV_FILE" "$@"
}

PARAMS_JSON="$(aws ssm get-parameters-by-path --path /outline/ --with-decryption \
  --region "$AWS_REGION" --output json)"

render_env() {
  local tag="$1" tmp
  tmp="$(mktemp "$OPT/.env.XXXXXX")"
  chmod 600 "$tmp"
  jq -r \
    --arg tag "$tag" --arg region "$AWS_REGION" --arg domain "$DOMAIN" \
    --arg ecr "$ECR_REGISTRY" --arg bucket "$ATTACHMENTS_BUCKET" '
    def clean: gsub("[\r\n]"; "");
    (.Parameters | map({key: (.Name | sub("^/outline/"; "")), value: (.Value | clean)}) | from_entries) as $p
    | ($p | to_entries[] | "\(.key)=\(.value)"),
      "NODE_ENV=production",
      "URL=https://\($domain)",
      "PORT=3000",
      "DATABASE_URL=postgres://outline:\($p.POSTGRES_PASSWORD)@postgres:5432/outline",
      "PGSSLMODE=disable",
      "REDIS_URL=redis://redis:6379",
      "FILE_STORAGE=s3",
      "AWS_REGION=\($region)",
      "AWS_S3_UPLOAD_BUCKET_NAME=\($bucket)",
      "AWS_S3_UPLOAD_BUCKET_URL=https://s3.\($region).amazonaws.com",
      "AWS_S3_FORCE_PATH_STYLE=true",
      "AWS_S3_ACL=private",
      "FILE_STORAGE_UPLOAD_MAX_SIZE=26214400",
      "FORCE_HTTPS=true",
      "ECR_REGISTRY=\($ecr)",
      "DOMAIN=\($domain)",
      "OUTLINE_TAG=\($tag)"
  ' <<<"$PARAMS_JSON" >"$tmp"
  mv -f "$tmp" "$ENV_FILE"
}

OLD_TAG=""
if [[ -f "$STATE_DIR/current_tag" ]]; then
  OLD_TAG="$(<"$STATE_DIR/current_tag")"
fi
OLD_REL=""
if [[ -L "$CURRENT_LINK" ]]; then
  OLD_REL="$(readlink -f "$CURRENT_LINK")"
fi

render_env "$TAG"

aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "$ECR_REGISTRY"

if [[ -n "$OLD_TAG" && -n "$OLD_REL" ]] \
  && dc ps --status running --services 2>/dev/null | grep -qx postgres; then
  echo "pre-deploy backup"
  bash "$REL_DIR/backup.sh" pre-deploy
fi

ln -sfn "$REL_DIR" "$CURRENT_LINK"
dc pull outline
dc up -d --remove-orphans

healthy=false
for i in $(seq 1 60); do
  out="$(dc exec -T outline wget -qO- http://localhost:3000/_health 2>/dev/null || true)"
  if [[ "$out" == *OK* ]]; then
    healthy=true
    break
  fi
  echo "waiting for health ($i/60)"
  sleep 5
done

if [[ "$healthy" == true ]]; then
  if [[ -n "$OLD_TAG" ]]; then
    echo "$OLD_TAG" >"$STATE_DIR/previous_tag"
  fi
  echo "$TAG" >"$STATE_DIR/current_tag"
  docker image prune -af --filter until=168h >/dev/null || true
  find "$OPT/releases" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' \
    | sort -rn | tail -n +6 | cut -d' ' -f2- \
    | while IFS= read -r d; do
        if [[ "$d" != "$REL_DIR" && "$d" != "$OLD_REL" ]]; then
          rm -rf -- "$d"
        fi
      done
  echo "deploy ok: $TAG"
  exit 0
fi

echo "health check failed for $TAG" >&2
dc logs --tail 50 outline >&2 || true

if [[ -n "$OLD_TAG" && -n "$OLD_REL" && -d "$OLD_REL" ]]; then
  echo "rolling back to $OLD_TAG" >&2
  render_env "$OLD_TAG"
  ln -sfn "$OLD_REL" "$CURRENT_LINK"
  dc up -d --remove-orphans || true
else
  echo "no previous release to roll back to" >&2
fi
exit 1
