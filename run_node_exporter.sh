#!/bin/bash
# Run node_exporter to generate real host metrics for Prometheus to scrape
# This creates hundreds of real time series (CPU, memory, disk, network)
# which exercises MaaS chunk allocation.
#
# Usage: ./run_node_exporter.sh
#
# Prometheus is already configured to scrape localhost:9100

set -e

# ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Kill existing
# pkill -f node_exporter 2>/dev/null || true
# sleep 1

# echo "=== Starting node_exporter ==="
# echo "  Listening on: http://localhost:9100/metrics"
# echo "  Prometheus will scrape this automatically (job: high-cardinality-stress-test)"
# echo ""

exec /workspaces/MemoryAsAService/node_exporter --web.listen-address=":9100"
