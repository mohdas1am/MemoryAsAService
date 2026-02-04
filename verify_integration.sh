#!/bin/bash
set -e

# Cleanup any existing processes
pkill maas-backend || true
pkill prometheus || true

echo "Starting MaaS Backend..."
cd maas-backend
nohup cargo run > ../maas.log 2>&1 &
MAAS_PID=$!
cd ..

echo "Waiting for MaaS..."
sleep 10
curl -s http://localhost:3000/health | grep "healthy"

echo "Starting Prometheus..."
# Assuming prometheus binary is built in prometheus/prometheus
nohup ./prometheus/prometheus --config.file=prometheus.yml --web.listen-address=:9091 > prometheus.log 2>&1 &
PROM_PID=$!

echo "Waiting for Prometheus..."
sleep 10

echo "1. Verify Target Health"
# Check if Prometheus sees the target as UP (state="up")
curl -s http://localhost:9091/api/v1/targets | grep '"health":"up"'
echo "Target is UP"

echo "2. Generate Load"
curl -X POST http://localhost:3000/allocate -H "Content-Type: application/json" -d '{"size_bytes": 10485760}'
sleep 5 # Wait for scrape interval (5s)

echo "3. Verify Scraped Metrics"
# Query active_allocations from Prometheus
RESULT=$(curl -s 'http://localhost:9091/api/v1/query?query=active_allocations')
echo $RESULT | grep '"value":\[.*"1"\]'
echo "Prometheus Successfully Scraped active_allocations=1"

echo "Cleanup..."
kill $MAAS_PID
kill $PROM_PID
echo "Integration Verification Passed"
