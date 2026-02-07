# Memory-as-a-Service (MaaS) Backend v2.0

A **production-ready**, high-performance Rust-based memory server with slab allocation, connection pooling, and robust Prometheus integration.

## 🚀 Key Features

### Memory Management
- **Slab Allocator**: Efficient fixed-size block allocation with automatic reuse
- **Configurable Pool Sizes**: Multiple slab sizes (1KB to 4MB default)
- **Maximum Pool Size**: Hard limit to prevent unbounded memory growth
- **Memory Reuse**: Automatic slab recycling for optimal performance
- **Zero-Copy**: Memory blocks are zeroed on deallocation for security

### Backend Connection
- **Connection Manager**: Automatic connection state tracking
- **Auto-Reconnection**: Intelligent retry logic with exponential backoff
- **Health Monitoring**: Continuous backend health checks
- **Graceful Degradation**: Falls back to native metrics if connection breaks
- **Metrics Push**: Periodic metrics push to backend server

### Observability
- **Enhanced Prometheus Metrics**:
  - `maas_active_allocations` - Current allocations
  - `maas_allocation_size_bytes` - In-use memory
  - `maas_pool_size_bytes` - Total allocated pool
  - `maas_utilization_percent` - Pool utilization
  - `maas_request_count` - Request counter
  - `maas_slab_reuse_total` - Slab reuse counter

- **Detailed Health Endpoint**: Memory stats, connection status, version info
- **Stats Endpoint**: Per-pool statistics and allocation details

## 📋 Prerequisites

- Rust 1.70+ (stable)
- `cargo`

## ⚙️ Configuration

### Environment Variables (`.env`)
```bash
# Server
SERVER_HOST=127.0.0.1
SERVER_PORT=3000

# Memory Pool
SLAB_SIZES=1024,4096,16384,65536,262144,1048576,4194304
MAX_POOL_SIZE=1073741824  # 1GB

# Backend Connection (optional)
BACKEND_SERVER_URL=http://backend-server:8080
BACKEND_RETRY_INTERVAL=30

# Prometheus
PROMETHEUS_PUSH_ENABLED=true
PROMETHEUS_PUSHGATEWAY_URL=http://localhost:9091
```

### Configuration File (`config.toml`)
```toml
[server]
host = "127.0.0.1"
port = 3000

[memory]
slab_sizes = [1024, 4096, 16384, 65536, 262144, 1048576, 4194304]
max_pool_size = 1073741824
initial_slabs_per_size = 10

[backend]
server_url = ""
retry_interval = 30
timeout = 10

[prometheus]
push_enabled = false
pushgateway_url = "http://localhost:9091"
push_interval = 10
```

## 🏃 Quick Start

### 1. Build and Run
```bash
cd maas-backend
cargo build --release
cargo run --release
```

### 2. Test the API

**Health Check**
```bash
curl http://localhost:3000/health | jq
```

**Allocate Memory**
```bash
# Allocate 100KB (will use 128KB slab)
curl -X POST http://localhost:3000/allocate \
  -H "Content-Type: application/json" \
  -d '{"size_bytes": 102400}' | jq

# Response:
# {
#   "id": "550e8400-e29b-41d4-a716-446655440000",
#   "size_bytes": 102400,
#   "actual_size_bytes": 131072,
#   "size_mb": 0.125,
#   "age_seconds": 0
# }
```

**View Statistics**
```bash
curl http://localhost:3000/stats | jq
```

**Deallocate Memory**
```bash
curl -X DELETE http://localhost:3000/allocate/{allocation-id}
```

**Prometheus Metrics**
```bash
curl http://localhost:3000/metrics
```

## 🏗️ Architecture

### Slab Allocator Design
```
Request: 50KB
    ↓
Find smallest slab ≥ 50KB → 64KB slab
    ↓
Check free pool → Reuse if available
    ↓
Else: Allocate new (if under max pool size)
    ↓
Return allocation ID
```

### Connection Manager Flow
```
[Disconnected] → Test Connection
    ↓ Success
[Connected] → Push Metrics
    ↓ Failure
[Reconnecting] → Retry after interval
    ↓
[Native Metrics] ← Fallback mode
```

## 📊 Monitoring

### Prometheus Integration

Add to your `prometheus.yml`:
```yaml
scrape_configs:
  - job_name: 'maas-backend'
    scrape_interval: 5s
    static_configs:
      - targets: ['localhost:3000']
```

### Key Metrics to Monitor
- **Utilization**: Alert if > 90%
- **Active Allocations**: Track allocation patterns
- **Slab Reuse**: Monitor efficiency
- **Connection State**: Backend connectivity

## 🧪 Testing

Run included tests:
```bash
cargo test
```

Run verification script:
```bash
./verify.sh
```

## 🔒 Production Considerations

### Security
- Memory blocks zeroed on deallocation
- No buffer overflow (Rust safety)
- Input validation on all endpoints

### Performance
- Lock-free where possible
- Efficient slab reuse
- Pre-allocated pools reduce allocation overhead
- Connection pooling for backend

### Reliability
- Automatic reconnection on backend failure
- Graceful degradation to native metrics
- Health checks for monitoring
- Resource limits prevent OOM

### Scalability
- Configurable pool sizes
- Per-size slab pools
- Minimal memory fragmentation
- Horizontal scaling ready

## 📈 Performance Tuning

### Slab Sizes
Choose based on your workload:
- **Small frequent allocations**: Add more small slabs (1KB-16KB)
- **Large buffers**: Increase large slab sizes
- **Mixed workload**: Use default distribution

### Pool Size
- Set based on available RAM
- Leave headroom for other processes
- Monitor utilization in production

### Initial Slabs
- Pre-allocate for hot path performance
- Trade memory for allocation speed
- Adjust based on startup patterns

## 🛠️ Development

### Build
```bash
cargo build
```

### Run with debug logging
```bash
RUST_LOG=debug cargo run
```

### Format code
```bash
cargo fmt
```

### Lint
```bash
cargo clippy
```

## 📝 API Reference

### `GET /health`
Returns service health and status.

### `GET /metrics`
Returns Prometheus-formatted metrics.

### `GET /stats`
Returns detailed memory statistics.

### `POST /allocate`
Allocate memory block.

**Request:**
```json
{"size_bytes": 102400}
```

**Response:**
```json
{
  "id": "uuid",
  "size_bytes": 102400,
  "actual_size_bytes": 131072,
  "size_mb": 0.125,
  "age_seconds": 0
}
```

### `DELETE /allocate/:id`
Deallocate memory block by ID.

## 🤝 Contributing

Contributions welcome! Please ensure:
- Code is formatted (`cargo fmt`)
- Tests pass (`cargo test`)
- Clippy warnings addressed (`cargo clippy`)

## 📄 License

MIT License - see LICENSE file for details

## 🔗 Version History

- **v2.0.0** - Production-ready with slab allocator, connection manager
- **v0.1.0** - Initial prototype with basic allocation

---

**Built with ❤️ using Rust, Axum, and Tokio**
