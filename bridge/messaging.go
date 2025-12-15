package main

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"go.mau.fi/whatsmeow"
	waProto "go.mau.fi/whatsmeow/binary/proto"
	"go.mau.fi/whatsmeow/types"
	waLog "go.mau.fi/whatsmeow/util/log"
	"google.golang.org/protobuf/proto"
)

// extractTextContent extracts text content from a WhatsApp message
func extractTextContent(msg *waProto.Message) string {
	if msg == nil {
		return ""
	}

	if text := msg.GetConversation(); text != "" {
		return text
	}
	if extendedText := msg.GetExtendedTextMessage(); extendedText != nil {
		return extendedText.GetText()
	}

	return ""
}

// sendWhatsAppMessage sends a WhatsApp message to the specified recipient
func sendWhatsAppMessage(ctx context.Context, client *whatsmeow.Client, recipient string, message string, mediaPath string, logger waLog.Logger) (bool, string) {
	if !client.IsConnected() {
		return false, "Not connected to WhatsApp"
	}

	recipientJID, err := parseRecipientJID(recipient)
	if err != nil {
		return false, fmt.Sprintf("Error parsing JID: %v", err)
	}

	var msg *waProto.Message
	if mediaPath != "" {
		msg, err = buildMediaMessage(ctx, client, mediaPath, message, logger)
		if err != nil {
			return false, err.Error()
		}
	} else {
		msg = &waProto.Message{
			Conversation: proto.String(message),
		}
	}

	_, err = client.SendMessage(ctx, recipientJID, msg)
	if err != nil {
		return false, fmt.Sprintf("Error sending message: %v", err)
	}

	return true, fmt.Sprintf("Message sent to %s", recipient)
}

// buildMediaMessage creates a media message from a file path
func buildMediaMessage(ctx context.Context, client *whatsmeow.Client, mediaPath string, caption string, logger waLog.Logger) (*waProto.Message, error) {
	mediaData, err := os.ReadFile(mediaPath)
	if err != nil {
		return nil, fmt.Errorf("error reading media file: %v", err)
	}

	fileExt := extractFileExtension(mediaPath)
	mediaType, mimeType := getMediaTypeFromExtension(fileExt)

	resp, err := client.Upload(ctx, mediaData, mediaType)
	if err != nil {
		return nil, fmt.Errorf("error uploading media: %v", err)
	}

	logger.Infof("Media uploaded: %s (%d bytes)", mimeType, len(mediaData))

	return createMediaProtoMessage(mediaType, mimeType, mediaPath, caption, mediaData, &resp, logger)
}

// getMediaTypeFromExtension returns the WhatsApp media type and MIME type for a file extension
func getMediaTypeFromExtension(ext string) (whatsmeow.MediaType, string) {
	mimeType, found := MimeTypes[ext]
	if !found {
		return whatsmeow.MediaDocument, DefaultMimeType
	}

	switch ext {
	case "jpg", "jpeg", "png", "gif", "webp":
		return whatsmeow.MediaImage, mimeType
	case "ogg":
		return whatsmeow.MediaAudio, mimeType
	case "mp4", "avi", "mov":
		return whatsmeow.MediaVideo, mimeType
	default:
		return whatsmeow.MediaDocument, mimeType
	}
}

// createMediaProtoMessage creates the appropriate protobuf message for the media type
func createMediaProtoMessage(mediaType whatsmeow.MediaType, mimeType string, mediaPath string, caption string, mediaData []byte, resp *whatsmeow.UploadResponse, logger waLog.Logger) (*waProto.Message, error) {
	msg := &waProto.Message{}

	switch mediaType {
	case whatsmeow.MediaImage:
		msg.ImageMessage = &waProto.ImageMessage{
			Caption:       proto.String(caption),
			Mimetype:      proto.String(mimeType),
			URL:           &resp.URL,
			DirectPath:    &resp.DirectPath,
			MediaKey:      resp.MediaKey,
			FileEncSHA256: resp.FileEncSHA256,
			FileSHA256:    resp.FileSHA256,
			FileLength:    &resp.FileLength,
		}

	case whatsmeow.MediaAudio:
		audioMsg, err := buildAudioMessage(mimeType, mediaData, resp, logger)
		if err != nil {
			return nil, err
		}
		msg.AudioMessage = audioMsg

	case whatsmeow.MediaVideo:
		msg.VideoMessage = &waProto.VideoMessage{
			Caption:       proto.String(caption),
			Mimetype:      proto.String(mimeType),
			URL:           &resp.URL,
			DirectPath:    &resp.DirectPath,
			MediaKey:      resp.MediaKey,
			FileEncSHA256: resp.FileEncSHA256,
			FileSHA256:    resp.FileSHA256,
			FileLength:    &resp.FileLength,
		}

	case whatsmeow.MediaDocument:
		filename := extractFilename(mediaPath)
		msg.DocumentMessage = &waProto.DocumentMessage{
			Title:         proto.String(filename),
			FileName:      proto.String(filename),
			Caption:       proto.String(caption),
			Mimetype:      proto.String(mimeType),
			URL:           &resp.URL,
			DirectPath:    &resp.DirectPath,
			MediaKey:      resp.MediaKey,
			FileEncSHA256: resp.FileEncSHA256,
			FileSHA256:    resp.FileSHA256,
			FileLength:    &resp.FileLength,
		}
	}

	return msg, nil
}

