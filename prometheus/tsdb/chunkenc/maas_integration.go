package chunkenc

import "github.com/prometheus/prometheus/tsdb/maas"

// Global MaaS allocator - initialized by TSDB if enabled
var globalMaaSAllocator *maas.ChunkAllocator

// SetMaaSAllocator sets the global MaaS allocator
func SetMaaSAllocator(allocator *maas.ChunkAllocator) {
	globalMaaSAllocator = allocator
}

// allocateChunkBytes allocates memory for a chunk, using MaaS if available
func allocateChunkBytes(size, capacity int) []byte {
	if globalMaaSAllocator != nil {
		// Try MaaS allocation
		if data, err := globalMaaSAllocator.AllocateChunk(capacity); err == nil {
			return data[:size]
		}
		// Fallback happens automatically in allocator
	}
	
	// Native allocation
	return make([]byte, size, capacity)
}
