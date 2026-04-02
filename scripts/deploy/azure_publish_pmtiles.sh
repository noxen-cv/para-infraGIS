#!/usr/bin/env bash
set -euo pipefail

# Provision Azure Blob infra, upload PMTiles, configure CORS for range requests,
# and verify partial-content behavior required by PMTiles clients.

RESOURCE_GROUP="${RESOURCE_GROUP:-paraInfraGIS-rg}"
LOCATION="${LOCATION:-southeastasia}"
STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-paragisstorage}"
CONTAINER_NAME="${CONTAINER_NAME:-maps}"
LOCAL_FILE="${LOCAL_FILE:-data/pmtiles/philippines-260326.pmtiles}"
BLOB_NAME="${BLOB_NAME:-$(basename "$LOCAL_FILE")}" 
MAX_AGE_SECONDS="${MAX_AGE_SECONDS:-3600}"
AZ_SUBSCRIPTION_ID="${AZ_SUBSCRIPTION_ID:-}"
STORAGE_AUTH_MODE="${STORAGE_AUTH_MODE:-login}"
AZURE_STORAGE_KEY="${AZURE_STORAGE_KEY:-}"
BLOB_OVERWRITE="${BLOB_OVERWRITE:-false}"

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
  if [[ ! -f "$LOCAL_FILE" ]]; then
    log "Local PMTiles file not found: $LOCAL_FILE"
    exit 1
  fi
}

blob_url() {
  printf "https://%s.blob.core.windows.net/%s/%s" "$STORAGE_ACCOUNT" "$CONTAINER_NAME" "$BLOB_NAME"
}

provision_infra() {
  log "Creating/ensuring resource group: $RESOURCE_GROUP ($LOCATION)"
  az group create \
    --name "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --output none

  log "Creating/ensuring storage account: $STORAGE_ACCOUNT"
  az storage account create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$STORAGE_ACCOUNT" \
    --location "$LOCATION" \
    --sku Standard_LRS \
    --kind StorageV2 \
    --allow-blob-public-access true \
    --min-tls-version TLS1_2 \
    --https-only true \
    --output none

  log "Creating/ensuring public blob container: $CONTAINER_NAME"
  ensure_storage_auth_args
  az storage container create \
    --name "$CONTAINER_NAME" \
    --public-access blob \
    --account-name "$STORAGE_ACCOUNT" \
    "${STORAGE_AUTH_ARGS[@]}" \
    --output none
}

upload_pmtiles() {
  assert_file_exists

  local size
  size="$(wc -c < "$LOCAL_FILE")"
  log "Uploading PMTiles ($size bytes): $LOCAL_FILE -> $CONTAINER_NAME/$BLOB_NAME"

  ensure_storage_auth_args

  local -a overwrite_arg=()
  [[ "$BLOB_OVERWRITE" == "true" ]] && overwrite_arg=(--overwrite)

  az storage blob upload \
    --account-name "$STORAGE_ACCOUNT" \
    --container-name "$CONTAINER_NAME" \
    --name "$BLOB_NAME" \
    --file "$LOCAL_FILE" \
    "${overwrite_arg[@]}" \
    "${STORAGE_AUTH_ARGS[@]}" \
    --output none

  log "Upload complete: $(blob_url)"
}

configure_cors() {
  local -a cors_auth_args

  ensure_storage_auth_args
  cors_auth_args=()
  if [[ "$STORAGE_AUTH_MODE" == "key" ]]; then
    cors_auth_args=(--account-key "$AZURE_STORAGE_KEY")
  fi

  log "Clearing existing Blob CORS rules to avoid overlap"
  az storage cors clear \
    --services b \
    --account-name "$STORAGE_ACCOUNT" \
    "${cors_auth_args[@]}" \
    --output none

  log "Applying PMTiles-safe CORS rule (GET, HEAD, OPTIONS + Range + Content-Range exposure)"
  az storage cors add \
    --services b \
    --methods GET HEAD OPTIONS \
    --origins '*' \
    --allowed-headers 'Range,Content-Type,Origin,Accept,If-Modified-Since,If-None-Match,Cache-Control,x-ms-*' \
    --exposed-headers 'Content-Range,Accept-Ranges,Content-Length,Content-Type,ETag,Last-Modified' \
    --max-age "$MAX_AGE_SECONDS" \
    --account-name "$STORAGE_ACCOUNT" \
    "${cors_auth_args[@]}" \
    --output none
}

