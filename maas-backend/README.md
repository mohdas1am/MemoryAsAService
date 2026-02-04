# Memory-as-a-Service (MaaS) Backend

A high-performance, Rust-based backend that manages memory allocations and exposes metrics for Prometheus scraping.

## Features
- **Allocation API**: Allocate and deallocate memory blocks via HTTP.
- **Health Checks**: `/health` endpoint for liveness probes.
- **Prometheus Metrics**: Exposes custom metrics (e.g., `active_allocations`, `memory_usage_bytes`) at `/metrics`.
- **Concurrency**: Built with `tokio` for handling multiple concurrent requests.

## Prerequisites
- Rust (latest stable)
- `cargo`

## Quick Start

1. **Build and Run**
   ```bash
   cargo run
   ```
   The server listens on `localhost:3000`.

2. **API Endpoints**

   - **Check Health**
     ```bash
     curl http://localhost:3000/health
     ```

   - **Allocate Memory (JSON)**
     ```bash
     curl -X POST http://localhost:3000/allocate \
       -H "Content-Type: application/json" \
       -d '{"size_bytes": 1048576}'
     ```

   - **View Metrics**
     ```bash
     curl http://localhost:3000/metrics
     ```

## Integration
This service is designed to be scraped by a Prometheus instance. Ensure your `prometheus.yml` is configured to scrape `localhost:3000`.
