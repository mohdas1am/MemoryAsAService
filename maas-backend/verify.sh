#!/bin/bash
set -e

echo "Waiting for server to start..."
sleep 5

echo "1. Health Check"
curl -s http://localhost:3000/health | grep "healthy"
echo -e "\nHealth Check Passed"

echo "2. Allocate Memory (10MB)"
ALLOC_RESP=$(curl -s -X POST http://localhost:3000/allocate -H "Content-Type: application/json" -d '{"size_bytes": 10485760}')
echo $ALLOC_RESP
ID=$(echo $ALLOC_RESP | grep -oP '"id":"\K[^"]+')
echo "Allocated ID: $ID"

echo "3. Check Stats"
curl -s http://localhost:3000/stats
echo -e "\nStats Checked"

echo "4. Check Metrics"
curl -s http://localhost:3000/metrics | grep "active_allocations"
echo -e "\nMetrics Checked"

echo "5. Deallocate Memory"
if [ ! -z "$ID" ]; then
    curl -s -X DELETE http://localhost:3000/allocate/$ID
    echo -e "\nDeallocated"
fi

echo "6. Check Stats Again"
curl -s http://localhost:3000/stats | jq .
echo -e "\nFinal Stats Checked"
