package main

import (
	"bytes"
	"context"
	"encoding/binary"
	"fmt"
	"math"
	"math/rand"
	"os"
	"path/filepath"
	"strings"

	"go.mau.fi/whatsmeow"
	waLog "go.mau.fi/whatsmeow/util/log"
)

// GetDirectPath implements the DownloadableMessage interface
func (d *MediaDownloader) GetDirectPath() string {
	return d.DirectPath
}

// GetURL implements the DownloadableMessage interface
func (d *MediaDownloader) GetURL() string {
	return d.URL
}

// GetMediaKey implements the DownloadableMessage interface
func (d *MediaDownloader) GetMediaKey() []byte {
	return d.MediaKey
}

// GetFileLength implements the DownloadableMessage interface
func (d *MediaDownloader) GetFileLength() uint64 {
	return d.FileLength
}

// GetFileSHA256 implements the DownloadableMessage interface
func (d *MediaDownloader) GetFileSHA256() []byte {
	return d.FileSHA256
}

// GetFileEncSHA256 implements the DownloadableMessage interface
func (d *MediaDownloader) GetFileEncSHA256() []byte {
	return d.FileEncSHA256
}

// GetMediaType implements the DownloadableMessage interface
func (d *MediaDownloader) GetMediaType() whatsmeow.MediaType {
	return d.MediaType
}

// sanitizePath removes potentially dangerous characters from a path component
func sanitizePath(s string) string {
	s = strings.ReplaceAll(s, "..", "")
	s = strings.ReplaceAll(s, "/", "_")
	s = strings.ReplaceAll(s, "\\", "_")
	s = strings.ReplaceAll(s, ":", "_")
	return s
}

// downloadMedia downloads media from a WhatsApp message
func downloadMedia(ctx context.Context, client *whatsmeow.Client, messageStore *MessageStore, messageID, chatJID string, logger waLog.Logger) (bool, string, string, string, error) {
	// Get media info from database
	mediaInfo, err := getMediaInfoFromDB(messageStore, messageID, chatJID)
	if err != nil {
		return false, "", "", "", err
	}

	// Prepare file path
	localPath, absPath, err := prepareMediaPath(chatJID, mediaInfo.filename)
	if err != nil {
		return false, "", "", "", err
	}

	// Check if file already exists
	if _, err := os.Stat(localPath); err == nil {
		return true, mediaInfo.mediaType, mediaInfo.filename, absPath, nil
	}

	// Validate we have all required info for download
	if err := validateMediaInfo(mediaInfo); err != nil {
		return false, "", "", "", err
	}

	logger.Infof("Downloading media for message %s in chat %s...", messageID, chatJID)

	// Download and save the media
	if err := downloadAndSaveMedia(ctx, client, mediaInfo, localPath, logger); err != nil {
		return false, "", "", "", err
	}

	return true, mediaInfo.mediaType, mediaInfo.filename, absPath, nil
}

// mediaInfo holds the information needed to download media
type mediaInfo struct {
	mediaType     string
	filename      string
	url           string
	mediaKey      []byte
	fileSHA256    []byte
	fileEncSHA256 []byte
	fileLength    uint64
}

// getMediaInfoFromDB retrieves media information from the database
func getMediaInfoFromDB(messageStore *MessageStore, messageID, chatJID string) (*mediaInfo, error) {
	mediaType, filename, url, mediaKey, fileSHA256, fileEncSHA256, fileLength, err := messageStore.GetMediaInfo(messageID, chatJID)
	if err != nil {
		// Try basic info as fallback
		mediaType, filename, err = messageStore.GetBasicMediaInfo(messageID, chatJID)
		if err != nil {
			return nil, fmt.Errorf("failed to find message: %v", err)
		}
	}

	if mediaType == "" {
		return nil, fmt.Errorf("not a media message")
	}

	return &mediaInfo{
		mediaType:     mediaType,
		filename:      filename,
		url:           url,
		mediaKey:      mediaKey,
		fileSHA256:    fileSHA256,
		fileEncSHA256: fileEncSHA256,
		fileLength:    fileLength,
	}, nil
}

// prepareMediaPath creates the directory and returns paths for saving media
func prepareMediaPath(chatJID, filename string) (localPath, absPath string, err error) {
	safeChatJID := sanitizePath(chatJID)
	chatDir := filepath.Join("store", safeChatJID)

	if err := os.MkdirAll(chatDir, 0755); err != nil {
		return "", "", fmt.Errorf("failed to create chat directory: %v", err)
	}

	safeFilename := sanitizePath(filename)
	localPath = filepath.Join(chatDir, safeFilename)

	absPath, err = filepath.Abs(localPath)
	if err != nil {
		return "", "", fmt.Errorf("failed to get absolute path: %v", err)
	}

	return localPath, absPath, nil
}

// validateMediaInfo checks if we have all required information for download
func validateMediaInfo(info *mediaInfo) error {
	if info.url == "" || len(info.mediaKey) == 0 || len(info.fileSHA256) == 0 || len(info.fileEncSHA256) == 0 || info.fileLength == 0 {
		return fmt.Errorf("incomplete media information for download")
	}
	return nil
}

