#!/bin/bash
# Burst Allocation Script - Allocate multiple times quickly
# Great for showing a dramatic spike in the Prometheus graph

MAAS_URL="http://127.0.0.1:3000"
ALLOCATION_SIZE=524288  # 512KB per allocation
NUM_ALLOCATIONS=${1:-10}  # Default 10 allocations

echo "💥 Burst Allocation Demo"
echo "========================"
echo "Allocating ${ALLOCATION_SIZE} bytes × ${NUM_ALLOCATIONS} times"
echo ""

# Check if MaaS is running
if ! curl -s "${MAAS_URL}/health" | grep -q "healthy"; then
    echo "❌ Error: MaaS backend is not running!"
    exit 1
fi

# Show initial state
INITIAL=$(curl -s "${MAAS_URL}/metrics" | grep "active_allocations" | grep -v "#" | awk '{print $2}')
echo "📊 Before: ${INITIAL} allocations"
echo ""

# Burst allocate
echo "🚀 Allocating..."
for i in $(seq 1 ${NUM_ALLOCATIONS}); do
    RESPONSE=$(curl -s -X POST "${MAAS_URL}/allocate" \
        -H "Content-Type: application/json" \
        -d "{\"size_bytes\": ${ALLOCATION_SIZE}}")
    
    UUID=$(echo "$RESPONSE" | grep -o '"id":"[^"]*"' | cut -d'"' -f4)
    
    if [ -n "$UUID" ]; then
        echo "  [$i/${NUM_ALLOCATIONS}] ✅ ${UUID}"
    else
        echo "  [$i/${NUM_ALLOCATIONS}] ❌ Failed"
    fi
    
    sleep 0.2  # Small delay to avoid overwhelming the server
done

echo ""

# Show final state
sleep 1
FINAL=$(curl -s "${MAAS_URL}/metrics" | grep "active_allocations" | grep -v "#" | awk '{print $2}')
echo "📊 After: ${FINAL} allocations"
echo "📈 Increase: $((FINAL - INITIAL)) allocations"
echo ""
echo "🌐 Check Prometheus graph at: http://localhost:9091/graph"
echo "   Query: active_allocations"
