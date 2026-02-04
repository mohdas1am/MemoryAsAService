use serde::{Deserialize, Serialize};
use uuid::Uuid;
use axum::{
    response::{IntoResponse, Response},
    Json,
    http::StatusCode,
};
use std::time::SystemTime;

#[derive(Debug, Deserialize)]
pub struct AllocateRequest {
    pub size_bytes: usize,
}

#[derive(Debug, Serialize, Clone)]
pub struct AllocationInfo {
    pub id: Uuid,
    pub size_bytes: usize,
    pub size_mb: f64,
    pub age_seconds: u64,
}

#[derive(Debug, Serialize)]
pub struct MemoryStats {
    pub total_allocated_bytes: usize,
    pub total_allocated_mb: f64,
    pub active_allocations: usize,
    pub allocations: Vec<AllocationInfo>,
}

pub struct AppError(pub StatusCode, pub String);

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        (self.0, self.1).into_response()
    }
}
