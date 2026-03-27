set -eo pipefail
JAVA_XMX="${JAVA_XMX:-2g}"
THREADS="${THREADS:-4}"
TMP_SUBDIR="planetiler-$(date +%s)"

PID=$(pgrep -f "wget -c --timeout=30 --tries=0 --waitretry=5 -O data/sources/water-polygons-split-3857.zip" | head -n 1 || true)
if [ -n "$PID" ]; then
  while kill -0 "$PID" 2>/dev/null; do
    sleep 30
  done
fi
unzip -tq data/sources/water-polygons-split-3857.zip
echo "water-polygons validated"
mkdir -p "data/tmp/$TMP_SUBDIR" data/pmtiles
docker run --rm --ulimit nofile=65536:65536 -e "JAVA_TOOL_OPTIONS=-Xmx$JAVA_XMX" -v "$PWD/data:/data" ghcr.io/onthegomap/planetiler:latest --download=false --threads="$THREADS" --tmpdir="/data/tmp/$TMP_SUBDIR" --osm_path=/data/philippines-260326.osm.pbf --water_polygons_path=/data/sources/water-polygons-split-3857.zip --lake_centerlines_path=/data/sources/lake_centerline.shp.zip --natural_earth_path=/data/sources/natural_earth_vector.sqlite.zip --output=/data/pmtiles/philippines-260326.pmtiles --force
ls -lh data/pmtiles/philippines-260326.pmtiles
file data/pmtiles/philippines-260326.pmtiles
