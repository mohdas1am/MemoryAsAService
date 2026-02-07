#!/bin/bash
# Quick monitoring script for MaaS allocations

echo "Monitoring MaaS Memory Allocations"
echo "Press Ctrl+C to stop"
echo ""

MAAS_URL="http://localhost:3000"

while true; do
    clear
    echo "===================================="
    echo "  MaaS Memory Statistics"
    echo "  $(date '+%Y-%m-%d %H:%M:%S')"
    echo "===================================="
    echo ""
    
    # Get stats
    STATS=$(curl -s $MAAS_URL/stats 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        echo "📊 Overall Statistics:"
        echo "$STATS" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(f\"  Active Allocations:    {data.get('active_allocations', 0):>8}\"
)
    print(f\"  Total Allocations:     {data.get('total_allocations', 0):>8}\")
    print(f\"  Allocated Memory:      {data.get('total_allocated_bytes', 0):>8} bytes\")
    print(f\"  Allocated Memory (MB): {data.get('total_allocated_bytes', 0) / 1024 / 1024:>8.2f} MB\")
    print()
    print('📦 Pool Statistics:')
    print('  {:<10} {:>10} {:>10} {:>10} {:>10}'.format('Size', 'Total', 'Free', 'Used', 'Util%'))
    print('  ' + '-' * 60)
    for pool in data.get('pool_stats', []):
        size_kb = pool['slab_size'] / 1024
        if size_kb < 1024:
            size_str = f\"{size_kb:.0f}KB\"
        else:
            size_str = f\"{size_kb/1024:.0f}MB\"
        total = pool['total_slabs']
        free = pool['free_slabs']
        used = total - free
        util = pool['utilization_percent']
        print(f\"  {size_str:<10} {total:>10} {free:>10} {used:>10} {util:>9.1f}%\")
except:
    print('  Error parsing stats')
" 2>/dev/null || echo "  Error displaying stats"
        
        echo ""
        echo "🔗 Endpoints:"
        echo "  Health: $MAAS_URL/health"
        echo "  Stats:  $MAAS_URL/stats"
        echo "  Metrics: $MAAS_URL/metrics"
    else
        echo "❌ Cannot connect to MaaS at $MAAS_URL"
        echo ""
        echo "Is MaaS running?"
        echo "  Start with: cd maas-backend && cargo run --release"
    fi
    
    sleep 2
done
