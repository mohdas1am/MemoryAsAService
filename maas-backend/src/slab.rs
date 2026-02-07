use std::collections::{HashMap, VecDeque};
use std::sync::{Arc, Mutex};
use uuid::Uuid;
use std::time::SystemTime;
use tracing::{info, warn, error};
use serde::Serialize;

/// A memory slab - a fixed-size block of memory
#[derive(Debug)]
pub struct Slab {
    pub id: Uuid,
    pub size: usize,
    pub data: Vec<u8>,
    pub created_at: SystemTime,
    pub in_use: bool,
}

impl Slab {
    fn new(size: usize) -> Self {
        Self {
            id: Uuid::new_v4(),
            size,
            data: vec![0u8; size],
            created_at: SystemTime::now(),
            in_use: false,
        }
    }
}

/// Manages a pool of slabs for a specific size
#[derive(Debug)]
struct SlabPool {
    size: usize,
    free_slabs: VecDeque<Uuid>,
    all_slabs: HashMap<Uuid, Slab>,
    total_allocated: usize,
}

impl SlabPool {
    fn new(size: usize, initial_count: usize) -> Self {
        let mut pool = Self {
            size,
            free_slabs: VecDeque::new(),
            all_slabs: HashMap::new(),
            total_allocated: 0,
        };

        // Pre-allocate initial slabs
        for _ in 0..initial_count {
            let slab = Slab::new(size);
            let id = slab.id;
            pool.free_slabs.push_back(id);
            pool.all_slabs.insert(id, slab);
            pool.total_allocated += size;
        }

        pool
    }

    fn allocate(&mut self, max_pool_size: usize, current_total: usize) -> Option<Uuid> {
        // Try to reuse a free slab first
        if let Some(id) = self.free_slabs.pop_front() {
            if let Some(slab) = self.all_slabs.get_mut(&id) {
                slab.in_use = true;
                return Some(id);
            }
        }

        // Check if we can allocate a new slab
        if current_total + self.size <= max_pool_size {
            let slab = Slab::new(self.size);
            let id = slab.id;
            self.all_slabs.insert(id, slab);
            self.total_allocated += self.size;
            
            if let Some(slab) = self.all_slabs.get_mut(&id) {
                slab.in_use = true;
            }
            
            Some(id)
        } else {
            None
        }
    }

    fn deallocate(&mut self, id: Uuid) -> bool {
        if let Some(slab) = self.all_slabs.get_mut(&id) {
            if slab.in_use {
                slab.in_use = false;
                // Zero out the memory for security
                slab.data.fill(0);
                self.free_slabs.push_back(id);
                return true;
            }
        }
        false
    }

    fn get_stats(&self) -> SlabPoolStats {
        let in_use = self.all_slabs.values().filter(|s| s.in_use).count();
        SlabPoolStats {
            size: self.size,
            total_slabs: self.all_slabs.len(),
            in_use_slabs: in_use,
            free_slabs: self.free_slabs.len(),
            total_allocated_bytes: self.total_allocated,
            in_use_bytes: in_use * self.size,
        }
    }
}

#[derive(Debug, Clone, Serialize)]
pub struct SlabPoolStats {
    pub size: usize,
    pub total_slabs: usize,
    pub in_use_slabs: usize,
    pub free_slabs: usize,
    pub total_allocated_bytes: usize,
    pub in_use_bytes: usize,
}

/// Main slab allocator managing multiple slab pools
pub struct SlabAllocator {
    pools: Arc<Mutex<HashMap<usize, SlabPool>>>,
    max_pool_size: usize,
    slab_sizes: Vec<usize>,
    allocations: Arc<Mutex<HashMap<Uuid, (usize, Uuid)>>>, // allocation_id -> (pool_size, slab_id)
}

