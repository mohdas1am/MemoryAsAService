#!/bin/bash

# Configuration
API_URL="http://localhost:3000"

echo "==========================================="
echo "   Memory-as-a-Service Client Simulator"
echo "==========================================="
echo ""

while true; do
    echo "=== MaaS Client Simulator ==="
    echo "1. Allocate Memory"
    echo "2. Deallocate Memory"
    echo "3. Check Service Health"
    echo "4. View All Allocations"
    echo "5. Exit"
    read -p "Choose an option (1-5): " selection

    case $selection in
        1)
            read -p "Enter size in MB (e.g., 1, 100, 300): " mb
            
            # Convert MB to bytes
            bytes=$((mb * 1024 * 1024))
            
            echo "Requesting allocation of ${mb} MB (${bytes} bytes)..."
            
            response=$(curl -s -X POST "$API_URL/allocate" \
                -H "Content-Type: application/json" \
                -d "{\"size_bytes\": $bytes}")
            
            # Extract UUID and size from response
            uuid=$(echo "$response" | grep -o '"id":"[^"]*"' | cut -d'"' -f4)
            
            if [ -n "$uuid" ]; then
                echo ""
                echo "✅ Memory allocated successfully!"
                echo "UUID: $uuid"
                echo "Size: ${mb} MB (${bytes} bytes)"
                echo ""
                echo "→ CHECK PROMETHEUS GRAPH! 'active_allocations' should increase."
            else
                echo "❌ Allocation failed!"
                echo "Response: $response"
            fi
            echo ""
            ;;
        2)
            read -p "Enter allocation UUID to deallocate: " uuid
            echo "Requesting deallocation for $uuid..."
            
            status_code=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE "$API_URL/allocate/$uuid")
            
            echo ""
            if [ "$status_code" -eq 200 ]; then
                echo "✅ Memory deallocated successfully!"
                echo "UUID: $uuid has been freed."
                echo ""
                echo "→ CHECK PROMETHEUS GRAPH! 'active_allocations' should decrease."
            else
                echo "❌ Deallocation failed (HTTP $status_code)"
                echo "Check if UUID exists. Use option 4 to view all allocations."
            fi
            echo ""
            ;;
        3)
            echo "Checking MaaS Service Health..."
            health=$(curl -s "$API_URL/health")
            
            if echo "$health" | grep -q "healthy"; then
                echo "✅ Service is healthy"
            else
                echo "❌ Service is not responding"
            fi
            echo ""
            ;;
        4)
            echo "Fetching all allocations..."
            stats=$(curl -s "$API_URL/stats")
            
            # Pretty print if jq is available
            if command -v jq &> /dev/null; then
                echo "$stats" | jq .
            else
                echo "$stats"
            fi
            echo ""
            ;;
        5)
            echo "Exiting MaaS Client Simulator..."
            exit 0
            ;;
        *)
            echo "❌ Invalid selection. Please choose 1-5."
            echo ""
            ;;
    esac
done
