package maas

import (
	"log/slog"
	"runtime"
	"sync"
	"sync/atomic"
	"time"
)

// MemoryPoolManager manages allocation strategy between local and MaaS memory
type MemoryPoolManager struct {
	maasClient *Client
	logger     *slog.Logger
	
	// Configuration
	localMemoryThreshold  uint64 // Bytes - switch to MaaS when local exceeds this
	maasEnabled          atomic.Bool
	fallbackEnabled      bool
	
	// Statistics
	localAllocations  atomic.Uint64
	maasAllocations   atomic.Uint64
	totalAllocated    atomic.Uint64
	fallbackCount     atomic.Uint64
	
	// State
	mu                sync.RWMutex
	lastHealthCheck   time.Time
	healthCheckFailed bool
}

// PoolStats contains memory pool statistics
type PoolStats struct {
	LocalAllocations  uint64
	MaaSAllocations   uint64
	TotalAllocated    uint64
	FallbackCount     uint64
	MaaSAvailable     bool
	MemoryStats       runtime.MemStats
}

// NewMemoryPoolManager creates a new memory pool manager
func NewMemoryPoolManager(maasURL string, localThresholdMB uint64, fallbackEnabled bool, logger *slog.Logger) *MemoryPoolManager {
	if logger == nil {
		logger = slog.Default()
	}
	
	var client *Client
	if maasURL != "" {
		client = NewClient(maasURL)
	}
	
	mgr := &MemoryPoolManager{
		maasClient:           client,
		logger:               logger,
		localMemoryThreshold: localThresholdMB * 1024 * 1024,
		fallbackEnabled:      fallbackEnabled,
	}
	
	if client != nil {
		mgr.maasEnabled.Store(true)
	}
	
	return mgr
}

// Initialize connects to MaaS and starts monitoring
func (m *MemoryPoolManager) Initialize() error {
	if m.maasClient == nil {
		m.logger.Info("MaaS integration disabled")
		return nil
	}
	
	if err := m.maasClient.Connect(); err != nil {
		if m.fallbackEnabled {
			m.logger.Warn("Failed to connect to MaaS, using local memory only", "error", err)
			m.maasEnabled.Store(false)
			return nil
		}
		return err
	}
	
	m.logger.Info("MaaS memory pool manager initialized",
		"threshold_mb", m.localMemoryThreshold/1024/1024,
		"fallback", m.fallbackEnabled)
	
	// Start health monitoring
	go m.healthMonitor()
	
	return nil
}

// shouldUseMaaS determines if MaaS should be used for allocation
func (m *MemoryPoolManager) shouldUseMaaS() bool {
	if !m.maasEnabled.Load() {
		return false
	}
	
	// Check if MaaS is healthy
	m.mu.RLock()
	healthyMaaS := !m.healthCheckFailed
	m.mu.RUnlock()
	
	// Use MaaS whenever it's available and healthy to maximize utilization
	// This allows MaaS to manage its own buffer pool efficiently
	return healthyMaaS
}

// AllocateBytes allocates memory, choosing between local and MaaS
func (m *MemoryPoolManager) AllocateBytes(size int) ([]byte, string, error) {
	if m.shouldUseMaaS() {
		// Try MaaS allocation
		alloc, err := m.maasClient.Allocate(size)
		if err != nil {
			m.logger.Warn("MaaS allocation failed, falling back to local", 
				"size", size, "error", err)
			m.fallbackCount.Add(1)
			
			if m.fallbackEnabled {
				// Fallback to local
				m.localAllocations.Add(1)
				m.totalAllocated.Add(uint64(size))
				return make([]byte, size), "", nil
			}
			return nil, "", err
		}
		
		m.maasAllocations.Add(1)
		m.totalAllocated.Add(uint64(alloc.ActualSizeBytes))
		m.logger.Debug("Allocated from MaaS",
			"id", alloc.ID,
			"requested", size,
			"actual", alloc.ActualSizeBytes)
		
		return alloc.Data[:size], alloc.ID, nil
	}
	
	// Use local memory
	m.localAllocations.Add(1)
	m.totalAllocated.Add(uint64(size))
	return make([]byte, size), "", nil
}

// DeallocateBytes frees memory back to appropriate pool
func (m *MemoryPoolManager) DeallocateBytes(data []byte, allocID string) error {
	if allocID == "" {
		// Local allocation, let GC handle it
		return nil
	}
	
	// MaaS allocation
	if err := m.maasClient.Deallocate(allocID); err != nil {
		m.logger.Warn("Failed to deallocate from MaaS", "id", allocID, "error", err)
		return err
	}
	
	m.logger.Debug("Deallocated from MaaS", "id", allocID)
	return nil
}

// GetStats returns current pool statistics
func (m *MemoryPoolManager) GetStats() PoolStats {
	var mem runtime.MemStats
	runtime.ReadMemStats(&mem)
	
	stats := PoolStats{
		LocalAllocations: m.localAllocations.Load(),
		MaaSAllocations:  m.maasAllocations.Load(),
		TotalAllocated:   m.totalAllocated.Load(),
		FallbackCount:    m.fallbackCount.Load(),
		MaaSAvailable:    m.maasEnabled.Load() && m.maasClient != nil && m.maasClient.IsConnected(),
		MemoryStats:      mem,
	}
	
	return stats
}

// healthMonitor periodically checks MaaS health
func (m *MemoryPoolManager) healthMonitor() {
	if m.maasClient == nil {
		return
	}
	
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()
	
	for range ticker.C {
		err := m.maasClient.Connect()
		
		m.mu.Lock()
		m.lastHealthCheck = time.Now()
		m.healthCheckFailed = err != nil
		m.mu.Unlock()
		
		if err != nil {
			if m.maasEnabled.Load() {
				m.logger.Warn("MaaS health check failed, disabling", "error", err)
				m.maasEnabled.Store(false)
			}
		} else {
			if !m.maasEnabled.Load() {
				m.logger.Info("MaaS health check succeeded, re-enabling")
				m.maasEnabled.Store(true)
			}
		}
	}
}

// Cleanup deallocates all MaaS allocations
func (m *MemoryPoolManager) Cleanup() error {
	if m.maasClient == nil {
		return nil
	}
	
	m.logger.Info("Cleaning up MaaS allocations")
	return m.maasClient.Cleanup()
}

// SetThreshold updates the local memory threshold (in MB)
func (m *MemoryPoolManager) SetThreshold(thresholdMB uint64) {
	m.localMemoryThreshold = thresholdMB * 1024 * 1024
	m.logger.Info("Updated memory threshold", "threshold_mb", thresholdMB)
}
