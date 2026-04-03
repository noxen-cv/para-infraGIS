#!/usr/bin/env bash
set -euo pipefail

# Upload a versioned style JSON to Azure Blob and optionally update a stable alias.

RESOURCE_GROUP="${RESOURCE_GROUP:-paraInfraGIS-rg}"
STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-paragisstorage}"
CONTAINER_NAME="${CONTAINER_NAME:-styles}"
STYLE_FILE="${STYLE_FILE:-src/styles/para-latest.json}"
STYLE_DATE="${STYLE_DATE:-$(date +%Y%m%d)}"
STYLE_BLOB_NAME="${STYLE_BLOB_NAME:-style-v${STYLE_DATE}.json}"
STYLE_LATEST_BLOB="${STYLE_LATEST_BLOB:-style-latest.json}"
AUTO_INCREMENT_STYLE_BLOB="${AUTO_INCREMENT_STYLE_BLOB:-true}"
STYLE_COUNTER_START="${STYLE_COUNTER_START:-1}"
STYLE_COUNTER_PAD="${STYLE_COUNTER_PAD:-3}"
UPDATE_LATEST="${UPDATE_LATEST:-true}"
AZ_SUBSCRIPTION_ID="${AZ_SUBSCRIPTION_ID:-}"
STORAGE_AUTH_MODE="${STORAGE_AUTH_MODE:-login}"
AZURE_STORAGE_KEY="${AZURE_STORAGE_KEY:-}"

declare -a STORAGE_AUTH_ARGS=()
RESOLVED_STYLE_BLOB_NAME=""
ACTION="${1:-all}"

log() {
  printf "[%s] %s\n" "$(date +"%Y-%m-%d %H:%M:%S")" "$*"
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    log "Missing required command: $1"
    exit 1
  fi
}

verify_azure_login() {
  if ! az account show >/dev/null 2>&1; then
    log "Azure CLI is not logged in. Run: az login"
    exit 1
  fi
}

set_subscription_context() {
  local sub

  if [[ -n "$AZ_SUBSCRIPTION_ID" ]]; then
    sub="$AZ_SUBSCRIPTION_ID"
  else
    sub="$(az account show --query id -o tsv)"
  fi

  if [[ -z "$sub" ]]; then
    log "Could not determine Azure subscription id. Set AZ_SUBSCRIPTION_ID and retry."
    exit 1
  fi

  log "Using subscription: $sub"
  az account set --subscription "$sub" --output none
}

ensure_storage_auth_args() {
  if [[ "$STORAGE_AUTH_MODE" == "login" ]]; then
    STORAGE_AUTH_ARGS=(--auth-mode login)
    return 0
  fi

  if [[ "$STORAGE_AUTH_MODE" != "key" ]]; then
    log "Unsupported STORAGE_AUTH_MODE: $STORAGE_AUTH_MODE (use login or key)"
    exit 1
  fi

  if [[ -z "$AZURE_STORAGE_KEY" ]]; then
    AZURE_STORAGE_KEY="$(az storage account keys list \
      --resource-group "$RESOURCE_GROUP" \
      --account-name "$STORAGE_ACCOUNT" \
      --query '[0].value' \
      -o tsv)"
  fi

  if [[ -z "$AZURE_STORAGE_KEY" ]]; then
    log "Could not resolve storage account key. Set AZURE_STORAGE_KEY explicitly and retry."
    exit 1
  fi

  STORAGE_AUTH_ARGS=(--auth-mode key --account-key "$AZURE_STORAGE_KEY")
}

assert_file_exists() {
  if [[ ! -f "$STYLE_FILE" ]]; then
    log "Style file not found: $STYLE_FILE"
    exit 1
  fi
}

validate_style_json() {
  assert_file_exists

  if command -v jq >/dev/null 2>&1; then
    jq empty "$STYLE_FILE" >/dev/null
    return 0
  fi

  require_cmd python3
  python3 -m json.tool "$STYLE_FILE" >/dev/null
}

versioned_style_url() {
  printf "https://%s.blob.core.windows.net/%s/%s" "$STORAGE_ACCOUNT" "$CONTAINER_NAME" "$(effective_style_blob_name)"
}

latest_style_url() {
  printf "https://%s.blob.core.windows.net/%s/%s" "$STORAGE_ACCOUNT" "$CONTAINER_NAME" "$STYLE_LATEST_BLOB"
}

effective_style_blob_name() {
  if [[ -n "$RESOLVED_STYLE_BLOB_NAME" ]]; then
    printf "%s" "$RESOLVED_STYLE_BLOB_NAME"
    return 0
  fi

  printf "%s" "$STYLE_BLOB_NAME"
}

resolve_versioned_blob_name() {
  local base_name ext stem counter counter_fmt candidate exists

  if [[ "$AUTO_INCREMENT_STYLE_BLOB" != "true" ]]; then
    RESOLVED_STYLE_BLOB_NAME="$STYLE_BLOB_NAME"
    return 0
  fi

  if [[ ! "$STYLE_COUNTER_START" =~ ^[0-9]+$ || ! "$STYLE_COUNTER_PAD" =~ ^[0-9]+$ ]]; then
    log "STYLE_COUNTER_START and STYLE_COUNTER_PAD must be numeric."
    exit 1
  fi

  ensure_storage_auth_args

  base_name="$STYLE_BLOB_NAME"
  ext=""
  stem="$base_name"
  if [[ "$base_name" == *.* ]]; then
    ext=".${base_name##*.}"
    stem="${base_name%.*}"
  fi

  counter="$STYLE_COUNTER_START"
  while true; do
    printf -v counter_fmt "%0${STYLE_COUNTER_PAD}d" "$counter"
    candidate="${stem}-${counter_fmt}${ext}"
    exists="$(az storage blob exists \
      --account-name "$STORAGE_ACCOUNT" \
      --container-name "$CONTAINER_NAME" \
      --name "$candidate" \
      "${STORAGE_AUTH_ARGS[@]}" \
      --query exists \
      -o tsv)"

    if [[ "$exists" != "true" ]]; then
      RESOLVED_STYLE_BLOB_NAME="$candidate"
      return 0
    fi

    counter=$((counter + 1))
  done
}

