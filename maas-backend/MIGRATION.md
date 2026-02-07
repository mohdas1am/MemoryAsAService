# Migration Guide: v1 → v2

## Overview
Version 2.0 introduces production-ready features including slab allocation, connection management, and enhanced observability.

## Breaking Changes

### 1. Configuration
**Old (v1)**: Hardcoded configuration
**New (v2)**: `config.toml` and `.env` files

**Action**: Create `config.toml` or set environment variables. See `.env.example`.

### 2. Memory Allocation
**Old**: Direct `Vec` allocation
**New**: Slab-based allocation

**Impact**: 
- Allocations rounded up to nearest slab size
- API response includes both `size_bytes` (requested) and `actual_size_bytes` (slab size)

**Example**:
```json
// v1 Response
{
  "id": "...",
  "size_bytes": 50000,
  "size_mb": 0.048
}

// v2 Response
{
  "id": "...",
  "size_bytes": 50000,
  "actual_size_bytes": 65536,
  "size_mb": 0.0625
}
```

### 3. Metrics Names
**Changed metrics** (prefixed with `maas_`):
- `request_count` → `maas_request_count`
- `active_allocations` → `maas_active_allocations`
- `allocation_size_bytes` → `maas_allocation_size_bytes`

**New metrics**:
- `maas_pool_size_bytes` - Total allocated pool
- `maas_utilization_percent` - Pool utilization
- `maas_slab_reuse_total` - Slab reuse counter

**Action**: Update Prometheus queries and dashboards.

### 4. Health Endpoint
**Enhanced response** includes memory and connection status.

**Old**:
```json
{
  "status": "healthy",
  "service": "memory-as-a-service",
  "timestamp": 1234567890
}
```

**New**:
```json
{
  "status": "healthy",
  "service": "memory-as-a-service",
  "version": "0.2.0",
  "timestamp": 1234567890,
  "memory": {
    "total_allocated_mb": 12.5,
    "utilization_percent": 1.2,
    "active_allocations": 5
  },
  "backend_connection": {
    "state": "Connected",
    "last_success": 1234567890,
    "consecutive_failures": 0
  }
}
```

### 5. Stats Endpoint
**Enhanced** with pool statistics and utilization.

**New fields**:
- `total_in_use_bytes` - Actual memory in use
- `max_pool_size` - Maximum pool capacity
- `utilization_percent` - Usage percentage
- `pool_stats` - Per-pool statistics array

## New Features

### 1. Slab Allocator
Efficient memory management with configurable pool sizes.

**Configuration**:
```toml
[memory]
slab_sizes = [1024, 4096, 16384, 65536, 262144, 1048576, 4194304]
max_pool_size = 1073741824
initial_slabs_per_size = 10
```

**Benefits**:
- Memory reuse (no allocation on hot path)
- Predictable performance
- Bounded memory usage

### 2. Backend Connection Manager
Automatic connection management with reconnection.

**Configuration**:
```toml
[backend]
server_url = "http://backend:8080"
retry_interval = 30
timeout = 10
```

**Features**:
- Auto-reconnection on failure
- Health monitoring
- Graceful degradation

### 3. Metrics Push
Push metrics to backend server or Prometheus pushgateway.

**Configuration**:
```toml
[prometheus]
push_enabled = true
pushgateway_url = "http://localhost:9091"
push_interval = 10
```

## Migration Steps

### Step 1: Update Dependencies
```bash
cd maas-backend
cargo update
```

### Step 2: Create Configuration
```bash
# Copy example config
cp .env.example .env

# Edit configuration
nano .env
```

### Step 3: Update Prometheus Config
```yaml
# prometheus.yml
scrape_configs:
  - job_name: 'maas-backend'
    scrape_interval: 5s
    static_configs:
      - targets: ['localhost:3000']
```

### Step 4: Update Grafana Dashboards
Replace metric names:
```
request_count → maas_request_count
active_allocations → maas_active_allocations
allocation_size_bytes → maas_allocation_size_bytes
```

Add new metrics:
```
maas_pool_size_bytes
maas_utilization_percent
```

### Step 5: Test
```bash
# Build
cargo build --release

# Run
cargo run --release

# Verify
./verify_v2.sh
```

## Compatibility

### API Compatibility
✅ All v1 API endpoints work in v2
✅ Response format backward compatible (added fields only)
⚠️  Metric names changed (requires Prometheus config update)

### Data Compatibility
✅ No persistent data - no migration needed
✅ Stateless service - can run side-by-side

## Rollback Plan

If issues occur, rollback is simple:

1. Stop v2 server
2. Revert to v1 binary
3. Restore old Prometheus config
4. Restart v1 server

No data loss occurs as service is stateless.

## Performance Impact

### Improvements
- ✅ Faster allocations (slab reuse)
- ✅ More predictable latency
- ✅ Better memory efficiency
- ✅ Lower GC pressure

### Considerations
- Memory rounded to slab sizes (may use slightly more)
- Initial startup allocates pool (configurable)
- Connection monitoring adds background task

## Monitoring

### Key Metrics to Watch Post-Migration

1. **Utilization**: Should stay under 80%
2. **Slab Reuse**: Should increase over time
3. **Pool Size**: Should stabilize after warmup
4. **Response Time**: Should improve or stay same

### Alerts to Update

```yaml
# Old alert
- alert: HighMemoryUsage
  expr: allocation_size_bytes > 1e9

# New alert
- alert: HighMemoryUsage
  expr: maas_allocation_size_bytes > 1e9
  
# New alert for utilization
- alert: PoolNearCapacity
  expr: maas_utilization_percent > 90
```

## Support

For issues or questions:
1. Check logs: `tail -f maas.log`
2. Verify config: `cat config.toml`
3. Run diagnostics: `./verify_v2.sh`
4. Review README_v2.md

## Timeline Recommendation

- **Week 1**: Test in dev environment
- **Week 2**: Deploy to staging, update monitoring
- **Week 3**: Gradual production rollout
- **Week 4**: Monitor and optimize

---

**Questions?** Open an issue or check the README_v2.md for details.