verify_endpoint() {
  local url
  url="$(blob_url)"

  log "Checking blob headers: $url"
  local head_headers
  head_headers="$(mktemp)"
  curl -sS -I "$url" > "$head_headers"

  if ! grep -Ei '^HTTP/.* (200|206)' "$head_headers" >/dev/null; then
    log "HEAD check failed. Response headers:"
    cat "$head_headers"
    rm -f "$head_headers"
    exit 1
  fi

  log "Running byte-range check: Range: bytes=0-255"
  local range_headers range_body status_line
  range_headers="$(mktemp)"
  range_body="$(mktemp)"

  curl -sS -D "$range_headers" -H 'Range: bytes=0-255' "$url" -o "$range_body"

  status_line="$(awk '/^HTTP\// {s=$0} END {print s}' "$range_headers")"
  printf "%s\n" "$status_line"

  if ! echo "$status_line" | grep -q ' 206 '; then
    log "Expected HTTP 206 Partial Content but got: $status_line"
    log "Full response headers:"
    cat "$range_headers"
    rm -f "$head_headers" "$range_headers" "$range_body"
    exit 1
  fi

  local content_range
  content_range="$(grep -Ei '^Content-Range:' "$range_headers" | tail -n 1 || true)"
  printf "%s\n" "$content_range"

  if [[ -z "$content_range" ]]; then
    log "Missing Content-Range header in range response"
    log "Full response headers:"
    cat "$range_headers"
    rm -f "$head_headers" "$range_headers" "$range_body"
    exit 1
  fi

  log "Running CORS preflight simulation (OPTIONS + range request header)"
  local preflight_headers
  preflight_headers="$(mktemp)"
  curl -sS -D "$preflight_headers" -o /dev/null -X OPTIONS "$url" \
    -H 'Origin: https://example.com' \
    -H 'Access-Control-Request-Method: GET' \
    -H 'Access-Control-Request-Headers: range'

  if ! grep -Ei '^HTTP/.* (200|204)' "$preflight_headers" >/dev/null; then
    log "CORS preflight did not return 200/204. Headers:"
    cat "$preflight_headers"
    rm -f "$head_headers" "$range_headers" "$range_body" "$preflight_headers"
    exit 1
  fi

  # Azure may echo the caller origin even when AllowedOrigins is '*'.
  if ! grep -Ei '^Access-Control-Allow-Origin:\s*(\*|https://example.com)' "$preflight_headers" >/dev/null; then
    log "CORS preflight did not return expected allow-origin. Headers:"
    cat "$preflight_headers"
    rm -f "$head_headers" "$range_headers" "$range_body" "$preflight_headers"
    exit 1
  fi

  if ! grep -Ei '^Access-Control-Allow-Headers:.*range' "$preflight_headers" >/dev/null; then
    log "CORS preflight did not allow Range header. Headers:"
    cat "$preflight_headers"
    rm -f "$head_headers" "$range_headers" "$range_body" "$preflight_headers"
    exit 1
  fi

  log "Binary sample (first 48 bytes from PMTiles):"
  LC_ALL=C head -c 48 "$range_body" | cat
  printf "\n"

  rm -f "$head_headers" "$range_headers" "$range_body" "$preflight_headers"

  log "Verification succeeded. PMTiles endpoint is range-compatible."
}

usage() {
  cat <<EOF
Usage: $(basename "$0") [all|provision|upload|cors|verify]

Environment overrides:
  RESOURCE_GROUP   (default: $RESOURCE_GROUP)
  LOCATION         (default: $LOCATION)
  STORAGE_ACCOUNT  (default: $STORAGE_ACCOUNT)
  CONTAINER_NAME   (default: $CONTAINER_NAME)
  LOCAL_FILE       (default: $LOCAL_FILE)
  BLOB_NAME        (default: basename of LOCAL_FILE)
  MAX_AGE_SECONDS  (default: $MAX_AGE_SECONDS)
  AZ_SUBSCRIPTION_ID (default: current `az account show` subscription)
  STORAGE_AUTH_MODE (default: $STORAGE_AUTH_MODE; values: login|key)
  AZURE_STORAGE_KEY (optional; used when STORAGE_AUTH_MODE=key)
  BLOB_OVERWRITE    (default: $BLOB_OVERWRITE; set to true to overwrite an existing blob)

Examples:
  $(basename "$0") all
  STORAGE_AUTH_MODE=key $(basename "$0") all
  BLOB_NAME=philippines-260326.pmtiles $(basename "$0") upload
  $(basename "$0") verify
EOF
}

main() {
  require_cmd az
  require_cmd curl

  case "$ACTION" in
    all)
      verify_azure_login
      set_subscription_context
      provision_infra
      upload_pmtiles
      configure_cors
      verify_endpoint
      ;;
    provision)
      verify_azure_login
      set_subscription_context
      provision_infra
      ;;
    upload)
      verify_azure_login
      set_subscription_context
      upload_pmtiles
      ;;
    cors)
      verify_azure_login
      set_subscription_context
      configure_cors
      ;;
    verify)
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