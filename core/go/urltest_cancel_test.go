package main

import (
	"context"
	"testing"
	"time"
)

func TestURLTestInterruptDoesNotNeedCoreLock(t *testing.T) {
	var c urlTestCancellation
	ctx, finish := c.begin(context.Background())
	defer finish()
	c.interrupt()
	select {
	case <-ctx.Done():
	case <-time.After(time.Second):
		t.Fatal("URLTest cancellation blocked")
	}
}

func TestOldCompletionCannotClearNewCancellation(t *testing.T) {
	var c urlTestCancellation
	old, finishOld := c.begin(context.Background())
	current, finishCurrent := c.begin(context.Background())
	defer finishCurrent()
	if old.Err() != context.Canceled {
		t.Fatal("old request still active")
	}
	finishOld()
	c.interrupt()
	if current.Err() != context.Canceled {
		t.Fatal("old completion lost current cancellation")
	}
}

func TestCancellationCanBeReused(t *testing.T) {
	var c urlTestCancellation
	c.interrupt()
	_, done := c.begin(context.Background())
	done()
	c.interrupt()
	next, doneNext := c.begin(context.Background())
	defer doneNext()
	if next.Err() != nil {
		t.Fatal("fresh test inherited previous cancellation")
	}
}