// downloadAndSaveMedia downloads the media from WhatsApp and saves it to disk
func downloadAndSaveMedia(ctx context.Context, client *whatsmeow.Client, info *mediaInfo, localPath string, logger waLog.Logger) error {
	directPath := extractDirectPathFromURL(info.url)

	waMediaType, err := getWhatsAppMediaType(info.mediaType)
	if err != nil {
		return err
	}

	downloader := &MediaDownloader{
		URL:           info.url,
		DirectPath:    directPath,
		MediaKey:      info.mediaKey,
		FileLength:    info.fileLength,
		FileSHA256:    info.fileSHA256,
		FileEncSHA256: info.fileEncSHA256,
		MediaType:     waMediaType,
	}

	mediaData, err := client.Download(ctx, downloader)
	if err != nil {
		return fmt.Errorf("failed to download media: %v", err)
	}

	if err := os.WriteFile(localPath, mediaData, 0644); err != nil {
		return fmt.Errorf("failed to save media file: %v", err)
	}

	absPath, _ := filepath.Abs(localPath)
	logger.Infof("Downloaded %s media to %s (%d bytes)", info.mediaType, absPath, len(mediaData))
	return nil
}

// getWhatsAppMediaType converts a string media type to whatsmeow.MediaType
func getWhatsAppMediaType(mediaType string) (whatsmeow.MediaType, error) {
	switch mediaType {
	case "image":
		return whatsmeow.MediaImage, nil
	case "video":
		return whatsmeow.MediaVideo, nil
	case "audio":
		return whatsmeow.MediaAudio, nil
	case "document":
		return whatsmeow.MediaDocument, nil
	default:
		return whatsmeow.MediaDocument, fmt.Errorf("unsupported media type: %s", mediaType)
	}
}

// extractDirectPathFromURL extracts the direct path from a WhatsApp media URL
func extractDirectPathFromURL(url string) string {
	parts := strings.SplitN(url, ".net/", 2)
	if len(parts) < 2 {
		return url
	}

	pathPart := parts[1]
	pathPart = strings.SplitN(pathPart, "?", 2)[0]

	return "/" + pathPart
}

// analyzeOggOpus extracts duration and generates a waveform from an Ogg Opus file
func analyzeOggOpus(data []byte) (duration uint32, waveform []byte, err error) {
	if len(data) < 4 || string(data[0:4]) != "OggS" {
		return 0, nil, fmt.Errorf("not a valid Ogg file (missing OggS signature)")
	}

	var lastGranule uint64
	var sampleRate uint32 = DefaultOpusSampleRate
	var preSkip uint16 = 0
	var foundOpusHead bool

	// Scan through the file looking for Ogg pages
	for i := 0; i < len(data); {
		if i+27 >= len(data) {
			break
		}

		if string(data[i:i+4]) != "OggS" {
			i++
			continue
		}

		granulePos := binary.LittleEndian.Uint64(data[i+6 : i+14])
		pageSeqNum := binary.LittleEndian.Uint32(data[i+18 : i+22])
		numSegments := int(data[i+26])

		if i+27+numSegments >= len(data) {
			break
		}
		segmentTable := data[i+27 : i+27+numSegments]

		pageSize := 27 + numSegments
		for _, segLen := range segmentTable {
			pageSize += int(segLen)
		}

		// Look for OpusHead in first pages
		if !foundOpusHead && pageSeqNum <= 1 {
			pageData := data[i : i+pageSize]
			headPos := bytes.Index(pageData, []byte("OpusHead"))
			if headPos >= 0 && headPos+12 < len(pageData) {
				headPos += 8
				if headPos+12 <= len(pageData) {
					preSkip = binary.LittleEndian.Uint16(pageData[headPos+10 : headPos+12])
					sampleRate = binary.LittleEndian.Uint32(pageData[headPos+12 : headPos+16])
					foundOpusHead = true
				}
			}
		}

		if granulePos != 0 {
			lastGranule = granulePos
		}

		i += pageSize
	}

	// Calculate duration
	if lastGranule > 0 {
		durationSeconds := float64(lastGranule-uint64(preSkip)) / float64(sampleRate)
		duration = uint32(math.Ceil(durationSeconds))
	} else {
		durationEstimate := float64(len(data)) / 2000.0
		duration = uint32(durationEstimate)
	}

	// Clamp duration
	duration = clampUint32(duration, MinAudioDurationSeconds, MaxAudioDurationSeconds)

	waveform = placeholderWaveform(duration)

	return duration, waveform, nil
}

// clampUint32 constrains a value between min and max
func clampUint32(value, minVal, maxVal uint32) uint32 {
	if value < minVal {
		return minVal
	}
	if value > maxVal {
		return maxVal
	}
	return value
}

// placeholderWaveform generates a synthetic waveform for WhatsApp voice messages.
// Uses duration as seed for deterministic but varied waveforms.
func placeholderWaveform(duration uint32) []byte {
	waveform := make([]byte, WaveformLength)

	rng := rand.New(rand.NewSource(int64(duration)))

	baseAmplitude := 35.0
	frequencyFactor := float64(min(int(duration), MaxFrequencyDurationSeconds)) / 30.0

	for i := range waveform {
		pos := float64(i) / float64(WaveformLength)

		val := baseAmplitude * math.Sin(pos*math.Pi*frequencyFactor*8)
		val += (baseAmplitude / 2) * math.Sin(pos*math.Pi*frequencyFactor*16)
		val += (rng.Float64() - 0.5) * 15

		fadeInOut := math.Sin(pos * math.Pi)
		val = val * (0.7 + 0.3*fadeInOut)
		val = val + 50

		if val < 0 {
			val = 0
		} else if val > 100 {
			val = 100
		}

		waveform[i] = byte(val)
	}

	return waveform
}
