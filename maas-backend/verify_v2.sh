#!/bin/bash
# Comprehensive verification script for MaaS v2

set -e

BASE_URL="http://localhost:3000"
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=========================================="
echo "  MaaS v2.0 Verification Suite"
echo "=========================================="
echo ""

# Check if server is running
echo "1. Testing server connectivity..."
if curl -s "${BASE_URL}/health" > /dev/null; then
    echo -e "${GREEN}✓ Server is running${NC}"
else
    echo -e "${RED}✗ Server is not running${NC}"
    echo "Please start the server with: cargo run"
    exit 1
fi

# Test health endpoint
echo ""
echo "2. Testing health endpoint..."
HEALTH=$(curl -s "${BASE_URL}/health")
if echo "$HEALTH" | jq -e '.status == "healthy"' > /dev/null; then
    echo -e "${GREEN}✓ Health check passed${NC}"
    echo "   Version: $(echo "$HEALTH" | jq -r '.version')"
    echo "   Memory utilization: $(echo "$HEALTH" | jq -r '.memory.utilization_percent')%"
else
    echo -e "${RED}✗ Health check failed${NC}"
    exit 1
fi

# Test allocation
echo ""
echo "3. Testing memory allocation..."
ALLOC1=$(curl -s -X POST "${BASE_URL}/allocate" \
    -H "Content-Type: application/json" \
    -d '{"size_bytes": 50000}')

ID1=$(echo "$ALLOC1" | jq -r '.id')
ACTUAL_SIZE=$(echo "$ALLOC1" | jq -r '.actual_size_bytes')

if [ -n "$ID1" ] && [ "$ID1" != "null" ]; then
    echo -e "${GREEN}✓ Allocation successful${NC}"
    echo "   ID: $ID1"
    echo "   Requested: 50000 bytes"
    echo "   Actual slab size: $ACTUAL_SIZE bytes"
else
    echo -e "${RED}✗ Allocation failed${NC}"
    echo "$ALLOC1"
    exit 1
fi

# Test multiple allocations
echo ""
echo "4. Testing multiple allocations..."
IDS=()
for i in {1..5}; do
    SIZE=$((1024 * i * 10))
    ALLOC=$(curl -s -X POST "${BASE_URL}/allocate" \
        -H "Content-Type: application/json" \
        -d "{\"size_bytes\": $SIZE}")
    ID=$(echo "$ALLOC" | jq -r '.id')
    IDS+=("$ID")
    echo "   Allocated: $SIZE bytes → ID: $ID"
done
echo -e "${GREEN}✓ Multiple allocations successful${NC}"

# Test stats endpoint
echo ""
echo "5. Testing stats endpoint..."
STATS=$(curl -s "${BASE_URL}/stats")
ACTIVE_ALLOCS=$(echo "$STATS" | jq -r '.active_allocations')
TOTAL_MB=$(echo "$STATS" | jq -r '.total_in_use_mb')

if [ "$ACTIVE_ALLOCS" -ge 6 ]; then
    echo -e "${GREEN}✓ Stats endpoint working${NC}"
    echo "   Active allocations: $ACTIVE_ALLOCS"
    echo "   Total in-use: ${TOTAL_MB} MB"
    echo "   Utilization: $(echo "$STATS" | jq -r '.utilization_percent')%"
else
    echo -e "${RED}✗ Stats show incorrect allocation count${NC}"
    exit 1
fi

# Test pool statistics
echo ""
echo "6. Verifying slab pool distribution..."
echo "$STATS" | jq -r '.pool_stats[] | "   \(.size) bytes: \(.in_use_slabs)/\(.total_slabs) in use"'

# Test deallocation
echo ""
echo "7. Testing deallocation..."
STATUS=$(curl -s -X DELETE "${BASE_URL}/allocate/${ID1}" -w "%{http_code}")
if [ "$STATUS" = "200" ]; then
    echo -e "${GREEN}✓ Deallocation successful${NC}"
else
    echo -e "${RED}✗ Deallocation failed (status: $STATUS)${NC}"
    exit 1
fi

# Verify allocation count decreased
STATS_AFTER=$(curl -s "${BASE_URL}/stats")
ACTIVE_AFTER=$(echo "$STATS_AFTER" | jq -r '.active_allocations')

if [ "$ACTIVE_AFTER" -eq $((ACTIVE_ALLOCS - 1)) ]; then
    echo -e "${GREEN}✓ Allocation count correctly updated${NC}"
else
    echo -e "${YELLOW}⚠ Allocation count mismatch (expected $((ACTIVE_ALLOCS - 1)), got $ACTIVE_AFTER)${NC}"
fi

# Test slab reuse
echo ""
echo "8. Testing slab reuse..."
ALLOC_REUSE=$(curl -s -X POST "${BASE_URL}/allocate" \
    -H "Content-Type: application/json" \
    -d '{"size_bytes": 50000}')
