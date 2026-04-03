#!/usr/bin/env bash
set -euo pipefail

# Convert TTF fonts into Mapbox glyph PBF ranges and publish to Azure Blob.

RESOURCE_GROUP="${RESOURCE_GROUP:-paraInfraGIS-rg}"
STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-paragisstorage}"
CONTAINER_NAME="${CONTAINER_NAME:-fonts}"
FONT_SOURCE_DIR="${FONT_SOURCE_DIR:-src/font}"
GLYPH_BLOB_PREFIX="${GLYPH_BLOB_PREFIX:-fonts}"
LOCAL_GLYPHS_DIR="${LOCAL_GLYPHS_DIR:-data/processed/glyphs}"
GLYPH_CONVERTER_CMD="${GLYPH_CONVERTER_CMD:-build-glyphs \"{input}\" \"{output}\"}"
AZ_SUBSCRIPTION_ID="${AZ_SUBSCRIPTION_ID:-}"
STORAGE_AUTH_MODE="${STORAGE_AUTH_MODE:-login}"
AZURE_STORAGE_KEY="${AZURE_STORAGE_KEY:-}"

ACTION="${1:-all}"

declare -a STORAGE_AUTH_ARGS=()
declare -a UPLOADED_BLOBS=()

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

glyph_url() {
  local blob_name="$1"
  printf "https://%s.blob.core.windows.net/%s/%s" "$STORAGE_ACCOUNT" "$CONTAINER_NAME" "$blob_name"
}

assert_font_sources() {
  if [[ ! -d "$FONT_SOURCE_DIR" ]]; then
    log "Font source directory not found: $FONT_SOURCE_DIR"
    exit 1
  fi

  if ! find "$FONT_SOURCE_DIR" -type f \( -name '*.ttf' -o -name '*.TTF' \) | grep -q .; then
    log "No .ttf files found under $FONT_SOURCE_DIR"
    exit 1
  fi
}

run_converter() {
  local input_ttf="$1"
  local converter_cmd

  converter_cmd="${GLYPH_CONVERTER_CMD//\{input\}/$input_ttf}"
  converter_cmd="${converter_cmd//\{output\}/$LOCAL_GLYPHS_DIR}"

  log "Converting $(basename "$input_ttf") to glyph PBF ranges"
  bash -lc "$converter_cmd"
}

convert_fonts() {
  assert_font_sources

  require_cmd bash

  rm -rf "$LOCAL_GLYPHS_DIR"
  mkdir -p "$LOCAL_GLYPHS_DIR"

  while IFS= read -r ttf_file; do
    [[ -n "$ttf_file" ]] || continue
    run_converter "$ttf_file"
  done < <(find "$FONT_SOURCE_DIR" -type f \( -name '*.ttf' -o -name '*.TTF' \) | sort)

  if ! find "$LOCAL_GLYPHS_DIR" -type f -name '*.pbf' | grep -q .; then
    log "No glyph .pbf files were generated in $LOCAL_GLYPHS_DIR"
    log "Set GLYPH_CONVERTER_CMD to a working converter command (example: build-glyphs \"{input}\" \"{output}\")."
    exit 1
  fi

  log "Glyph conversion complete: $LOCAL_GLYPHS_DIR"
}

upload_fonts() {
  ensure_storage_auth_args

  if [[ ! -d "$LOCAL_GLYPHS_DIR" ]]; then
    log "Generated glyph directory not found: $LOCAL_GLYPHS_DIR"
    log "Run convert action first or use ACTION=all."
    exit 1
  fi

  if ! find "$LOCAL_GLYPHS_DIR" -type f -name '*.pbf' | grep -q .; then
    log "No .pbf files found in $LOCAL_GLYPHS_DIR"
    log "Run convert action first or use ACTION=all."
    exit 1
  fi

  while IFS= read -r pbf_file; do
    [[ -n "$pbf_file" ]] || continue

    local rel_path blob_name
    rel_path="${pbf_file#${LOCAL_GLYPHS_DIR}/}"
    blob_name="${GLYPH_BLOB_PREFIX%/}/${rel_path}"

    log "Uploading glyph: $pbf_file -> $CONTAINER_NAME/$blob_name"
    az storage blob upload \
      --account-name "$STORAGE_ACCOUNT" \
      --container-name "$CONTAINER_NAME" \
      --name "$blob_name" \
      --file "$pbf_file" \
      --content-type "application/x-protobuf" \
      --overwrite true \
      "${STORAGE_AUTH_ARGS[@]}" \
      --output none

    UPLOADED_BLOBS+=("$blob_name")
  done < <(find "$LOCAL_GLYPHS_DIR" -type f -name '*.pbf' | sort)

  log "Uploaded ${#UPLOADED_BLOBS[@]} glyph PBF files."
}

