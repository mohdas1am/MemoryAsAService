#!/bin/bash
set -e

# Cleanup any existing processes
pkill -f "target/debug/maas-backend" || true
pkill -f "./prometheus/prometheus" || true

echo "Cleaning up old data..."
rm -rf ./data
rm -f prometheus.log

echo "Starting MaaS Backend..."
cd maas-backend
nohup cargo run > ../maas.log 2>&1 &
MAAS_PID=$!
cd ..

# Wait for MaaS to start with retry
echo "Waiting for MaaS to start..."
for i in {1..20}; do
    if curl -s http://127.0.0.1:3000/health | grep "healthy" > /dev/null; then
        echo "MaaS is up!"
        break
    fi
    echo "Waiting for MaaS... ($i/20)"
    sleep 1
done

# Perform explicit check
if ! curl -s http://127.0.0.1:3000/health | grep "healthy"; then
    echo "MaaS failed to start. tailing maas.log:"
    tail -n 20 maas.log
    exit 1
fi

echo "Starting Prometheus (Modified)..."
# We use a config that scrapes MaaS, but the allocation happens via the hook code anyway
nohup ./prometheus/prometheus --config.file=prometheus.yml --web.listen-address=:9091 > prometheus.log 2>&1 &
PROM_PID=$!

echo "Waiting for Prometheus to initialize and trigger allocation..."
sleep 15

# Check active allocations in MaaS
echo "checking active_allocations metric from MaaS..."
ALLOCS=$(curl -s http://127.0.0.1:3000/metrics | grep "active_allocations" | grep -v "#" | awk '{print $2}')
echo "Active Allocations: $ALLOCS"

if [ "$ALLOCS" -gt 0 ]; then
    echo "SUCCESS: Prometheus successfully requested memory from MaaS!"
else
    echo "FAILURE: active_allocations is 0. Integration failed."
    cat prometheus.log
    exit 1
fi

# Cleanup
kill $MAAS_PID
kill $PROM_PID
