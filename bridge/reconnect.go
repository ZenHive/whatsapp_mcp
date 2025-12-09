package main

import (
	"math"
	"math/rand"
	"time"

	"go.mau.fi/whatsmeow"
	waLog "go.mau.fi/whatsmeow/util/log"
)

// NewReconnectManager creates a new reconnection manager
func NewReconnectManager(client *whatsmeow.Client, logger waLog.Logger) *ReconnectManager {
	return &ReconnectManager{
		client:   client,
		logger:   logger,
		stopChan: make(chan struct{}),
	}
}

// calculateBackoff returns the delay for the given attempt number with jitter
func (rm *ReconnectManager) calculateBackoff(attempt int) time.Duration {
	// Calculate base delay with exponential backoff
	delay := float64(ReconnectInitialDelaySeconds) * math.Pow(ReconnectBackoffMultiplier, float64(attempt))

	// Cap at maximum delay
	if delay > float64(ReconnectMaxDelaySeconds) {
		delay = float64(ReconnectMaxDelaySeconds)
	}

	// Add random jitter to prevent thundering herd
	jitter := delay * ReconnectJitterFactor * (rand.Float64()*2 - 1) // -jitter to +jitter
	delay += jitter

	return time.Duration(delay * float64(time.Second))
}

// StartReconnect initiates the reconnection process
func (rm *ReconnectManager) StartReconnect(reason string) {
	rm.mu.Lock()
	if rm.isReconnecting {
		rm.mu.Unlock()
		rm.logger.Infof("Reconnection already in progress, skipping")
		return
	}
	rm.isReconnecting = true
	rm.mu.Unlock()

	go rm.reconnectLoop(reason)
}

// reconnectLoop attempts to reconnect with exponential backoff
func (rm *ReconnectManager) reconnectLoop(reason string) {
	defer func() {
		rm.mu.Lock()
		rm.isReconnecting = false
		rm.mu.Unlock()
	}()

	rm.logger.Warnf("Connection lost: %s. Starting reconnection attempts...", reason)

	attempt := 0
	for {
		select {
		case <-rm.stopChan:
			rm.logger.Infof("Reconnection stopped by shutdown signal")
			return
		default:
		}

		// Check if already connected
		if rm.client.IsConnected() {
			rm.logger.Infof("Already connected, stopping reconnection loop")
			return
		}

		// Calculate backoff delay
		delay := rm.calculateBackoff(attempt)
		rm.logger.Infof("Reconnection attempt %d in %v...", attempt+1, delay.Round(time.Millisecond))

		// Wait before attempting reconnection
		select {
		case <-rm.stopChan:
			rm.logger.Infof("Reconnection stopped by shutdown signal during wait")
			return
		case <-time.After(delay):
		}

		// Attempt to connect
		err := rm.client.Connect()
		if err != nil {
			rm.logger.Warnf("Reconnection attempt %d failed: %v", attempt+1, err)
			attempt++
			continue
		}

		// Wait a moment for connection to stabilize
		time.Sleep(ConnectionStabilizeDelaySeconds * time.Second)

		if rm.client.IsConnected() {
			rm.logger.Infof("Reconnection successful after %d attempt(s)", attempt+1)
			return
		}

		rm.logger.Warnf("Connection not stable after attempt %d", attempt+1)
		attempt++
	}
}

// Stop signals the reconnection manager to stop
func (rm *ReconnectManager) Stop() {
	close(rm.stopChan)
}
