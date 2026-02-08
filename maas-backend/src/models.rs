use serde::{Deserialize, Serialize};
use uuid::Uuid;
use axum::{
    response::{IntoResponse, Response},
    http::StatusCode,
};
use crate::slab::SlabPoolStats;

#[derive(Debug, Deserialize)]
pub struct AllocateRequest {
    pub size_bytes: usize,
}

#[derive(Debug, Serialize, Clone)]
pub struct AllocationInfo {
    pub id: Uuid,
    pub size_bytes: usize,
    pub actual_size_bytes: usize,
    pub size_mb: f64,
    pub age_seconds: u64,
}

#[derive(Debug, Serialize)]
pub struct MemoryStats {
    pub total_allocated_bytes: usize,
    pub total_in_use_bytes: usize,
    pub total_allocated_mb: f64,
    pub total_in_use_mb: f64,
    pub active_allocations: usize,
    pub max_pool_size: usize,
    pub utilization_percent: f64,
    pub pool_stats: Vec<SlabPoolStats>,
    pub allocations: Vec<AllocationInfo>,
}

#[derive(Debug, Serialize)]
pub struct HealthResponse {
    pub status: String,
    pub service: String,
    pub version: String,
    pub timestamp: u64,
    pub memory: MemoryHealth,
}

#[derive(Debug, Serialize)]
pub struct MemoryHealth {
    pub total_allocated_mb: f64,
    pub utilization_percent: f64,
    pub active_allocations: usize,
}

pub struct AppError(pub StatusCode, pub String);

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        (self.0, self.1).into_response()
    }
}