resolve_verification_blob() {
  if [[ ${#UPLOADED_BLOBS[@]} -gt 0 ]]; then
    printf "%s" "${UPLOADED_BLOBS[0]}"
    return 0
  fi

  local existing
  existing="$(az storage blob list \
    --account-name "$STORAGE_ACCOUNT" \
    --container-name "$CONTAINER_NAME" \
    --prefix "${GLYPH_BLOB_PREFIX%/}/" \
    "${STORAGE_AUTH_ARGS[@]}" \
    --query "[?ends_with(name, '.pbf')].name | [0]" \
    -o tsv)"

  if [[ -z "$existing" ]]; then
    log "No glyph blob found under prefix ${GLYPH_BLOB_PREFIX%/}/ for verification."
    exit 1
  fi

  printf "%s" "$existing"
}

verify_endpoint() {
  ensure_storage_auth_args

  local blob_name url headers status_line content_type
  blob_name="$(resolve_verification_blob)"
  url="$(glyph_url "$blob_name")"

  log "Verifying glyph endpoint: $url"

  headers="$(mktemp)"
  curl -sS -I "$url" > "$headers"

  status_line="$(grep -Ei '^HTTP/' "$headers" | tail -n 1 || true)"
  if [[ "$status_line" != *" 200 "* ]]; then
    log "Expected HTTP 200 for $url"
    cat "$headers"
    rm -f "$headers"
    exit 1
  fi

  content_type="$(grep -Ei '^Content-Type:' "$headers" | tr -d '\r' || true)"
  if [[ "$content_type" != *"application/x-protobuf"* && "$content_type" != *"application/octet-stream"* ]]; then
    log "Expected protobuf/binary Content-Type for $url"
    cat "$headers"
    rm -f "$headers"
    exit 1
  fi

  rm -f "$headers"
  log "Verification succeeded."
}

usage() {
  cat <<EOF
Usage: $(basename "$0") [all|convert|upload|verify]

Environment variables:
  RESOURCE_GROUP      Azure resource group (default: paraInfraGIS-rg)
  STORAGE_ACCOUNT     Blob storage account (default: paragisstorage)
  CONTAINER_NAME      Blob container for glyphs (default: fonts)
  FONT_SOURCE_DIR     Directory containing source TTF files (default: src/font)
  GLYPH_BLOB_PREFIX   Blob prefix in fonts container (default: fonts)
  LOCAL_GLYPHS_DIR    Local output directory for generated PBFs (default: data/processed/glyphs)
  GLYPH_CONVERTER_CMD Converter command template with {input} and {output}
                      (default: build-glyphs "{input}" "{output}")
  AZ_SUBSCRIPTION_ID  Optional explicit subscription id
  STORAGE_AUTH_MODE   login|key (default: login)
  AZURE_STORAGE_KEY   Optional key for STORAGE_AUTH_MODE=key

Examples:
  $0 all
  $0 convert
  STORAGE_AUTH_MODE=key $0 upload
  GLYPH_CONVERTER_CMD='docker run --rm -v "$PWD":/work ghcr.io/maplibre/font-maker:latest --input "{input}" --output "{output}"' $0 all
EOF
}

main() {
  require_cmd az
  require_cmd curl
  verify_azure_login
  set_subscription_context

  case "$ACTION" in
    all)
      convert_fonts
      upload_fonts
      verify_endpoint
      ;;
    convert)
      convert_fonts
      ;;
    upload)
      upload_fonts
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
