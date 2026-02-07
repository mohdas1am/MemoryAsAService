# Prometheus + MaaS Integration Testing Guide

This guide provides complete commands to build, run, and test the Prometheus + MaaS integration.

## Prerequisites

- Rust toolchain (cargo)
- Go 1.25+
- curl, lsof (for monitoring)

## Step 1: Build MaaS Backend

```bash
cd /home/abhi/Programs/MemoryAsAService/maas-backend
cargo build --release
```

The binary will be at: `target/release/maas-backend`

## Step 2: Build Prometheus with MaaS Integration

```bash
cd /home/abhi/Programs/MemoryAsAService/prometheus
make build
```

The binary will be at: `./prometheus`

## Step 3: Start MaaS Backend Server

```bash
cd /home/abhi/Programs/MemoryAsAService/maas-backend
cargo run --release
```

Or use the binary directly:
```bash
cd /home/abhi/Programs/MemoryAsAService/maas-backend
./target/release/maas-backend
```

**Default settings:**
- Port: 3000
- Max pool size: 1GB
- Slab sizes: 1KB, 2KB, 4KB, 8KB, 512KB, 1MB, 4MB

The server will start and show:
```
Listening on http://0.0.0.0:3000
```

## Step 4: Verify MaaS is Running

Open a new terminal and check:

```bash
# Health check
curl http://localhost:3000/health

# View statistics
curl http://localhost:3000/stats | python3 -m json.tool

# View Prometheus metrics
curl http://localhost:3000/metrics
```

Expected output for stats:
```json
{
  "total_allocations": 0,
  "active_allocations": 0,
  "total_allocated_bytes": 0,
  "pool_stats": [
    {"slab_size": 1024, "total_slabs": 0, "free_slabs": 0, ...},
    ...
  ]
}
```

## Step 5: Create Prometheus Configuration

Create a config file at `/tmp/prometheus-maas-test.yml`:

```bash
cat > /tmp/prometheus-maas-test.yml << 'EOF'
global:
  scrape_interval: 5s
  evaluation_interval: 5s

scrape_configs:
  # Scrape Prometheus itself
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
  
  # Scrape MaaS backend metrics
  - job_name: 'maas'
    static_configs:
      - targets: ['localhost:3000']
    metrics_path: '/metrics'
EOF
```

## Step 6: Start Prometheus with MaaS Integration

```bash
cd /home/abhi/Programs/MemoryAsAService/prometheus

./prometheus \
  --config.file=/tmp/prometheus-maas-test.yml \
  --storage.tsdb.path=/tmp/prometheus-maas-data \
  --storage.tsdb.maas.url=http://localhost:3000 \
  --storage.tsdb.maas.fallback=true \
  --web.listen-address=:9090
```

**Key flags:**
- `--storage.tsdb.maas.url`: URL to MaaS backend (required for integration)
- `--storage.tsdb.maas.fallback`: Enable local memory fallback (default: true)
- `--storage.tsdb.path`: Local storage directory
- `--config.file`: Prometheus configuration

## Step 7: Verify Prometheus is Using MaaS

Open a new terminal and monitor MaaS allocations:

```bash
# Watch MaaS stats in real-time
watch -n 2 'curl -s http://localhost:3000/stats | python3 -m json.tool'
```

You should see `active_allocations` and `total_allocated_bytes` increase as Prometheus stores metrics.

## Step 8: Generate Test Load

To generate more metrics and trigger MaaS allocations:

### Option A: Use Prometheus's own metrics
Just let it run - Prometheus scrapes itself and MaaS every 5 seconds.

### Option B: Generate synthetic load with node_exporter

```bash
# Install node_exporter (if available)
wget https://github.com/prometheus/node_exporter/releases/download/v1.7.0/node_exporter-1.7.0.linux-amd64.tar.gz
tar xvfz node_exporter-1.7.0.linux-amd64.tar.gz
cd node_exporter-1.7.0.linux-amd64
./node_exporter --web.listen-address=:9100
```

Then add to prometheus config:
```yaml
  - job_name: 'node'
    static_configs:
      - targets: ['localhost:9100']
```

And reload Prometheus:
```bash
kill -HUP $(pgrep prometheus)
```

### Option C: Use curl to push metrics (simple test)

