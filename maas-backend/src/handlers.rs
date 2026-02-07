use axum::{
    extract::{Path, State},
    response::Json,
    http::StatusCode,
};
use uuid::Uuid;
use std::time::SystemTime;
use crate::{
    models::{AllocateRequest, AllocationInfo, AppError, MemoryStats, HealthResponse, MemoryHealth},
    state::{AppState, AllocationRecord},
};
use prometheus::{Encoder, TextEncoder, register_counter, register_gauge};

// Metrics
lazy_static::lazy_static! {
    static ref REQUEST_COUNTER: prometheus::Counter = 
        register_counter!("maas_request_count", "Total number of requests").unwrap();
    static ref ALLOCATION_GAUGE: prometheus::Gauge = 
        register_gauge!("maas_active_allocations", "Number of active allocations").unwrap();
    static ref ALLOCATION_SIZE_GAUGE: prometheus::Gauge = 
        register_gauge!("maas_allocation_size_bytes", "Total size of in-use memory in bytes").unwrap();
    static ref POOL_SIZE_GAUGE: prometheus::Gauge = 
        register_gauge!("maas_pool_size_bytes", "Total allocated pool size in bytes").unwrap();
    static ref UTILIZATION_GAUGE: prometheus::Gauge = 
        register_gauge!("maas_utilization_percent", "Memory pool utilization percentage").unwrap();
    static ref SLAB_REUSE_COUNTER: prometheus::Counter = 
        register_counter!("maas_slab_reuse_total", "Total number of slab reuses").unwrap();
}

pub async fn health_check(State(state): State<AppState>) -> Json<HealthResponse> {
    REQUEST_COUNTER.inc();
    
    let stats = state.get_stats();
    
    Json(HealthResponse {
        status: "healthy".to_string(),
        service: "memory-as-a-service".to_string(),
        version: env!("CARGO_PKG_VERSION").to_string(),
        timestamp: SystemTime::now()
            .duration_since(SystemTime::UNIX_EPOCH)
            .unwrap()
            .as_secs(),
        memory: MemoryHealth {
            total_allocated_mb: stats.total_allocated_mb,
            utilization_percent: stats.utilization_percent,
            active_allocations: stats.active_allocations,
        },
    })
}

pub async fn metrics_handler(State(state): State<AppState>) -> String {
    // Update gauges with current values
    let stats = state.get_stats();
    ALLOCATION_GAUGE.set(stats.active_allocations as f64);
    ALLOCATION_SIZE_GAUGE.set(stats.total_in_use_bytes as f64);
    POOL_SIZE_GAUGE.set(stats.total_allocated_bytes as f64);
    UTILIZATION_GAUGE.set(stats.utilization_percent);
    
    let encoder = TextEncoder::new();
    let metric_families = prometheus::gather();
    let mut buffer = vec![];
    encoder.encode(&metric_families, &mut buffer).unwrap();
    String::from_utf8(buffer).unwrap()
}

pub async fn stats_handler(
    State(state): State<AppState>,
) -> Json<MemoryStats> {
    Json(state.get_stats())
}

pub async fn allocate_handler(
    State(state): State<AppState>,
    Json(payload): Json<AllocateRequest>,
) -> Result<Json<AllocationInfo>, AppError> {
    REQUEST_COUNTER.inc();
    
    // Allocate from slab allocator
    let (allocation_id, actual_size, slab_id) = state.allocator
        .allocate(payload.size_bytes)
        .map_err(|e| AppError(StatusCode::INSUFFICIENT_STORAGE, e))?;

    let now = SystemTime::now();
    
    let record = AllocationRecord {
        id: allocation_id,
        size_bytes: payload.size_bytes,
        actual_size_bytes: actual_size,
        slab_id,
        created_at: now,
    };

    let info = AllocationInfo {
        id: allocation_id,
        size_bytes: payload.size_bytes,
        actual_size_bytes: actual_size,
        size_mb: actual_size as f64 / 1_048_576.0,
        age_seconds: 0,
    };

    {
        let mut allocations = state.allocations.lock().unwrap();
        allocations.insert(allocation_id, record);
        
        // Update metrics
        ALLOCATION_GAUGE.set(allocations.len() as f64);
        ALLOCATION_SIZE_GAUGE.set(state.allocator.get_total_in_use() as f64);
        POOL_SIZE_GAUGE.set(state.allocator.get_total_allocated() as f64);
        UTILIZATION_GAUGE.set(state.allocator.get_utilization());
    }
    
    Ok(Json(info))
}

pub async fn deallocate_handler(
    State(state): State<AppState>,
    Path(id): Path<Uuid>,
) -> Result<StatusCode, AppError> {
    REQUEST_COUNTER.inc();

    // Remove from tracking
    let record = {
        let mut allocations = state.allocations.lock().unwrap();
        allocations.remove(&id)
            .ok_or_else(|| AppError(StatusCode::NOT_FOUND, "Allocation not found".to_string()))?
    };

    // Deallocate from slab allocator
    state.allocator
        .deallocate(id)
        .map_err(|e| AppError(StatusCode::INTERNAL_SERVER_ERROR, e))?;

    // Update metrics
    {
        let allocations = state.allocations.lock().unwrap();
        ALLOCATION_GAUGE.set(allocations.len() as f64);
        ALLOCATION_SIZE_GAUGE.set(state.allocator.get_total_in_use() as f64);
        POOL_SIZE_GAUGE.set(state.allocator.get_total_allocated() as f64);
        UTILIZATION_GAUGE.set(state.allocator.get_utilization());
    }

    Ok(StatusCode::OK)
}
