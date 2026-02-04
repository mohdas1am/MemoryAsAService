use axum::{
    extract::{Path, State},
    response::Json,
    http::StatusCode,
};
use uuid::Uuid;
use std::sync::{Arc, Mutex};
use std::time::SystemTime;
use crate::{
    models::{AllocateRequest, AllocationInfo, AppError, MemoryStats},
    state::{AppState, MemoryAllocation},
};
use prometheus::{Encoder, TextEncoder, register_counter, register_histogram, register_gauge};

// Metrics
lazy_static::lazy_static! {
    static ref REQUEST_COUNTER: prometheus::Counter = register_counter!("request_count", "Total number of requests").unwrap();
    static ref ALLOCATION_GAUGE: prometheus::Gauge = register_gauge!("active_allocations", "Number of active allocations").unwrap();
    static ref ALLOCATION_SIZE_GAUGE: prometheus::Gauge = register_gauge!("allocation_size_bytes", "Total size of allocated memory in bytes").unwrap();
}

// Since we didn't add lazy_static to Cargo.toml, we should add it or use std::sync::OnceLock (if rust 1.70+) or just initialize in main and pass via state?
// But macros like register_counter! rely on global state.
// Wait, I forgot to add `lazy_static` to Cargo.toml.
// I will add it using run_command or just edit Cargo.toml first. 
// Or I can just manually initialize them in main and use them. 
// But accessing them in handlers requires them to be global or passed in state.
// I'll stick to global for metrics as it's standard for Prometheus. 
// I will quickly add lazy_static to Cargo.toml before this.

pub async fn health_check() -> Json<serde_json::Value> {
    REQUEST_COUNTER.inc();
    Json(serde_json::json!({
        "status": "healthy",
        "service": "memory-as-a-service",
        "timestamp": SystemTime::now().duration_since(SystemTime::UNIX_EPOCH).unwrap().as_secs()
    }))
}

pub async fn metrics_handler() -> String {
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
    
    // Simulate allocation
    let data = vec![0u8; payload.size_bytes];
    let id = Uuid::new_v4();
    let now = SystemTime::now();
    
    let allocation = MemoryAllocation {
        id,
        size_bytes: payload.size_bytes,
        data: Arc::new(data),
        created_at: now,
    };

    let info = AllocationInfo {
        id,
        size_bytes: allocation.size_bytes,
        size_mb: allocation.size_bytes as f64 / 1_048_576.0,
        age_seconds: 0,
    };

    {
        let mut allocations = state.allocations.lock().unwrap();
        allocations.insert(id, allocation);
        ALLOCATION_GAUGE.set(allocations.len() as f64);
        ALLOCATION_SIZE_GAUGE.add(payload.size_bytes as f64);
    }
    
    Ok(Json(info))
}

pub async fn deallocate_handler(
    State(state): State<AppState>,
    Path(id): Path<Uuid>,
) -> Result<StatusCode, AppError> {
    REQUEST_COUNTER.inc();

    let mut allocations = state.allocations.lock().unwrap();
    if let Some(removed) = allocations.remove(&id) {
        ALLOCATION_GAUGE.set(allocations.len() as f64);
        ALLOCATION_SIZE_GAUGE.sub(removed.size_bytes as f64);
        Ok(StatusCode::OK)
    } else {
        Err(AppError(StatusCode::NOT_FOUND, "Allocation not found".to_string()))
    }
}
