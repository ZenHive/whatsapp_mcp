package main

import (
	"context"
	"fmt"
	"time"

	"go.mau.fi/whatsmeow"
	"go.mau.fi/whatsmeow/types"
	"go.mau.fi/whatsmeow/types/events"
	waLog "go.mau.fi/whatsmeow/util/log"
)

// handleMessage handles regular incoming messages with media support
func handleMessage(ctx context.Context, client *whatsmeow.Client, messageStore *MessageStore, msg *events.Message, logger waLog.Logger) {
	chatJID := msg.Info.Chat.String()
	sender := msg.Info.Sender.User

	// Get appropriate chat name (pass nil for conversation since we don't have one for regular messages)
	name := GetChatName(ctx, client, messageStore, msg.Info.Chat, chatJID, nil, sender, logger)

	// Update chat in database with the message timestamp (stored in UTC for portability)
	err := messageStore.StoreChat(chatJID, name, msg.Info.Timestamp.UTC())
	if err != nil {
		logger.Warnf("Failed to store chat: %v", err)
	}

	// Extract text content
	content := extractTextContent(msg.Message)

	// Extract media info
	mediaType, filename, url, mediaKey, fileSHA256, fileEncSHA256, fileLength := extractMediaInfo(msg.Message)

	// Skip if there's no content and no media
	if content == "" && mediaType == "" {
		return
	}

	// Store message in database (timestamp in UTC for portability)
	err = messageStore.StoreMessage(
		msg.Info.ID,
		chatJID,
		sender,
		content,
		msg.Info.Timestamp.UTC(),
		msg.Info.IsFromMe,
		mediaType,
		filename,
		url,
		mediaKey,
		fileSHA256,
		fileEncSHA256,
		fileLength,
	)

	if err != nil {
		logger.Warnf("Failed to store message: %v", err)
	} else {
		// Log message reception
		timestamp := msg.Info.Timestamp.Format("2006-01-02 15:04:05")
		direction := "←"
		if msg.Info.IsFromMe {
			direction = "→"
		}

		// Log message reception (without content for privacy)
		if mediaType != "" {
			fmt.Printf("[%s] %s %s: [%s]\n", timestamp, direction, sender, mediaType)
		} else {
			fmt.Printf("[%s] %s %s: [text]\n", timestamp, direction, sender)
		}
	}
}

// determineSender extracts the sender from a history sync message with cross-validation.
// Priority: WebMessageInfo.Participant > Key.Participant > derive from FromMe flag.
func determineSender(participant *string, keyParticipant *string, isFromMe bool, clientUserID string, fallbackUser string) (sender string, correctedIsFromMe bool) {
	correctedIsFromMe = isFromMe

	// Try WebMessageInfo.Participant first (most reliable)
	if participant != nil && *participant != "" {
		if participantJID, err := types.ParseJID(*participant); err == nil {
			sender = participantJID.User
			correctedIsFromMe = (sender == clientUserID)
		} else {
			sender = *participant
		}
		return
	}

	// Try Key.Participant (typically used for group chats)
	if keyParticipant != nil && *keyParticipant != "" {
		if participantJID, err := types.ParseJID(*keyParticipant); err == nil {
			sender = participantJID.User
			correctedIsFromMe = (sender == clientUserID)
		} else {
			sender = *keyParticipant
		}
		return
	}

	// Fallback: trust FromMe flag or use chat partner
	if isFromMe {
		sender = clientUserID
	} else {
		sender = fallbackUser
	}
	return
}

// handleHistorySync handles history sync events from WhatsApp
func handleHistorySync(ctx context.Context, client *whatsmeow.Client, messageStore *MessageStore, historySync *events.HistorySync, logger waLog.Logger) {
	// Log sync metadata for debugging
	syncType := historySync.Data.GetSyncType().String()
	progress := historySync.Data.GetProgress()
	chunkOrder := historySync.Data.GetChunkOrder()
	numConversations := len(historySync.Data.Conversations)
	numLidMappings := len(historySync.Data.PhoneNumberToLidMappings)

	fmt.Printf("📥 History sync: type=%s, progress=%d%%, chunk=%d, conversations=%d, LID mappings=%d\n",
		syncType, progress, chunkOrder, numConversations, numLidMappings)

	// Store LID → phone mappings if present (helps with contact resolution)
	if numLidMappings > 0 {
		storedMappings := 0
		for _, mapping := range historySync.Data.PhoneNumberToLidMappings {
			if mapping.PnJID != nil && mapping.LidJID != nil {
				phone := *mapping.PnJID
				lid := *mapping.LidJID
				if err := messageStore.StoreLIDMapping(lid, phone); err != nil {
					logger.Warnf("Failed to store LID mapping: %v", err)
				} else {
					storedMappings++
				}
			}
		}
		if storedMappings > 0 {
			fmt.Printf("💾 Stored %d LID→phone mappings\n", storedMappings)
		}
	}

	syncedCount := 0
	clientUserID := client.Store.ID.User

	for _, conversation := range historySync.Data.Conversations {
		if conversation.ID == nil {
			continue
		}
		chatJID := *conversation.ID

		jid, err := types.ParseJID(chatJID)
		if err != nil {
			logger.Warnf("Failed to parse JID %s: %v", chatJID, err)
			continue
		}

		name := GetChatName(ctx, client, messageStore, jid, chatJID, conversation, "", logger)

		messages := conversation.Messages
		if len(messages) == 0 {
			continue
		}

		// Update chat with latest message timestamp
		latestMsg := messages[0]
		if latestMsg == nil || latestMsg.Message == nil {
			continue
		}
		if ts := latestMsg.Message.GetMessageTimestamp(); ts != 0 {
			messageStore.StoreChat(chatJID, name, time.Unix(int64(ts), 0).UTC())
		}

		// Process and store each message
		for _, msg := range messages {
			if msg == nil || msg.Message == nil || msg.Message.Message == nil {
				continue
			}

			// Extract content and media info
			content := extractTextContent(msg.Message.Message)
			mediaType, filename, url, mediaKey, fileSHA256, fileEncSHA256, fileLength := extractMediaInfo(msg.Message.Message)

			// Skip messages with no content and no media
			if content == "" && mediaType == "" {
				continue
			}

			// Determine sender with cross-validation
			isFromMe := msg.Message.Key != nil && msg.Message.Key.FromMe != nil && *msg.Message.Key.FromMe
			var keyParticipant *string
			if msg.Message.Key != nil {
				keyParticipant = msg.Message.Key.Participant
			}
			sender, isFromMe := determineSender(msg.Message.Participant, keyParticipant, isFromMe, clientUserID, jid.User)

			// Get message ID and timestamp
			msgID := ""
			if msg.Message.Key != nil && msg.Message.Key.ID != nil {
				msgID = *msg.Message.Key.ID
			}
			ts := msg.Message.GetMessageTimestamp()
			if ts == 0 {
				continue
			}
			timestamp := time.Unix(int64(ts), 0).UTC()

			err = messageStore.StoreMessage(
				msgID, chatJID, sender, content, timestamp, isFromMe,
				mediaType, filename, url, mediaKey, fileSHA256, fileEncSHA256, fileLength,
			)
			if err != nil {
				logger.Warnf("Failed to store history message: %v", err)
				continue
			}
			syncedCount++
		}
	}

	fmt.Printf("✅ History sync (%s) complete: stored %d messages from %d conversations\n", syncType, syncedCount, numConversations)
}
