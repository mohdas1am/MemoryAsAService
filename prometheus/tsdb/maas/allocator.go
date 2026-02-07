package maas

import (
	"fmt"
	"log/slog"
	"sync"
	"unsafe"
)

// ChunkAllocator manages chunk allocation using MaaS backend with intelligent pooling
type ChunkAllocator struct {
	poolManager  *MemoryPoolManager
	logger       *slog.Logger
	mu           sync.RWMutex
	chunkToAlloc map[uintptr]string // Maps chunk memory address to MaaS allocation ID
}

const (
	// DefaultChunkSize is typical Prometheus chunk size
	DefaultChunkSize = 1024
	// DefaultLocalThresholdMB is when to start using MaaS (512MB)
	DefaultLocalThresholdMB = 512
)

// NewChunkAllocator creates a new MaaS-backed chunk allocator
func NewChunkAllocator(maasURL string, logger *slog.Logger, fallback bool) *ChunkAllocator {
	return &ChunkAllocator{
		poolManager:  NewMemoryPoolManager(maasURL, DefaultLocalThresholdMB, fallback, logger),
		logger:       logger,
		chunkToAlloc: make(map[uintptr]string),
	}
}

// Initialize connects to MaaS backend
func (ca *ChunkAllocator) Initialize() error {
	return ca.poolManager.Initialize()
}

// AllocateChunk allocates memory for a chunk, intelligently choosing local vs MaaS
func (ca *ChunkAllocator) AllocateChunk(size int) ([]byte, error) {
	// Use pool manager to decide allocation strategy
	data, allocID, err := ca.poolManager.AllocateBytes(size)
	if err != nil {
		return nil, fmt.Errorf("failed to allocate chunk: %w", err)
	}
	
	// Track MaaS allocations
	if allocID != "" {
		chunkPtr := uintptr(0)
		if len(data) > 0 {
			chunkPtr = uintptr(unsafe.Pointer(&data[0]))
		}
		
		ca.mu.Lock()
		ca.chunkToAlloc[chunkPtr] = allocID
		ca.mu.Unlock()
	}
	
	return data, nil
}

// DeallocateChunk releases chunk memory back to appropriate pool
func (ca *ChunkAllocator) DeallocateChunk(chunk []byte) error {
	if len(chunk) == 0 {
		return nil
	}

	chunkPtr := uintptr(unsafe.Pointer(&chunk[0]))
	
	ca.mu.Lock()
	allocID, exists := ca.chunkToAlloc[chunkPtr]
	if exists {
		delete(ca.chunkToAlloc, chunkPtr)
	}
	ca.mu.Unlock()

	if !exists {
		// Local allocation, let GC handle it
		return nil
	}

	// Deallocate from MaaS
	return ca.poolManager.DeallocateBytes(chunk, allocID)
}

// GetStats returns allocation statistics
func (ca *ChunkAllocator) GetStats() PoolStats {
	return ca.poolManager.GetStats()
}

// IsEnabled returns true if MaaS allocation is active
func (ca *ChunkAllocator) IsEnabled() bool {
	stats := ca.poolManager.GetStats()
	return stats.MaaSAvailable
}

// Cleanup deallocates all chunks and closes connection
func (ca *ChunkAllocator) Cleanup() error {
	ca.logger.Info("Cleaning up chunk allocator")
	return ca.poolManager.Cleanup()
}

// SetThreshold updates when to use MaaS (in MB)
func (ca *ChunkAllocator) SetThreshold(thresholdMB uint64) {
	ca.poolManager.SetThreshold(thresholdMB)
}