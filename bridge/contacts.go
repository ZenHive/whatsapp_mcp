package main

import (
	"context"
	"fmt"

	"go.mau.fi/whatsmeow"
	"go.mau.fi/whatsmeow/proto/waHistorySync"
	"go.mau.fi/whatsmeow/types"
	waLog "go.mau.fi/whatsmeow/util/log"
)

// GetChatName determines the appropriate name for a chat based on JID and other info
func GetChatName(ctx context.Context, client *whatsmeow.Client, messageStore *MessageStore, jid types.JID, chatJID string, conversation *waHistorySync.Conversation, sender string, logger waLog.Logger) string {
	// First, check if chat already exists in database with a name
	if existingName := getExistingChatName(messageStore, chatJID); existingName != "" {
		logger.Infof("Using existing chat name for %s: %s", chatJID, existingName)
		return existingName
	}

	// Determine name based on chat type
	if jid.Server == "g.us" {
		return getGroupChatName(ctx, client, jid, chatJID, conversation, logger)
	}
	return getContactChatName(ctx, client, messageStore, jid, chatJID, sender, logger)
}

// getExistingChatName checks if the chat already has a name in the database
func getExistingChatName(messageStore *MessageStore, chatJID string) string {
	return messageStore.GetChatName(chatJID)
}

// getGroupChatName determines the name for a group chat
func getGroupChatName(ctx context.Context, client *whatsmeow.Client, jid types.JID, chatJID string, conversation *waHistorySync.Conversation, logger waLog.Logger) string {
	logger.Infof("Getting name for group: %s", chatJID)

	// Try conversation data first (from history sync)
	if conversation != nil {
		if dn := conversation.GetDisplayName(); dn != "" {
			logger.Infof("Using group name from conversation: %s", dn)
			return dn
		}
		if n := conversation.GetName(); n != "" {
			logger.Infof("Using group name from conversation: %s", n)
			return n
		}
	}

	// Try group info from WhatsApp
	groupInfo, err := client.GetGroupInfo(ctx, jid)
	if err == nil && groupInfo.Name != "" {
		logger.Infof("Using group name from API: %s", groupInfo.Name)
		return groupInfo.Name
	}

	// Fallback name for groups
	fallback := fmt.Sprintf("Group %s", jid.User)
	logger.Infof("Using fallback group name: %s", fallback)
	return fallback
}

// getContactChatName determines the name for an individual contact
func getContactChatName(ctx context.Context, client *whatsmeow.Client, messageStore *MessageStore, jid types.JID, chatJID string, sender string, logger waLog.Logger) string {
	logger.Infof("Getting name for contact: %s", chatJID)

	// Try to get contact name from WhatsApp's contact store
	contact, err := client.Store.Contacts.GetContact(ctx, jid)
	if err == nil && contact.FullName != "" {
		// Cache the contact name for future lookups (especially useful for @lid contacts)
		cacheContactName(messageStore, chatJID, jid.User, contact.FullName, logger)
		logger.Infof("Using contact name: %s", contact.FullName)
		return contact.FullName
	}

	// Fallback to sender
	if sender != "" {
		logger.Infof("Using sender as name: %s", sender)
		return sender
	}

	// Last fallback to JID user
	logger.Infof("Using JID user as name: %s", jid.User)
	return jid.User
}

// cacheContactName stores the contact name in the contacts table for future lookups.
// Parameters:
//   - chatJID: The full JID string (e.g., "12345@s.whatsapp.net" or "12345@lid")
//   - phoneOrUser: The user portion of the JID (phone number or LID user ID)
//   - name: The display name to cache
func cacheContactName(messageStore *MessageStore, chatJID string, phoneOrUser string, name string, logger waLog.Logger) {
	// Only cache if we have a meaningful name (not just the phone number or JID user)
	if name == "" || name == phoneOrUser {
		return
	}

	err := messageStore.StoreContact(chatJID, phoneOrUser, name)
	if err != nil {
		logger.Warnf("Failed to cache contact name for %s: %v", chatJID, err)
	} else {
		logger.Infof("Cached contact name: %s -> %s", chatJID, name)
	}
}
