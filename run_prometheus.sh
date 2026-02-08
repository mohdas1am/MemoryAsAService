#!/bin/bash
# Run Prometheus independently, with or without MaaS
#
# Usage:
#   ./run_prometheus.sh with-maas                          # WITH MaaS at localhost:3000
#   ./run_prometheus.sh with-maas --maas-url http://192.168.1.10:3000  # MaaS on remote server
#   ./run_prometheus.sh no-maas                            # WITHOUT MaaS (baseline comparison)
#   ./run_prometheus.sh with-maas --clean                  # Wipe old TSDB data first
#   ./run_prometheus.sh with-maas --build                  # Rebuild before starting

set -e

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROM_DIR="$ROOT_DIR/prometheus"
PROM_CONFIG="$ROOT_DIR/prometheus.yml"
PROM_DATA="$ROOT_DIR/data"

MODE="${1:-}"
shift 2>/dev/null || true

MAAS_URL="http://localhost:3000"
CLEAN=false
BUILD=false

if [ "$MODE" != "no-maas" ] && [ "$MODE" != "with-maas" ]; then
    echo "Usage: $0 [no-maas|with-maas] [OPTIONS]"
    echo ""
    echo "Modes:"
    echo "  no-maas     Start Prometheus WITHOUT MaaS (baseline comparison)"
    echo "  with-maas   Start Prometheus WITH MaaS memory extension"
    echo ""
    echo "Options:"
    echo "  --maas-url URL   MaaS backend URL (default: http://localhost:3000)"
    echo "  --clean          Delete old TSDB data before starting"
    echo "  --build          Rebuild Prometheus before starting"
    echo ""
    echo "Examples:"
    echo "  Terminal 1: ./run_maas.sh"
    echo "  Terminal 2: ./run_prometheus.sh with-maas"
    echo ""
    echo "  Two servers:"
    echo "    Server A: ./run_maas.sh"
    echo "    Server B: ./run_prometheus.sh with-maas --maas-url http://server-a:3000"
    echo ""
    echo "  Compare with vs without:"
    echo "    Run 1: ./run_prometheus.sh no-maas --clean"
    echo "    Run 2: ./run_prometheus.sh with-maas --clean"
    exit 1
fi

while [[ $# -gt 0 ]]; do
    case $1 in
        --maas-url) MAAS_URL="$2"; shift 2 ;;
        --clean)    CLEAN=true; shift ;;
        --build)    BUILD=true; shift ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Kill existing Prometheus
pkill -f "prometheus.*config.file" 2>/dev/null || true
sleep 1

# Build if requested
if [ "$BUILD" = true ]; then
    echo "=== Building Prometheus ==="
    cd "$PROM_DIR"
    PREBUILT_ASSETS_STATIC_DIR="$PROM_DIR/web/ui/static" make build 2>&1
    echo "Build complete."
    cd "$ROOT_DIR"
fi

# Clean data if requested
if [ "$CLEAN" = true ]; then
    echo "Cleaning TSDB data..."
    rm -rf "$PROM_DATA"
fi

# Build command flags
MAAS_FLAGS=""
if [ "$MODE" = "with-maas" ]; then
    MAAS_FLAGS="--storage.tsdb.maas.url=$MAAS_URL --storage.tsdb.maas.fallback"

    echo "=========================================="
    echo "  Starting Prometheus WITH MaaS"
    echo "=========================================="
    echo "  MaaS URL:       $MAAS_URL"
    echo "  TSDB path:      $PROM_DATA"
    echo "  Prometheus UI:  http://localhost:9090"
    echo ""
    echo "  Key queries to try in Prometheus UI:"
    echo "    prometheus_tsdb_maas_enabled"
    echo "    prometheus_tsdb_maas_available"
    echo "    prometheus_tsdb_memory_total_available_bytes"
    echo "    prometheus_tsdb_memory_maas_capacity_bytes"
    echo "    prometheus_tsdb_memory_maas_free_bytes"
    echo "    prometheus_tsdb_maas_chunks_allocated_total"
    echo "=========================================="
    echo ""

    # Verify MaaS is reachable
    if ! curl -s "$MAAS_URL/health" > /dev/null 2>&1; then
        echo "WARNING: MaaS backend at $MAAS_URL is not reachable."
        echo "         Start it first with: ./run_maas.sh"
        echo "         (Prometheus will start but MaaS metrics will show 0)"
        echo ""
    else
        echo "MaaS backend is healthy."
        echo ""
    fi
else
    echo "=========================================="
    echo "  Starting Prometheus WITHOUT MaaS"
    echo "=========================================="
    echo "  TSDB path:      $PROM_DATA"
    echo "  Prometheus UI:  http://localhost:9090"
    echo ""
    echo "  Without MaaS, these metrics will NOT exist:"
    echo "    prometheus_tsdb_maas_enabled          (absent)"
    echo "    prometheus_tsdb_memory_maas_*          (absent)"
    echo "    prometheus_tsdb_memory_total_available_bytes (absent)"
    echo ""
    echo "  You can only see local memory via Go runtime metrics:"
    echo "    go_memstats_heap_inuse_bytes"
    echo "=========================================="
    echo ""
fi

# Run in foreground
exec "$PROM_DIR/prometheus" \
    --config.file="$PROM_CONFIG" \
    --storage.tsdb.path="$PROM_DATA" \
    $MAAS_FLAGS \
    --web.enable-lifecycle \
    --log.level=info
