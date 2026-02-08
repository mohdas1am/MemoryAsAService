#!/bin/bash
# Run MaaS Backend independently
# Usage: ./run_maas.sh [--host HOST] [--port PORT] [--pool-size-mb MB] [--build]
#
# Examples:
#   ./run_maas.sh                          # defaults: 0.0.0.0:3000, 1GB pool
#   ./run_maas.sh --pool-size-mb 512       # 512MB pool
#   ./run_maas.sh --host 0.0.0.0 --port 3000 --build

set -e
export PATH="$HOME/.rustup/toolchains/stable-x86_64-unknown-linux-gnu/bin:$HOME/.cargo/bin:/usr/bin:/bin:/usr/local/bin:$PATH"

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
MAAS_DIR="$ROOT_DIR/maas-backend"

HOST=""
PORT=""
POOL_MB=""
BUILD=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --host)    HOST="$2"; shift 2 ;;
        --port)    PORT="$2"; shift 2 ;;
        --pool-size-mb) POOL_MB="$2"; shift 2 ;;
        --build)   BUILD=true; shift ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Kill existing
pkill -f "maas-backend" 2>/dev/null || true
sleep 1

# Build if requested
if [ "$BUILD" = true ]; then
    echo "=== Building MaaS Backend ==="
    cd "$MAAS_DIR"
    cargo build --release 2>&1
    echo "Build complete."
    cd "$ROOT_DIR"
fi

# Set env overrides
[ -n "$HOST" ] && export SERVER_HOST="$HOST"
[ -n "$PORT" ] && export SERVER_PORT="$PORT"
if [ -n "$POOL_MB" ]; then
    POOL_BYTES=$((POOL_MB * 1048576))
    export MAX_POOL_SIZE="$POOL_BYTES"
fi

echo "=== Starting MaaS Backend ==="
cd "$MAAS_DIR"
if [ -f "target/release/maas-backend" ]; then
    ./target/release/maas-backend
else
    cargo run --release
fi
