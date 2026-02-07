#!/bin/bash
# Complete test script for Prometheus + MaaS integration

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAAS_PORT=3000
PROM_PORT=9090

echo "======================================"
echo "Prometheus + MaaS Integration Test"
echo "======================================"

# Step 1: Build and start MaaS backend
echo ""
echo "[1/5] Starting MaaS backend server..."
cd "$SCRIPT_DIR/maas-backend"

# Check if already running
if lsof -Pi :$MAAS_PORT -sTCP:LISTEN -t >/dev/null 2>&1 ; then
    echo "⚠️  MaaS server already running on port $MAAS_PORT"
    PID=$(lsof -Pi :$MAAS_PORT -sTCP:LISTEN -t)
    echo "   Kill it with: kill $PID"
else
    echo "Building MaaS backend..."
    cargo build --release 2>&1 | tail -5
    
    echo "Starting MaaS backend on http://localhost:$MAAS_PORT"
    nohup cargo run --release > /tmp/maas.log 2>&1 &
    MAAS_PID=$!
    echo "MaaS PID: $MAAS_PID"
    sleep 3
    
    # Verify MaaS is running
    if curl -s http://localhost:$MAAS_PORT/health > /dev/null; then
        echo "✓ MaaS backend is healthy"
    else
        echo "✗ MaaS backend failed to start"
        exit 1
    fi
fi

# Step 2: Show MaaS configuration
echo ""
echo "[2/5] MaaS Configuration:"
curl -s http://localhost:$MAAS_PORT/stats | python3 -m json.tool 2>/dev/null || curl -s http://localhost:$MAAS_PORT/stats

# Step 3: Start Prometheus with MaaS integration
echo ""
echo "[3/5] Starting Prometheus with MaaS integration..."
cd "$SCRIPT_DIR/prometheus"

# Check if already running
if lsof -Pi :$PROM_PORT -sTCP:LISTEN -t >/dev/null 2>&1 ; then
    echo "⚠️  Prometheus already running on port $PROM_PORT"
    PID=$(lsof -Pi :$PROM_PORT -sTCP:LISTEN -t)
    echo "   Kill it with: kill $PID"
else
    # Create minimal prometheus.yml if it doesn't exist
    if [ ! -f "prometheus-test.yml" ]; then
        cat > prometheus-test.yml <<EOF
global:
  scrape_interval: 5s
  evaluation_interval: 5s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
  
  - job_name: 'maas'
    static_configs:
      - targets: ['localhost:3000']
    metrics_path: '/metrics'
EOF
    fi
    
    echo "Starting Prometheus with MaaS at http://localhost:$MAAS_PORT"
    nohup ./prometheus \
        --config.file=prometheus-test.yml \
        --storage.tsdb.path=/tmp/prometheus-data \
        --storage.tsdb.maas.url=http://localhost:$MAAS_PORT \
        --storage.tsdb.maas.fallback=true \
        --web.listen-address=:$PROM_PORT \
        > /tmp/prometheus.log 2>&1 &
    PROM_PID=$!
    echo "Prometheus PID: $PROM_PID"
    sleep 5
    
    # Verify Prometheus is running
    if curl -s http://localhost:$PROM_PORT/-/healthy > /dev/null; then
        echo "✓ Prometheus is healthy"
    else
        echo "✗ Prometheus failed to start"
        echo "Check logs: tail -f /tmp/prometheus.log"
        exit 1
    fi
fi

# Step 4: Monitor MaaS allocations
echo ""
echo "[4/5] Monitoring MaaS allocations..."
echo "Waiting 10 seconds for data to accumulate..."
sleep 10

echo ""
echo "Current MaaS Statistics:"
curl -s http://localhost:$MAAS_PORT/stats | python3 -m json.tool 2>/dev/null || curl -s http://localhost:$MAAS_PORT/stats

# Step 5: Instructions
echo ""
echo "[5/5] Test Setup Complete!"
echo "======================================"
echo ""
echo "📊 Monitoring URLs:"
echo "  - Prometheus UI:    http://localhost:$PROM_PORT"
echo "  - MaaS Stats:       http://localhost:$MAAS_PORT/stats"
echo "  - MaaS Metrics:     http://localhost:$MAAS_PORT/metrics"
echo "  - MaaS Health:      http://localhost:$MAAS_PORT/health"
echo ""
echo "📝 Log Files:"
echo "  - MaaS logs:        tail -f /tmp/maas.log"
echo "  - Prometheus logs:  tail -f /tmp/prometheus.log"
echo ""
echo "🔍 To monitor MaaS usage in real-time:"
echo "  watch -n 2 'curl -s http://localhost:3000/stats | python3 -m json.tool'"
echo ""
echo "📈 Test queries in Prometheus:"
echo "  - View MaaS metrics: {job=\"maas\"}"
echo "  - Check allocations: maas_active_allocations"
echo "  - Check pool usage:  maas_pool_size_bytes"
echo ""
echo "🛑 To stop services:"
echo "  pkill -f 'prometheus.*maas.url'"
echo "  pkill -f 'cargo run.*maas-backend'"
echo ""
