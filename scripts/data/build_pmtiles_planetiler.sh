#!/usr/bin/env bash
set -euo pipefail

# Build a PMTiles archive from a local OSM PBF using Planetiler in Docker.
# This script pre-downloads required OpenMapTiles sources with resume/retry,
# validates archives, then runs Planetiler without remote source downloads.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

DATA_DIR="$REPO_ROOT/data"
SOURCES_DIR="$DATA_DIR/sources"
PMTILES_DIR="$DATA_DIR/pmtiles"
INPUT_PBF="${INPUT_PBF:-$DATA_DIR/philippines-260326.osm.pbf}"
OUTPUT_PMTILES="${OUTPUT_PMTILES:-$PMTILES_DIR/philippines-260326.pmtiles}"
PLANETILER_IMAGE="${PLANETILER_IMAGE:-ghcr.io/onthegomap/planetiler:latest}"
JAVA_XMX="${JAVA_XMX:-8g}"

LAKE_URL="https://osmdata.openstreetmap.de/download/lake_centerline.shp.zip"
WATER_URL="https://osmdata.openstreetmap.de/download/water-polygons-split-3857.zip"
NATURAL_EARTH_URL="https://naciscdn.org/naturalearth/packages/natural_earth_vector.sqlite.zip"

LAKE_ZIP="$SOURCES_DIR/lake_centerline.shp.zip"
WATER_ZIP="$SOURCES_DIR/water-polygons-split-3857.zip"
NATURAL_EARTH_ZIP="$SOURCES_DIR/natural_earth_vector.sqlite.zip"

log() {
  printf "[%s] %s\n" "$(date +"%Y-%m-%d %H:%M:%S")" "$*"
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    log "Missing required command: $1"
    exit 1
  fi
}

download_zip_with_retry() {
  local url="$1"
  local out="$2"
  local max_attempts="${3:-12}"

  mkdir -p "$(dirname "$out")"

  if [[ -f "$out" ]] && unzip -tq "$out" >/dev/null 2>&1; then
    log "Using cached zip: $(basename "$out")"
    return 0
  fi

  local attempt
  for attempt in $(seq 1 "$max_attempts"); do
    log "Downloading $(basename "$out") (attempt $attempt/$max_attempts)..."

    # Try resume first; if server does not support byte ranges, retry as a full download.
    if curl -L \
      --retry 20 \
      --retry-delay 5 \
      --retry-connrefused \
      --continue-at - \
      --output "$out" \
      "$url"; then
      if unzip -tq "$out" >/dev/null 2>&1; then
        log "Validated zip: $(basename "$out")"
        return 0
      fi
    else
      log "Resume failed for $(basename "$out"), retrying with a full download..."
      rm -f "$out"
      if curl -L \
        --retry 20 \
        --retry-delay 5 \
        --retry-connrefused \
        --output "$out" \
        "$url"; then
        if unzip -tq "$out" >/dev/null 2>&1; then
          log "Validated zip: $(basename "$out")"
          return 0
        fi
      fi
    fi

    log "Validation failed for $(basename "$out"). Retrying..."
    sleep 5
  done

  log "Failed to fetch a valid archive after $max_attempts attempts: $url"
  return 1
}

main() {
  require_cmd docker
  require_cmd curl
  require_cmd unzip

  log "Checking Docker CLI and daemon..."
  docker --version >/dev/null
  docker info >/dev/null

  if [[ ! -f "$INPUT_PBF" ]]; then
    log "Input PBF not found: $INPUT_PBF"
    exit 1
  fi

  mkdir -p "$SOURCES_DIR" "$PMTILES_DIR"

  # Refresh or bootstrap required source files used by the OpenMapTiles profile.
  download_zip_with_retry "$LAKE_URL" "$LAKE_ZIP"
  download_zip_with_retry "$WATER_URL" "$WATER_ZIP"
  download_zip_with_retry "$NATURAL_EARTH_URL" "$NATURAL_EARTH_ZIP"

  log "Running Planetiler (offline source mode)..."
  docker run --rm \
    --ulimit nofile=65536:65536 \
    -e "JAVA_TOOL_OPTIONS=-Xmx$JAVA_XMX" \
    -v "$DATA_DIR:/data" \
    "$PLANETILER_IMAGE" \
    --download=false \
    --osm_path=/data/$(basename "$INPUT_PBF") \
    --lake_centerlines_path=/data/sources/$(basename "$LAKE_ZIP") \
    --water_polygons_path=/data/sources/$(basename "$WATER_ZIP") \
    --natural_earth_path=/data/sources/$(basename "$NATURAL_EARTH_ZIP") \
    --output=/data/pmtiles/$(basename "$OUTPUT_PMTILES") \
    --force

  log "Build complete: $OUTPUT_PMTILES"
  ls -lh "$OUTPUT_PMTILES"
}

main "$@"