// buildAudioMessage creates an audio message with duration and waveform analysis
func buildAudioMessage(mimeType string, mediaData []byte, resp *whatsmeow.UploadResponse, logger waLog.Logger) (*waProto.AudioMessage, error) {
	var seconds uint32 = DefaultAudioDurationFallbackSeconds
	var waveform []byte

	if strings.Contains(mimeType, "ogg") {
		analyzedSeconds, analyzedWaveform, err := analyzeOggOpus(mediaData)
		if err != nil {
			return nil, fmt.Errorf("failed to analyze Ogg Opus file: %v", err)
		}
		seconds = analyzedSeconds
		waveform = analyzedWaveform
	} else {
		logger.Infof("Not an Ogg Opus file: %s", mimeType)
	}

	return &waProto.AudioMessage{
		Mimetype:      proto.String(mimeType),
		URL:           &resp.URL,
		DirectPath:    &resp.DirectPath,
		MediaKey:      resp.MediaKey,
		FileEncSHA256: resp.FileEncSHA256,
		FileSHA256:    resp.FileSHA256,
		FileLength:    &resp.FileLength,
		Seconds:       proto.Uint32(seconds),
		PTT:           proto.Bool(true),
		Waveform:      waveform,
	}, nil
}

// extractFilename extracts the filename from a path
func extractFilename(path string) string {
	lastSlash := strings.LastIndex(path, "/")
	if lastSlash >= 0 && lastSlash < len(path)-1 {
		return path[lastSlash+1:]
	}
	return path
}

// extractMediaInfo extracts media information from a WhatsApp message
func extractMediaInfo(msg *waProto.Message) (mediaType string, filename string, url string, mediaKey []byte, fileSHA256 []byte, fileEncSHA256 []byte, fileLength uint64) {
	if msg == nil {
		return "", "", "", nil, nil, nil, 0
	}

	timestamp := time.Now().Format("20060102_150405")

	if img := msg.GetImageMessage(); img != nil {
		return "image", "image_" + timestamp + ".jpg",
			img.GetURL(), img.GetMediaKey(), img.GetFileSHA256(), img.GetFileEncSHA256(), img.GetFileLength()
	}

	if vid := msg.GetVideoMessage(); vid != nil {
		return "video", "video_" + timestamp + ".mp4",
			vid.GetURL(), vid.GetMediaKey(), vid.GetFileSHA256(), vid.GetFileEncSHA256(), vid.GetFileLength()
	}

	if aud := msg.GetAudioMessage(); aud != nil {
		return "audio", "audio_" + timestamp + ".ogg",
			aud.GetURL(), aud.GetMediaKey(), aud.GetFileSHA256(), aud.GetFileEncSHA256(), aud.GetFileLength()
	}

	if doc := msg.GetDocumentMessage(); doc != nil {
		filename := doc.GetFileName()
		if filename == "" {
			filename = "document_" + timestamp
		}
		return "document", filename,
			doc.GetURL(), doc.GetMediaKey(), doc.GetFileSHA256(), doc.GetFileEncSHA256(), doc.GetFileLength()
	}

	return "", "", "", nil, nil, nil, 0
}

// extractFileExtension extracts and lowercases the file extension from a path.
// Returns empty string if no extension is found.
func extractFileExtension(path string) string {
	ext := filepath.Ext(path)
	if ext == "" {
		return ""
	}
	// filepath.Ext returns ".ext", we need "ext"
	return strings.ToLower(ext[1:])
}

// buildReactionMessage creates a reaction message for a given message
func buildReactionMessage(chatJID string, messageID string, senderJID types.JID, clientUserID string, emoji string) *waProto.Message {
	return &waProto.Message{
		ReactionMessage: &waProto.ReactionMessage{
			Key: &waProto.MessageKey{
				RemoteJID:   proto.String(chatJID),
				FromMe:      proto.Bool(senderJID.User == clientUserID),
				ID:          proto.String(messageID),
				Participant: proto.String(senderJID.String()),
			},
			Text:              proto.String(emoji),
			SenderTimestampMS: proto.Int64(time.Now().UnixMilli()),
		},
	}
}
