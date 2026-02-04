#!/bin/bash
# Clean Demo Startup - No initial allocations from Prometheus

set -e

echo "🚀 Starting Clean MaaS Demo (No Initial Allocations)..."

# Cleanup
echo "📦 Cleaning up old processes and data..."
pkill -f "target/debug/maas-backend" || true
pkill -f "./prometheus/prometheus" || true
sleep 2

# Clean data to ensure fresh start
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

# Show initial state (should be 0)
echo ""
echo "📊 Initial MaaS State:"
curl -s http://127.0.0.1:3000/metrics | grep "active_allocations"
echo ""

echo "✅ MaaS Backend is running!"
echo ""
echo "📝 NOTE: Prometheus is NOT started to avoid initial allocations."
echo "   You will allocate memory manually using simulate_client.sh"
echo ""
echo "🌐 URLs:"
echo "   - MaaS Metrics:  http://localhost:3000/metrics"
echo "   - MaaS Stats:    http://localhost:3000/stats"
echo ""
echo "🎬 To start demo:"
echo "   Terminal 1: Already running (this terminal - MaaS logs)"
echo "   Terminal 2: watch -n 1 'curl -s http://127.0.0.1:3000/metrics | grep active_allocations'"
echo "   Terminal 3: ./simulate_client.sh"
echo ""
echo "Press Ctrl+C to stop MaaS backend"
echo ""

# Keep MaaS running
wait
