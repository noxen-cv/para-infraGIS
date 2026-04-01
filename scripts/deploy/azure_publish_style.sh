#!/usr/bin/env bash
set -euo pipefail

# Upload a versioned style JSON to Azure Blob and optionally update a stable alias.

RESOURCE_GROUP="${RESOURCE_GROUP:-paraInfraGIS-rg}"
STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-paragisstorage}"
CONTAINER_NAME="${CONTAINER_NAME:-maps}"
STYLE_FILE="${STYLE_FILE:-src/styles/v1/para-gold.json}"
STYLE_DATE="${STYLE_DATE:-$(date +%Y%m%d)}"
STYLE_BLOB_NAME="${STYLE_BLOB_NAME:-style-v${STYLE_DATE}.json}"
STYLE_LATEST_BLOB="${STYLE_LATEST_BLOB:-style-latest.json}"
UPDATE_LATEST="${UPDATE_LATEST:-true}"
AZ_SUBSCRIPTION_ID="${AZ_SUBSCRIPTION_ID:-}"
STORAGE_AUTH_MODE="${STORAGE_AUTH_MODE:-login}"
AZURE_STORAGE_KEY="${AZURE_STORAGE_KEY:-}"

declare -a STORAGE_AUTH_ARGS=()
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
  printf "https://%s.blob.core.windows.net/%s/%s" "$STORAGE_ACCOUNT" "$CONTAINER_NAME" "$STYLE_BLOB_NAME"
}

latest_style_url() {
  printf "https://%s.blob.core.windows.net/%s/%s" "$STORAGE_ACCOUNT" "$CONTAINER_NAME" "$STYLE_LATEST_BLOB"
}

upload_versioned() {
  validate_style_json
  ensure_storage_auth_args

  log "Uploading versioned style: $STYLE_FILE -> $CONTAINER_NAME/$STYLE_BLOB_NAME"
  az storage blob upload \
    --account-name "$STORAGE_ACCOUNT" \
    --container-name "$CONTAINER_NAME" \
    --name "$STYLE_BLOB_NAME" \
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
  CONTAINER_NAME      Blob container (default: maps)
  STYLE_FILE          Local style file path (default: src/styles/v1/para-gold.json)
  STYLE_DATE          Version token for naming (default: today YYYYMMDD; can include git hash)
  STYLE_BLOB_NAME     Versioned style blob name (default: style-vYYYYMMDD.json)
  STYLE_LATEST_BLOB   Stable alias blob name (default: style-latest.json)
  UPDATE_LATEST       true|false, publish stable alias (default: true)
  AZ_SUBSCRIPTION_ID  Optional explicit subscription id
  STORAGE_AUTH_MODE   login|key (default: login)
  AZURE_STORAGE_KEY   Optional key for STORAGE_AUTH_MODE=key

Examples:
  $0 upload
  STYLE_DATE=20260331 $0 all
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