```bash
# Generate continuous queries
for i in {1..100}; do
  curl -s "http://localhost:9090/api/v1/query?query=up" > /dev/null
  echo "Query $i sent"
  sleep 0.1
done
```

## Step 9: Monitor MaaS Usage

### View MaaS Statistics:
```bash
curl -s http://localhost:3000/stats | python3 -m json.tool
```

Key metrics to watch:
- `active_allocations`: Number of active memory allocations from Prometheus
- `total_allocated_bytes`: Total bytes allocated to Prometheus
- `pool_stats`: Per-slab-size utilization

### View MaaS Prometheus Metrics:
```bash
curl http://localhost:3000/metrics | grep maas_
```

Key metrics:
- `maas_active_allocations`: Current allocations
- `maas_allocation_size_bytes`: Size per allocation
- `maas_pool_size_bytes`: Pool usage per slab size
- `maas_utilization_percent`: Pool utilization

### View in Prometheus UI:
Open browser: http://localhost:9090

Query examples:
```
# MaaS allocations over time
maas_active_allocations

# MaaS memory usage
maas_pool_size_bytes

# Allocation rate
rate(maas_active_allocations[1m])

# Pool utilization
maas_utilization_percent
```

## Step 10: Verify Integration is Working

### Check Prometheus logs:
```bash
# Look for MaaS-related log entries
grep -i maas /tmp/prometheus.log

# Or if running in foreground, watch for:
# "MaaS memory pool manager initialized"
# "Allocated from MaaS"
# "MaaS health check succeeded"
```

### Check MaaS logs:
```bash
# If running with cargo run, check the terminal output
# Look for:
# POST /allocate requests
# DELETE /allocate/:id requests
```

### Verify allocations are happening:
```bash
# Before and after - should see increase
curl -s http://localhost:3000/stats | jq '.active_allocations, .total_allocated_bytes'

# Wait 30 seconds...

curl -s http://localhost:3000/stats | jq '.active_allocations, .total_allocated_bytes'
```

## Troubleshooting

### Prometheus not using MaaS:
1. Check Prometheus started with `--storage.tsdb.maas.url` flag
2. Verify MaaS is accessible: `curl http://localhost:3000/health`
3. Check Prometheus logs for connection errors

### MaaS shows 0 allocations:
1. Wait longer - allocations happen as chunks are created
2. Generate more load (see Step 8)
3. Check if fallback to local memory occurred (check logs)

### Connection refused:
1. Ensure MaaS is running: `lsof -i :3000`
2. Check firewall/network settings
3. Verify URL in Prometheus flags matches MaaS address

## Stopping Services

```bash
# Stop Prometheus
pkill prometheus

# Stop MaaS
pkill maas-backend
# or if running with cargo run
# Ctrl+C in the terminal

# Clean up test data
rm -rf /tmp/prometheus-maas-data
```

## Testing on Another Instance

To run on a different machine:

1. **Build on target machine:**
   ```bash
   # Build MaaS
   cd maas-backend && cargo build --release
   
   # Build Prometheus
   cd ../prometheus && make build
   ```

2. **Or copy binaries:**
   ```bash
   # Copy from build machine
   scp maas-backend/target/release/maas-backend target-machine:/path/to/maas-backend
   scp prometheus/prometheus target-machine:/path/to/prometheus
   ```

3. **Run with same commands** (adjust paths as needed)

4. **For remote MaaS:** Use full URL in Prometheus flag:
   ```bash
   --storage.tsdb.maas.url=http://remote-host:3000
   ```

## Expected Behavior

**When working correctly:**
- MaaS `active_allocations` increases over time
- MaaS `total_allocated_bytes` grows as metrics accumulate
- Prometheus logs show "Allocated from MaaS" messages
- Pool utilization increases in MaaS stats
- No errors in either Prometheus or MaaS logs

**Integration features:**
- ✅ Prometheus uses MaaS for chunk storage
- ✅ Automatic health monitoring (every 30s)
- ✅ Fallback to local memory if MaaS fails
- ✅ Efficient slab allocation (1KB to 4MB chunks)
- ✅ Pool size enforcement (1GB max)
- ✅ Metrics exported for monitoring

## Performance Notes

- First allocations happen within 1-2 minutes of starting
- Each scrape creates new time series chunks
- More targets = more allocations
- Default scrape interval: 5 seconds
- Check pool utilization to ensure not hitting limits