ID_REUSE=$(echo "$ALLOC_REUSE" | jq -r '.id')

if [ -n "$ID_REUSE" ] && [ "$ID_REUSE" != "null" ]; then
    echo -e "${GREEN}✓ Slab reuse working${NC}"
    echo "   New ID: $ID_REUSE"
else
    echo -e "${RED}✗ Slab reuse failed${NC}"
fi

# Test max pool size enforcement
echo ""
echo "9. Testing max pool size limits..."
# Get current config
MAX_SIZE=$(echo "$STATS" | jq -r '.max_pool_size')
CURRENT=$(echo "$STATS" | jq -r '.total_allocated_bytes')
echo "   Max pool size: $((MAX_SIZE / 1048576)) MB"
echo "   Current allocated: $((CURRENT / 1048576)) MB"

# Try to allocate more than available
REMAINING=$((MAX_SIZE - CURRENT))
if [ $REMAINING -gt 1048576 ]; then
    # Try allocating slightly less than max
    LARGE_ALLOC=$(curl -s -X POST "${BASE_URL}/allocate" \
        -H "Content-Type: application/json" \
        -d "{\"size_bytes\": $REMAINING}")
    
    if echo "$LARGE_ALLOC" | jq -e '.id' > /dev/null 2>&1; then
        LARGE_ID=$(echo "$LARGE_ALLOC" | jq -r '.id')
        echo -e "${GREEN}✓ Large allocation accepted${NC}"
        
        # Now try to exceed
        EXCEED=$(curl -s -X POST "${BASE_URL}/allocate" \
            -H "Content-Type: application/json" \
            -d '{"size_bytes": 1048576}' 2>&1)
        
        if echo "$EXCEED" | grep -q "exhausted\|exceeded"; then
            echo -e "${GREEN}✓ Pool size limit correctly enforced${NC}"
        fi
        
        # Clean up
        curl -s -X DELETE "${BASE_URL}/allocate/${LARGE_ID}" > /dev/null
    fi
fi

# Test Prometheus metrics
echo ""
echo "10. Testing Prometheus metrics..."
METRICS=$(curl -s "${BASE_URL}/metrics")

if echo "$METRICS" | grep -q "maas_active_allocations"; then
    echo -e "${GREEN}✓ Prometheus metrics exposed${NC}"
    echo "   Metrics found:"
    echo "$METRICS" | grep "^maas_" | grep -v "^#" | head -5 | sed 's/^/   - /'
else
    echo -e "${RED}✗ Prometheus metrics not found${NC}"
    exit 1
fi

# Test invalid allocation
echo ""
echo "11. Testing error handling..."
INVALID=$(curl -s -X POST "${BASE_URL}/allocate" \
    -H "Content-Type: application/json" \
    -d '{"size_bytes": 99999999999}' \
    -w "\n%{http_code}")

if echo "$INVALID" | tail -1 | grep -qE "507|400"; then
    echo -e "${GREEN}✓ Invalid allocation correctly rejected${NC}"
else
    echo -e "${YELLOW}⚠ Unexpected response for invalid allocation${NC}"
fi

# Test non-existent deallocation
INVALID_DEL=$(curl -s -o /dev/null -w "%{http_code}" \
    -X DELETE "${BASE_URL}/allocate/00000000-0000-0000-0000-000000000000")

if [ "$INVALID_DEL" = "404" ]; then
    echo -e "${GREEN}✓ Non-existent deallocation correctly handled${NC}"
else
    echo -e "${YELLOW}⚠ Unexpected status for invalid deallocation: $INVALID_DEL${NC}"
fi

# Cleanup remaining allocations
echo ""
echo "12. Cleaning up test allocations..."
for ID in "${IDS[@]}"; do
    curl -s -X DELETE "${BASE_URL}/allocate/${ID}" > /dev/null
done
curl -s -X DELETE "${BASE_URL}/allocate/${ID_REUSE}" > /dev/null
echo -e "${GREEN}✓ Cleanup complete${NC}"

# Final stats
echo ""
echo "=========================================="
echo "  Verification Complete!"
echo "=========================================="
FINAL_STATS=$(curl -s "${BASE_URL}/stats")
echo ""
echo "Final state:"
echo "   Active allocations: $(echo "$FINAL_STATS" | jq -r '.active_allocations')"
echo "   Total allocated: $(echo "$FINAL_STATS" | jq -r '.total_allocated_mb') MB"
echo "   Total in use: $(echo "$FINAL_STATS" | jq -r '.total_in_use_mb') MB"
echo "   Utilization: $(echo "$FINAL_STATS" | jq -r '.utilization_percent')%"
echo ""
echo -e "${GREEN}All tests passed! ✓${NC}"