impl SlabAllocator {
    pub fn new(slab_sizes: Vec<usize>, max_pool_size: usize, initial_per_size: usize) -> Self {
        let mut pools = HashMap::new();
        
        for &size in &slab_sizes {
            pools.insert(size, SlabPool::new(size, initial_per_size));
        }

        info!("Initialized slab allocator with {} pools, max size: {} bytes", 
              slab_sizes.len(), max_pool_size);

        Self {
            pools: Arc::new(Mutex::new(pools)),
            max_pool_size,
            slab_sizes,
            allocations: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    /// Allocate memory of the requested size
    /// Returns (allocation_id, actual_size, slab_id)
    pub fn allocate(&self, requested_size: usize) -> Result<(Uuid, usize, Uuid), String> {
        // Find the smallest slab size that fits
        let slab_size = self.slab_sizes
            .iter()
            .find(|&&size| size >= requested_size)
            .ok_or_else(|| format!("Requested size {} exceeds largest slab size", requested_size))?;

        let mut pools = self.pools.lock().unwrap();
        let current_total = self.get_total_allocated_internal(&pools);

        let pool = pools.get_mut(slab_size)
            .ok_or_else(|| "Pool not found".to_string())?;

        let slab_id = pool.allocate(self.max_pool_size, current_total)
            .ok_or_else(|| format!("Pool exhausted: max size {} reached", self.max_pool_size))?;

        let allocation_id = Uuid::new_v4();
        
        // Track the allocation
        let mut allocations = self.allocations.lock().unwrap();
        allocations.insert(allocation_id, (*slab_size, slab_id));

        info!("Allocated {} bytes (requested: {}) with id {}", slab_size, requested_size, allocation_id);

        Ok((allocation_id, *slab_size, slab_id))
    }

    /// Deallocate memory by allocation ID
    pub fn deallocate(&self, allocation_id: Uuid) -> Result<usize, String> {
        let mut allocations = self.allocations.lock().unwrap();
        
        let (pool_size, slab_id) = allocations
            .remove(&allocation_id)
            .ok_or_else(|| "Allocation not found".to_string())?;

        let mut pools = self.pools.lock().unwrap();
        let pool = pools.get_mut(&pool_size)
            .ok_or_else(|| "Pool not found".to_string())?;

        if pool.deallocate(slab_id) {
            info!("Deallocated allocation {} (slab size: {} bytes)", allocation_id, pool_size);
            Ok(pool_size)
        } else {
            error!("Failed to deallocate slab {} for allocation {}", slab_id, allocation_id);
            Err("Failed to deallocate slab".to_string())
        }
    }

    /// Get total allocated memory across all pools
    pub fn get_total_allocated(&self) -> usize {
        let pools = self.pools.lock().unwrap();
        self.get_total_allocated_internal(&pools)
    }

    fn get_total_allocated_internal(&self, pools: &HashMap<usize, SlabPool>) -> usize {
        pools.values().map(|p| p.total_allocated).sum()
    }

    /// Get total in-use memory
    pub fn get_total_in_use(&self) -> usize {
        let pools = self.pools.lock().unwrap();
        pools.values().map(|p| {
            p.all_slabs.values().filter(|s| s.in_use).count() * p.size
        }).sum()
    }

    /// Get number of active allocations
    pub fn get_active_allocations(&self) -> usize {
        let allocations = self.allocations.lock().unwrap();
        allocations.len()
    }

    /// Get detailed statistics for all pools
    pub fn get_pool_stats(&self) -> Vec<SlabPoolStats> {
        let pools = self.pools.lock().unwrap();
        let mut stats: Vec<_> = pools.values().map(|p| p.get_stats()).collect();
        stats.sort_by_key(|s| s.size);
        stats
    }

    /// Get memory utilization percentage
    pub fn get_utilization(&self) -> f64 {
        let total = self.get_total_allocated();
        if total == 0 {
            0.0
        } else {
            (total as f64 / self.max_pool_size as f64) * 100.0
        }
    }

    /// Get the maximum pool size
    pub fn get_max_pool_size(&self) -> usize {
        self.max_pool_size
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_slab_allocator_basic() {
        let allocator = SlabAllocator::new(vec![1024, 4096, 16384], 1024 * 1024, 2);
        
        // Allocate 500 bytes - should use 1024 byte slab
        let (id, size, _) = allocator.allocate(500).unwrap();
        assert_eq!(size, 1024);
        
        // Deallocate
        let freed = allocator.deallocate(id).unwrap();
        assert_eq!(freed, 1024);
    }

    #[test]
    fn test_slab_allocator_reuse() {
        let allocator = SlabAllocator::new(vec![1024], 10 * 1024, 1);
        
        let (id1, _, _) = allocator.allocate(1000).unwrap();
        allocator.deallocate(id1).unwrap();
        
        let (id2, _, _) = allocator.allocate(1000).unwrap();
        
        // Should have reused the slab
        assert_eq!(allocator.get_active_allocations(), 1);
    }

    #[test]
    fn test_slab_allocator_max_size() {
        let allocator = SlabAllocator::new(vec![1024], 2048, 0);
        
        // Should allocate 2 slabs (2048 bytes total)
        let (id1, _, _) = allocator.allocate(1000).unwrap();
        let (id2, _, _) = allocator.allocate(1000).unwrap();
        
        // Third allocation should fail (would exceed max pool size)
        assert!(allocator.allocate(1000).is_err());
        
        // After deallocation, should be able to allocate again
        allocator.deallocate(id1).unwrap();
        assert!(allocator.allocate(1000).is_ok());
    }
}
