#!/bin/bash
# Demo Script: Start Everything and Open Prometheus UI

set -e

echo "🚀 Starting MaaS + Prometheus Demo..."

# Cleanup
echo "📦 Cleaning up old processes and data..."
pkill -f "target/debug/maas-backend" || true
pkill -f "./prometheus/prometheus" || true
sleep 2

# Clean data to force new chunk creation
rm -rf data
rm -f *.log

# Start MaaS Backend
echo "🔧 Starting MaaS Backend..."
cd maas-backend
nohup cargo run > ../maas.log 2>&1 &
MAAS_PID=$!
cd ..

# Wait for MaaS to be ready
echo "⏳ Waiting for MaaS to start..."
for i in {1..20}; do
    if curl -s http://127.0.0.1:3000/health | grep "healthy" > /dev/null; then
        echo "✅ MaaS is ready!"
        break
    fi
    sleep 1
done

# Show initial state
echo ""
echo "📊 Initial MaaS State:"
curl -s http://127.0.0.1:3000/metrics | grep "active_allocations"
echo ""

# Start Prometheus
echo "🔍 Starting Prometheus..."
nohup ./prometheus/prometheus --config.file=prometheus.yml --web.listen-address=:9091 > prometheus.log 2>&1 &
PROM_PID=$!

echo "⏳ Waiting for Prometheus to initialize (15 seconds)..."
sleep 15

# Show final state
echo ""
echo "📊 Final MaaS State (after Prometheus startup):"
curl -s http://127.0.0.1:3000/metrics | grep "active_allocations"
echo ""

# Show Prometheus logs
echo "📝 Prometheus Memory Requests:"
grep "MaaS: Successfully" prometheus.log | head -5
echo ""

echo "✅ Demo is ready!"
echo ""
echo "🌐 Open these URLs in your browser:"
echo "   - Prometheus UI: http://localhost:9091"
echo "   - MaaS Metrics:  http://localhost:3000/metrics"
echo "   - MaaS Stats:    http://localhost:3000/stats"
echo ""
echo "📈 In Prometheus UI, try these queries:"
echo "   1. active_allocations"
echo "   2. rate(allocation_requests_total[1m])"
echo "   3. allocation_size_bytes"
echo ""
echo "Press Ctrl+C to stop all services"
echo ""

# Keep script running
wait
