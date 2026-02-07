// Package maas provides integration with Memory-as-a-Service backend
// for Prometheus to allocate chunks from remote memory server
package maas

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"sync"
	"time"
)

// Client manages connections to MaaS backend
type Client struct {
	baseURL    string
	httpClient *http.Client
	mu         sync.RWMutex
	allocations map[string]*Allocation
	connected  bool
}

// Allocation represents a memory allocation from MaaS
type Allocation struct {
	ID               string
	SizeBytes        int
	ActualSizeBytes  int
	Data             []byte
	AllocatedAt      time.Time
}

// AllocateRequest is sent to MaaS to request memory
type AllocateRequest struct {
	SizeBytes int `json:"size_bytes"`
}

// AllocateResponse is received from MaaS after allocation
type AllocateResponse struct {
	ID              string  `json:"id"`
	SizeBytes       int     `json:"size_bytes"`
	ActualSizeBytes int     `json:"actual_size_bytes"`
	SizeMB          float64 `json:"size_mb"`
	AgeSeconds      int64   `json:"age_seconds"`
}

// NewClient creates a new MaaS client
func NewClient(baseURL string) *Client {
	return &Client{
		baseURL: baseURL,
		httpClient: &http.Client{
			Timeout: 10 * time.Second,
		},
		allocations: make(map[string]*Allocation),
		connected:   false,
	}
}

// Connect tests connection to MaaS backend
func (c *Client) Connect() error {
	resp, err := c.httpClient.Get(c.baseURL + "/health")
	if err != nil {
		c.connected = false
		return fmt.Errorf("failed to connect to MaaS: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		c.connected = false
		return fmt.Errorf("MaaS health check failed: %d", resp.StatusCode)
	}

	c.connected = true
	return nil
}

// IsConnected returns true if connected to MaaS backend
func (c *Client) IsConnected() bool {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.connected
}

// Allocate requests memory from MaaS backend
func (c *Client) Allocate(sizeBytes int) (*Allocation, error) {
	reqBody := AllocateRequest{SizeBytes: sizeBytes}
	jsonData, err := json.Marshal(reqBody)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal request: %w", err)
	}

	resp, err := c.httpClient.Post(
		c.baseURL+"/allocate",
		"application/json",
		bytes.NewBuffer(jsonData),
	)
	if err != nil {
		c.connected = false
		return nil, fmt.Errorf("failed to allocate from MaaS: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("allocation failed (%d): %s", resp.StatusCode, string(body))
	}

	var allocResp AllocateResponse
	if err := json.NewDecoder(resp.Body).Decode(&allocResp); err != nil {
		return nil, fmt.Errorf("failed to decode response: %w", err)
	}

	alloc := &Allocation{
		ID:              allocResp.ID,
		SizeBytes:       allocResp.SizeBytes,
		ActualSizeBytes: allocResp.ActualSizeBytes,
		Data:            make([]byte, allocResp.ActualSizeBytes),
		AllocatedAt:     time.Now(),
	}

	c.mu.Lock()
	c.allocations[alloc.ID] = alloc
	c.mu.Unlock()

	return alloc, nil
}

// Deallocate releases memory back to MaaS
func (c *Client) Deallocate(id string) error {
	req, err := http.NewRequest(http.MethodDelete, c.baseURL+"/allocate/"+id, nil)
	if err != nil {
		return fmt.Errorf("failed to create request: %w", err)
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		c.connected = false
		return fmt.Errorf("failed to deallocate from MaaS: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusNotFound {
		return fmt.Errorf("deallocation failed: %d", resp.StatusCode)
	}

	c.mu.Lock()
	delete(c.allocations, id)
	c.mu.Unlock()

	return nil
}

// GetStats returns current allocation statistics
func (c *Client) GetStats() (activeCount int, totalBytes int) {
	c.mu.RLock()
	defer c.mu.RUnlock()
	
	activeCount = len(c.allocations)
	for _, alloc := range c.allocations {
		totalBytes += alloc.ActualSizeBytes
	}
	return
}

// Cleanup deallocates all active allocations
func (c *Client) Cleanup() error {
	c.mu.Lock()
	ids := make([]string, 0, len(c.allocations))
	for id := range c.allocations {
		ids = append(ids, id)
	}
	c.mu.Unlock()

	var firstErr error
	for _, id := range ids {
		if err := c.Deallocate(id); err != nil && firstErr == nil {
			firstErr = err
		}
	}
	return firstErr
}
