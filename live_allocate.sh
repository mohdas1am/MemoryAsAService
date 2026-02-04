#!/bin/bash
# Continuous Allocation Script for Live Demo
# This script allocates memory at regular intervals to show graph updates in Prometheus

MAAS_URL="http://127.0.0.1:3000"
ALLOCATION_SIZE=1048576  # 1MB per allocation
INTERVAL=5  # seconds between allocations

echo "🎬 Live Allocation Demo Script"
echo "================================"
echo "This will allocate ${ALLOCATION_SIZE} bytes every ${INTERVAL} seconds"
echo "Watch the Prometheus graph at: http://localhost:9091/graph"
echo "Query to use: active_allocations"
echo ""
echo "Press Ctrl+C to stop"
echo ""

# Check if MaaS is running
if ! curl -s "${MAAS_URL}/health" | grep -q "healthy"; then
    echo "❌ Error: MaaS backend is not running!"
    echo "Start it with: cd maas-backend && cargo run"
    exit 1
fi

echo "✅ MaaS backend is running"
echo ""

# Show initial state
INITIAL=$(curl -s "${MAAS_URL}/metrics" | grep "active_allocations" | grep -v "#" | awk '{print $2}')
echo "📊 Initial allocations: ${INITIAL}"
echo ""

# Counter
COUNT=0

# Allocate in a loop
while true; do
    COUNT=$((COUNT + 1))
    
    echo -n "[$COUNT] Allocating ${ALLOCATION_SIZE} bytes... "
    
    # Make allocation request
    RESPONSE=$(curl -s -X POST "${MAAS_URL}/allocate" \
        -H "Content-Type: application/json" \
        -d "{\"size_bytes\": ${ALLOCATION_SIZE}}")
    
    # Extract UUID from response
    UUID=$(echo "$RESPONSE" | grep -o '"id":"[^"]*"' | cut -d'"' -f4)
    
    if [ -n "$UUID" ]; then
        echo "✅ Success! UUID: ${UUID}"
        
        # Show current total
        CURRENT=$(curl -s "${MAAS_URL}/metrics" | grep "active_allocations" | grep -v "#" | awk '{print $2}')
        echo "   📈 Total allocations: ${CURRENT}"
        echo ""
    else
        echo "❌ Failed!"
        echo "   Response: $RESPONSE"
        echo ""
    fi
    
    # Wait before next allocation
    sleep ${INTERVAL}
done
