use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use uuid::Uuid;
use std::time::SystemTime;
use crate::models::{AllocationInfo, MemoryStats};
use crate::slab::SlabAllocator;

#[derive(Debug)]
pub struct AllocationRecord {
    pub id: Uuid,
    pub size_bytes: usize,
    pub actual_size_bytes: usize,
    pub _slab_id: Uuid,
    pub created_at: SystemTime,
}

#[derive(Clone)]
pub struct AppState {
    pub allocator: Arc<SlabAllocator>,
    pub allocations: Arc<Mutex<HashMap<Uuid, AllocationRecord>>>,
}

impl AppState {
    pub fn new(allocator: Arc<SlabAllocator>) -> Self {
        Self {
            allocator,
            allocations: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    pub fn get_stats(&self) -> MemoryStats {
        let allocations = self.allocations.lock().unwrap();
        let now = SystemTime::now();

        let mut allocation_infos = Vec::new();
        for record in allocations.values() {
            let age = now.duration_since(record.created_at).unwrap_or_default().as_secs();
            
            allocation_infos.push(AllocationInfo {
                id: record.id,
                size_bytes: record.size_bytes,
                actual_size_bytes: record.actual_size_bytes,
                size_mb: record.actual_size_bytes as f64 / 1_048_576.0,
                age_seconds: age,
            });
        }

        let total_allocated = self.allocator.get_total_allocated();
        let total_in_use = self.allocator.get_total_in_use();

        MemoryStats {
            total_allocated_bytes: total_allocated,
            total_in_use_bytes: total_in_use,
            total_allocated_mb: total_allocated as f64 / 1_048_576.0,
            total_in_use_mb: total_in_use as f64 / 1_048_576.0,
            active_allocations: allocations.len(),
            max_pool_size: self.allocator.get_max_pool_size(),
            utilization_percent: self.allocator.get_utilization(),
            pool_stats: self.allocator.get_pool_stats(),
            allocations: allocation_infos,
        }
    }
}
