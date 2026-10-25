package main

import (
	"context"
	"sync"
	"time"
)

// Cancellation must not wait for coreMu: the active test holds it to protect
// the service lifetime. Stop/reload still wait until the cancelled test exits.
type urlTestCancellation struct {
	mu         sync.Mutex
	generation uint64
	cancel     context.CancelFunc
}

var activeURLTest urlTestCancellation

func (c *urlTestCancellation) begin(parent context.Context) (context.Context, func()) {
	ctx, cancel := context.WithTimeout(parent, 15*time.Second)
	c.mu.Lock()
	c.generation++
	generation := c.generation
	if c.cancel != nil {
		c.cancel()
	}
	c.cancel = cancel
	c.mu.Unlock()
	return ctx, func() {
		cancel()
		c.mu.Lock()
		if c.generation == generation {
			c.cancel = nil
		}
		c.mu.Unlock()
	}
}

func (c *urlTestCancellation) interrupt() {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.cancel != nil {
		c.cancel()
	}
}
