#!/bin/bash
# Quick demo script for MaaS v2

set -e

echo "================================================"
echo "  MaaS v2.0 - Production Memory Server Demo"
echo "================================================"
echo ""

cd "$(dirname "$0")"

# Check if already running
if curl -s http://localhost:3000/health > /dev/null 2>&1; then
    echo "⚠️  Server already running on port 3000"
    read -p "Kill and restart? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        pkill -f "maas-backend" || true
        sleep 2
    else
        echo "Exiting..."
        exit 0
    fi
fi

echo "1️⃣  Building release version..."
cargo build --release

echo ""
echo "2️⃣  Starting MaaS backend..."
cargo run --release > maas.log 2>&1 &
MAAS_PID=$!

echo "   PID: $MAAS_PID"
echo "   Logs: maas.log"

echo ""
echo "3️⃣  Waiting for server to start..."
for i in {1..30}; do
    if curl -s http://localhost:3000/health > /dev/null 2>&1; then
        echo "   ✓ Server ready!"
        break
    fi
    sleep 1
    echo -n "."
done
echo ""

# Show health
echo ""
echo "4️⃣  Server Status:"
curl -s http://localhost:3000/health | jq '{
    status: .status,
    version: .version,
    memory: {
        allocated_mb: .memory.total_allocated_mb,
        utilization: (.memory.utilization_percent | tostring + "%"),
        allocations: .memory.active_allocations
    }
}'

echo ""
echo "5️⃣  Performing sample allocations..."
echo ""

# Allocate some memory
declare -a IDS

echo "   Allocating 100 KB..."
RESP=$(curl -s -X POST http://localhost:3000/allocate -H "Content-Type: application/json" -d '{"size_bytes": 102400}')
ID1=$(echo $RESP | jq -r '.id')
IDS+=($ID1)
echo "   → ID: $ID1 (actual: $(echo $RESP | jq -r '.actual_size_bytes') bytes)"

echo "   Allocating 500 KB..."
RESP=$(curl -s -X POST http://localhost:3000/allocate -H "Content-Type: application/json" -d '{"size_bytes": 512000}')
ID2=$(echo $RESP | jq -r '.id')
IDS+=($ID2)
echo "   → ID: $ID2 (actual: $(echo $RESP | jq -r '.actual_size_bytes') bytes)"

echo "   Allocating 2 MB..."
RESP=$(curl -s -X POST http://localhost:3000/allocate -H "Content-Type: application/json" -d '{"size_bytes": 2097152}')
ID3=$(echo $RESP | jq -r '.id')
IDS+=($ID3)
echo "   → ID: $ID3 (actual: $(echo $RESP | jq -r '.actual_size_bytes') bytes)"

echo ""
echo "6️⃣  Current Statistics:"
curl -s http://localhost:3000/stats | jq '{
    active_allocations: .active_allocations,
    total_in_use_mb: .total_in_use_mb,
    utilization: (.utilization_percent | tostring + "%"),
    pools: [.pool_stats[] | {size: .size, in_use: .in_use_slabs, total: .total_slabs}]
}'

echo ""
echo "7️⃣  Testing deallocation..."
echo "   Deallocating $ID1..."
curl -s -X DELETE http://localhost:3000/allocate/$ID1 > /dev/null
echo "   ✓ Deallocated"

echo ""
echo "8️⃣  Testing slab reuse..."
echo "   Allocating 100 KB again (should reuse slab)..."
RESP=$(curl -s -X POST http://localhost:3000/allocate -H "Content-Type: application/json" -d '{"size_bytes": 102400}')
ID4=$(echo $RESP | jq -r '.id')
echo "   → New ID: $ID4"

echo ""
echo "================================================"
echo "  🎉 Demo Complete!"
echo "================================================"
echo ""
echo "Available endpoints:"
echo "  Health:      curl http://localhost:3000/health"
echo "  Stats:       curl http://localhost:3000/stats"
echo "  Metrics:     curl http://localhost:3000/metrics"
echo "  Allocate:    curl -X POST http://localhost:3000/allocate -H 'Content-Type: application/json' -d '{\"size_bytes\": 1024}'"
echo "  Deallocate:  curl -X DELETE http://localhost:3000/allocate/{id}"
echo ""
echo "View logs:     tail -f maas.log"
echo "Run tests:     ./verify_v2.sh"
echo "Stop server:   kill $MAAS_PID"
echo ""
