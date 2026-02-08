# MaaS + Prometheus — Build & Deploy Guide

## Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| Go | 1.23+ | `wget https://go.dev/dl/go1.23.6.linux-amd64.tar.gz && sudo tar -C /usr/local -xzf go1.23.6.linux-amd64.tar.gz` |
| Rust | stable | `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \| sh` |
| Git | any | `sudo apt install -y git` |
| Make | any | `sudo apt install -y build-essential` |
| curl | any | `sudo apt install -y curl` |

After installing, add to `~/.bashrc`:
```bash
export PATH="/usr/local/go/bin:$HOME/.cargo/bin:$PATH"
```

## Clone & Build

```bash
git clone <your-repo-url> MemoryAsAService
cd MemoryAsAService
git checkout v2-update
```

### Build MaaS Backend (Rust)

```bash
cd maas-backend
cargo build --release
cd ..
```

Binary: `maas-backend/target/release/maas-backend`

### Build Prometheus (Go)

```bash
cd prometheus
PREBUILT_ASSETS_STATIC_DIR="$(pwd)/web/ui/static" make build
cd ..
```

Binaries: `prometheus/prometheus`, `prometheus/promtool`

### Get node_exporter

```bash
curl -sL https://github.com/prometheus/node_exporter/releases/download/v1.8.2/node_exporter-1.8.2.linux-amd64.tar.gz | tar xz
cp node_exporter-1.8.2.linux-amd64/node_exporter ./node_exporter
chmod +x ./node_exporter
```

---

## Single Server Setup

3 terminals, all from the project root:

```bash
# Terminal 1
./run_maas.sh

# Terminal 2
./run_node_exporter.sh

# Terminal 3
./run_prometheus.sh with-maas --clean
```

Open `http://localhost:9090` and query `prometheus_tsdb_maas_enabled`.

---

## Two-Server Setup

### Server A — MaaS backend

```bash
# Build
cd maas-backend && cargo build --release && cd ..

# Run (already binds to 0.0.0.0:3000)
./run_maas.sh
```

Verify: `curl http://<SERVER_A_IP>:3000/health`

### Server B — Prometheus + node_exporter

```bash
# Build
cd prometheus
PREBUILT_ASSETS_STATIC_DIR="$(pwd)/web/ui/static" make build
cd ..
```

Edit `prometheus.yml` — change the MaaS target:

```yaml
- job_name: 'maas-backend'
  static_configs:
    - targets: ['<SERVER_A_IP>:3000']    # <-- change this
```

Run:

```bash
# Terminal 1
./run_node_exporter.sh

# Terminal 2
./run_prometheus.sh with-maas --maas-url http://<SERVER_A_IP>:3000 --clean
```

---

## Testing: With vs Without MaaS

### With MaaS

```bash
./run_prometheus.sh with-maas --clean
```

Go to `http://localhost:9090`, query:

| Query | Expected |
|-------|----------|
| `prometheus_tsdb_maas_enabled` | 1 |
| `prometheus_tsdb_memory_total_available_bytes` | ~1.1 GB |
| `prometheus_tsdb_memory_maas_capacity_bytes` | 1073741824 |
| `prometheus_tsdb_maas_chunks_allocated_total` | growing |

### Without MaaS

```bash
# Ctrl+C Prometheus, then:
./run_prometheus.sh no-maas --clean
```

Same queries now return **empty result** -- metrics don't exist without MaaS.

---

## Ports Summary

| Service | Port | Firewall needed for remote? |
|---------|------|-----------------------------|
| MaaS backend | 3000 | Yes (Server A) |
| Prometheus UI | 9090 | Yes (Server B) |
| node_exporter | 9100 | No (local scrape only) |