upload_versioned() {
  validate_style_json
  resolve_versioned_blob_name

  log "Uploading versioned style: $STYLE_FILE -> $CONTAINER_NAME/$(effective_style_blob_name)"
  az storage blob upload \
    --account-name "$STORAGE_ACCOUNT" \
    --container-name "$CONTAINER_NAME" \
    --name "$(effective_style_blob_name)" \
    --file "$STYLE_FILE" \
    --content-type "application/json" \
    --overwrite false \
    "${STORAGE_AUTH_ARGS[@]}" \
    --output none

  log "Versioned style URL: $(versioned_style_url)"
}

upload_latest_alias() {
  if [[ "$UPDATE_LATEST" != "true" ]]; then
    log "Skipping stable alias update (UPDATE_LATEST=$UPDATE_LATEST)."
    return 0
  fi

  ensure_storage_auth_args

  log "Updating stable alias: $STYLE_FILE -> $CONTAINER_NAME/$STYLE_LATEST_BLOB"
  az storage blob upload \
    --account-name "$STORAGE_ACCOUNT" \
    --container-name "$CONTAINER_NAME" \
    --name "$STYLE_LATEST_BLOB" \
    --file "$STYLE_FILE" \
    --content-type "application/json" \
    --overwrite true \
    "${STORAGE_AUTH_ARGS[@]}" \
    --output none

  log "Stable alias URL: $(latest_style_url)"
}

verify_url() {
  local url="$1"

  local headers
  headers="$(mktemp)"
  curl -sS -I "$url" > "$headers"

  if ! grep -Ei '^HTTP/.* 200' "$headers" >/dev/null; then
    log "Expected HTTP 200 for $url"
    cat "$headers"
    rm -f "$headers"
    exit 1
  fi

  if ! grep -Ei '^Content-Type:.*application/json' "$headers" >/dev/null; then
    log "Expected Content-Type application/json for $url"
    cat "$headers"
    rm -f "$headers"
    exit 1
  fi

  local body
  body="$(mktemp)"
  curl -sS "$url" -o "$body"

  if command -v jq >/dev/null 2>&1; then
    jq empty "$body" >/dev/null
  else
    python3 -m json.tool "$body" >/dev/null
  fi

  rm -f "$headers" "$body"
}

verify_endpoint() {
  log "Verifying style endpoint: $(versioned_style_url)"
  verify_url "$(versioned_style_url)"

  if [[ "$UPDATE_LATEST" == "true" ]]; then
    log "Verifying style endpoint: $(latest_style_url)"
    verify_url "$(latest_style_url)"
  fi

  log "Verification succeeded."
}

usage() {
  cat <<EOF
Usage: $(basename "$0") [all|upload|verify]

Environment variables:
  RESOURCE_GROUP      Azure resource group (default: paraInfraGIS-rg)
  STORAGE_ACCOUNT     Blob storage account (default: paragisstorage)
  CONTAINER_NAME      Blob container (default: styles)
  STYLE_FILE          Local style file path (default: src/styles/para-latest.json)
  STYLE_DATE          Version token for naming (default: today YYYYMMDD; can include git hash)
  STYLE_BLOB_NAME     Versioned style blob base name (default: style-vYYYYMMDD.json)
  AUTO_INCREMENT_STYLE_BLOB true|false; when true, appends -NNN counter (default: true)
  STYLE_COUNTER_START Counter start value for auto-increment (default: 1)
  STYLE_COUNTER_PAD   Counter zero padding width (default: 3)
  STYLE_LATEST_BLOB   Stable alias blob name (default: style-latest.json)
  UPDATE_LATEST       true|false, publish stable alias (default: true)
  AZ_SUBSCRIPTION_ID  Optional explicit subscription id
  STORAGE_AUTH_MODE   login|key (default: login)
  AZURE_STORAGE_KEY   Optional key for STORAGE_AUTH_MODE=key

Examples:
  $0 upload
  STYLE_DATE=20260331 $0 all
  STYLE_BLOB_NAME=para-dark-v20260403.json $0 all
  AUTO_INCREMENT_STYLE_BLOB=false STYLE_BLOB_NAME=style-v20260403-abcdef0.json $0 all
  STORAGE_AUTH_MODE=key UPDATE_LATEST=false $0 all
EOF
}

main() {
  require_cmd az
  require_cmd curl
  verify_azure_login
  set_subscription_context

  case "$ACTION" in
    all)
      upload_versioned
      upload_latest_alias
      verify_endpoint
      ;;
    upload)
      upload_versioned
      upload_latest_alias
      ;;
    verify)
      require_cmd python3
      verify_endpoint
      ;;
    -h|--help|help)
      usage
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"