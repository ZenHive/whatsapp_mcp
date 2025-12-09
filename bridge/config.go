package main

import (
	"fmt"
	"os"
	"strconv"
)

// DeviceName is the name shown in WhatsApp's "Linked Devices" list
const DeviceName = "WhatsApp MCP"

// Configuration constants
const (
	// DefaultAPIPort is the default port for the REST API server
	DefaultAPIPort = 8080

	// QRCodeTimeoutMinutes is the timeout for QR code scanning
	QRCodeTimeoutMinutes = 3

	// ConnectionStabilizeDelaySeconds is the delay after connection before starting operations
	ConnectionStabilizeDelaySeconds = 2

	// MinPollOptions is the minimum number of options for a poll
	MinPollOptions = 2

	// MaxPollOptions is the maximum number of options for a poll
	MaxPollOptions = 12

	// DefaultOpusSampleRate is the default sample rate for Opus audio (48kHz)
	DefaultOpusSampleRate = 48000

	// DefaultAudioDurationFallbackSeconds is the fallback duration when analysis fails
	DefaultAudioDurationFallbackSeconds = 30

	// MaxAudioDurationSeconds is the maximum allowed audio duration
	MaxAudioDurationSeconds = 300

	// MinAudioDurationSeconds is the minimum audio duration
	MinAudioDurationSeconds = 1

	// WaveformLength is the expected waveform byte length for WhatsApp voice messages
	WaveformLength = 64

	// MaxFrequencyDurationSeconds is the cap for frequency calculation in waveform generation
	MaxFrequencyDurationSeconds = 120

	// HistorySyncMessageLimit is the number of messages to request in history sync
	HistorySyncMessageLimit = 1000

	// Reconnection constants
	// ReconnectInitialDelaySeconds is the initial delay before first reconnection attempt
	ReconnectInitialDelaySeconds = 1
	// ReconnectMaxDelaySeconds is the maximum delay between reconnection attempts
	ReconnectMaxDelaySeconds = 60
	// ReconnectBackoffMultiplier is the multiplier for exponential backoff
	ReconnectBackoffMultiplier = 2.0
	// ReconnectJitterFactor is the random jitter factor (0.0-1.0) to add to delays
	ReconnectJitterFactor = 0.2
)

// MimeTypes maps file extensions to MIME types for media uploads
var MimeTypes = map[string]string{
	// Image types
	"jpg":  "image/jpeg",
	"jpeg": "image/jpeg",
	"png":  "image/png",
	"gif":  "image/gif",
	"webp": "image/webp",
	// Audio types
	"ogg": "audio/ogg; codecs=opus",
	// Video types
	"mp4": "video/mp4",
	"avi": "video/avi",
	"mov": "video/quicktime",
}

// DefaultMimeType is used for unknown file types
const DefaultMimeType = "application/octet-stream"

// getAPIPort returns the API port from environment variable or default
func getAPIPort() int {
	portStr := os.Getenv("WHATSAPP_BRIDGE_PORT")
	if portStr == "" {
		return DefaultAPIPort
	}
	port, err := strconv.Atoi(portStr)
	if err != nil {
		fmt.Printf("Invalid WHATSAPP_BRIDGE_PORT value '%s', using default %d\n", portStr, DefaultAPIPort)
		return DefaultAPIPort
	}
	return port
}
