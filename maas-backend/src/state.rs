use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use uuid::Uuid;
use std::time::SystemTime;
use crate::models::{AllocationInfo, MemoryStats};

#[derive(Debug)]
pub struct MemoryAllocation {
    pub id: Uuid,
    pub size_bytes: usize,
    pub data: Arc<Vec<u8>>,
    pub created_at: SystemTime,
}

#[derive(Clone)]
pub struct AppState {
    pub allocations: Arc<Mutex<HashMap<Uuid, MemoryAllocation>>>,
}

impl AppState {
    pub fn new() -> Self {
        Self {
            allocations: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    pub fn get_stats(&self) -> MemoryStats {
        let allocations = self.allocations.lock().unwrap();
        let mut total_bytes = 0;
        let mut allocation_infos = Vec::new();
        let now = SystemTime::now();

        for alloc in allocations.values() {
            total_bytes += alloc.size_bytes;
            let age = now.duration_since(alloc.created_at).unwrap_or_default().as_secs();
            
            allocation_infos.push(AllocationInfo {
                id: alloc.id,
                size_bytes: alloc.size_bytes,
                size_mb: alloc.size_bytes as f64 / 1_048_576.0,
                age_seconds: age,
            });
        }

        MemoryStats {
            total_allocated_bytes: total_bytes,
            total_allocated_mb: total_bytes as f64 / 1_048_576.0,
            active_allocations: allocations.len(),
            allocations: allocation_infos,
        }
    }
}
