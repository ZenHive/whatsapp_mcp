package main

import (
	"database/sql"
	"sync"
	"time"

	"go.mau.fi/whatsmeow"
	waLog "go.mau.fi/whatsmeow/util/log"
)

// =============================================================================
// Core Types
// =============================================================================

// Message represents a chat message for our client
type Message struct {
	Time      time.Time
	Sender    string
	Content   string
	IsFromMe  bool
	MediaType string
	Filename  string
}

// MessageStore is the database handler for storing message history
type MessageStore struct {
	db *sql.DB
}

// ReconnectManager handles automatic reconnection with exponential backoff
type ReconnectManager struct {
	client         *whatsmeow.Client
	logger         waLog.Logger
	isReconnecting bool
	stopChan       chan struct{}
	mu             sync.Mutex
}

// =============================================================================
// Request Types
// =============================================================================

// SendMessageRequest represents the request body for the send message API
type SendMessageRequest struct {
	Recipient string `json:"recipient"`
	Message   string `json:"message"`
	MediaPath string `json:"media_path,omitempty"`
}

// DownloadMediaRequest represents the request body for the download media API
type DownloadMediaRequest struct {
	MessageID string `json:"message_id"`
	ChatJID   string `json:"chat_jid"`
}

// ResolveLidRequest represents the request body for resolving a LID to phone
type ResolveLidRequest struct {
	LID string `json:"lid"`
}

// TypingRequest represents the request body for sending typing indicators
type TypingRequest struct {
	Recipient string `json:"recipient"`
	Composing bool   `json:"composing"`
}

// MarkReadRequest represents the request body for marking messages as read
type MarkReadRequest struct {
	ChatJID    string   `json:"chat_jid"`
	MessageIDs []string `json:"message_ids"`
}

// ReactionRequest represents the request body for sending message reactions
type ReactionRequest struct {
	ChatJID   string `json:"chat_jid"`
	MessageID string `json:"message_id"`
	Sender    string `json:"sender"`
	Emoji     string `json:"emoji"`
}

// DeleteMessageRequest represents the request body for deleting messages
type DeleteMessageRequest struct {
	ChatJID   string `json:"chat_jid"`
	MessageID string `json:"message_id"`
	Sender    string `json:"sender"`
}

// ReplyMessageRequest represents the request body for replying to messages
type ReplyMessageRequest struct {
	Recipient       string `json:"recipient"`
	Message         string `json:"message"`
	QuotedMessageID string `json:"quoted_message_id"`
	QuotedChatJID   string `json:"quoted_chat_jid"`
	QuotedSender    string `json:"quoted_sender"` // JID of the person who sent the quoted message
}

// LocationRequest represents the request body for sending location messages
type LocationRequest struct {
	Recipient string  `json:"recipient"`
	Latitude  float64 `json:"latitude"`
	Longitude float64 `json:"longitude"`
	Name      string  `json:"name,omitempty"`    // Optional place name
	Address   string  `json:"address,omitempty"` // Optional address
}

// EditMessageRequest represents the request body for editing messages
type EditMessageRequest struct {
	ChatJID    string `json:"chat_jid"`
	MessageID  string `json:"message_id"`
	NewContent string `json:"new_content"`
}

// PresenceRequest represents the request body for setting online presence
type PresenceRequest struct {
	Available bool `json:"available"`
}

// SubscribePresenceRequest represents the request body for subscribing to presence updates
type SubscribePresenceRequest struct {
	JID string `json:"jid"`
}

// DisappearingTimerRequest represents the request body for setting disappearing messages timer
type DisappearingTimerRequest struct {
	ChatJID string `json:"chat_jid"`
	Timer   string `json:"timer"` // "off", "24h", "7d", "90d"
}

// IsOnWhatsAppRequest represents the request body for checking phone numbers
type IsOnWhatsAppRequest struct {
	Phones []string `json:"phones"` // Up to 50 phone numbers
}

// GetProfilePictureRequest represents the request body for getting profile pictures
type GetProfilePictureRequest struct {
	JID string `json:"jid"`
}

// UpdateBlocklistRequest represents the request body for blocking/unblocking contacts
type UpdateBlocklistRequest struct {
	JID    string `json:"jid"`
	Action string `json:"action"` // "block" or "unblock"
}

// CreatePollRequest represents the request body for creating a poll
type CreatePollRequest struct {
	Recipient     string   `json:"recipient"`
	Question      string   `json:"question"`
	Options       []string `json:"options"`
	MaxSelections int      `json:"max_selections"` // 1 for single-choice, 2+ for multi-choice
}

// GetGroupInfoRequest represents the request body for getting group info
type GetGroupInfoRequest struct {
	JID string `json:"jid"`
}

// MergeChatsRequest represents the request body for merging chats
type MergeChatsRequest struct {
	SourceJID string `json:"source_jid"`
	TargetJID string `json:"target_jid"`
}

// GetGroupInviteLinkRequest represents the request body for getting/resetting group invite link
type GetGroupInviteLinkRequest struct {
	JID   string `json:"jid"`
	Reset bool   `json:"reset,omitempty"` // If true, reset the invite link
}

// JoinGroupRequest represents the request body for joining a group via invite link
type JoinGroupRequest struct {
	InviteLink string `json:"invite_link"`
}

// CreateGroupRequest represents the request body for creating a new group
type CreateGroupRequest struct {
	Name         string   `json:"name"`         // Group name (max 25 characters)
	Participants []string `json:"participants"` // List of JIDs to add as initial members
}

// LeaveGroupRequest represents the request body for leaving a group
type LeaveGroupRequest struct {
	JID string `json:"jid"` // The group JID to leave
}

// UpdateGroupNameRequest represents the request body for updating group name
type UpdateGroupNameRequest struct {
	JID  string `json:"jid"`
	Name string `json:"name"` // Max 25 characters
}

// UpdateGroupDescriptionRequest represents the request body for updating group description
type UpdateGroupDescriptionRequest struct {
	JID         string `json:"jid"`
	Description string `json:"description"`
}

// UpdateGroupSettingsRequest represents the request body for updating group settings
type UpdateGroupSettingsRequest struct {
	JID      string `json:"jid"`
	Locked   *bool  `json:"locked,omitempty"`   // Only admins can edit group info
	Announce *bool  `json:"announce,omitempty"` // Only admins can send messages
}

// UpdateGroupParticipantsRequest represents the request body for managing group members
type UpdateGroupParticipantsRequest struct {
	JID          string   `json:"jid"`
	Participants []string `json:"participants"` // List of JIDs to modify
	Action       string   `json:"action"`       // "add", "remove", "promote", "demote"
}

// SetPrivacySettingRequest represents the request body for updating a privacy setting
type SetPrivacySettingRequest struct {
	Setting string `json:"setting"` // "groupadd", "last", "status", "profile", "readreceipts", "online", "calladd"
	Value   string `json:"value"`   // "all", "contacts", "contact_blacklist", "match_last_seen", "known", "none"
}

// GetBusinessProfileRequest represents the request body for getting business profile
type GetBusinessProfileRequest struct {
	JID string `json:"jid"`
}

// RejectCallRequest represents the request body for rejecting a call
type RejectCallRequest struct {
	CallFrom string `json:"call_from"` // The JID of the caller
	CallID   string `json:"call_id"`   // The call ID
}

// GetNewsletterInfoRequest represents the request body for getting newsletter info
type GetNewsletterInfoRequest struct {
	JID string `json:"jid"` // Newsletter JID (ends with @newsletter)
}

// GetNewsletterMessagesRequest represents the request body for getting newsletter messages
type GetNewsletterMessagesRequest struct {
	JID    string `json:"jid"`              // Newsletter JID
	Count  int    `json:"count,omitempty"`  // Number of messages to fetch (default: 50)
	Before int    `json:"before,omitempty"` // Server ID to fetch messages before (for pagination)
}

// FollowNewsletterRequest represents the request body for following/unfollowing a newsletter
type FollowNewsletterRequest struct {
	JID string `json:"jid"` // Newsletter JID
}

// =============================================================================
// Response Types
// =============================================================================

// APIResponse is a generic response type for simple success/error responses
type APIResponse struct {
	Success bool   `json:"success"`
	Message string `json:"message,omitempty"`
}

// SendMessageResponse represents the response for the send message API
type SendMessageResponse struct {
	Success bool   `json:"success"`
	Message string `json:"message"`
}

// HealthResponse represents the response for the health check API
type HealthResponse struct {
	Connected bool   `json:"connected"`
	Phone     string `json:"phone,omitempty"`
	Name      string `json:"name,omitempty"`
}

// DownloadMediaResponse represents the response for the download media API
type DownloadMediaResponse struct {
	Success  bool   `json:"success"`
	Message  string `json:"message"`
	Filename string `json:"filename,omitempty"`
	Path     string `json:"path,omitempty"`
}

// ResolveLidResponse represents the response for the resolve LID API
type ResolveLidResponse struct {
	Success bool   `json:"success"`
	Message string `json:"message,omitempty"`
	Phone   string `json:"phone,omitempty"`
	Name    string `json:"name,omitempty"`
}

// IsOnWhatsAppResponse represents the response for the is_on_whatsapp API
type IsOnWhatsAppResponse struct {
	Success bool                 `json:"success"`
	Results []IsOnWhatsAppResult `json:"results,omitempty"`
	Message string               `json:"message,omitempty"`
}

// IsOnWhatsAppResult represents the result for a single phone number check
type IsOnWhatsAppResult struct {
	Phone        string `json:"phone"`
	IsOnWhatsApp bool   `json:"is_on_whatsapp"`
	JID          string `json:"jid,omitempty"` // The WhatsApp JID if registered
}

// GetProfilePictureResponse represents the response for the profile picture API
type GetProfilePictureResponse struct {
	Success bool   `json:"success"`
	URL     string `json:"url,omitempty"`
	ID      string `json:"id,omitempty"` // Profile picture ID
	Message string `json:"message,omitempty"`
}

// BlocklistResponse represents the response for the blocklist API
type BlocklistResponse struct {
	Success   bool     `json:"success"`
	Blocklist []string `json:"blocklist,omitempty"` // List of blocked JIDs
	Message   string   `json:"message,omitempty"`
}

// MergeChatsResponse represents the response for merging chats
type MergeChatsResponse struct {
	Success       bool   `json:"success"`
	Message       string `json:"message,omitempty"`
	MessagesMoved int64  `json:"messages_moved,omitempty"`
}

// ListGroupsResponse represents the response for listing joined groups
type ListGroupsResponse struct {
	Success bool        `json:"success"`
	Groups  []GroupInfo `json:"groups,omitempty"`
	Message string      `json:"message,omitempty"`
}

// GetGroupInfoResponse represents the response for getting group info
type GetGroupInfoResponse struct {
	Success bool       `json:"success"`
	Group   *GroupInfo `json:"group,omitempty"`
	Message string     `json:"message,omitempty"`
}

// GetGroupInviteLinkResponse represents the response for getting group invite link
type GetGroupInviteLinkResponse struct {
	Success    bool   `json:"success"`
	InviteLink string `json:"invite_link,omitempty"`
	Message    string `json:"message,omitempty"`
}

// JoinGroupResponse represents the response for joining a group
type JoinGroupResponse struct {
	Success  bool   `json:"success"`
	GroupJID string `json:"group_jid,omitempty"`
	Message  string `json:"message,omitempty"`
}

// CreateGroupResponse represents the response for creating a group
type CreateGroupResponse struct {
	Success bool       `json:"success"`
	Group   *GroupInfo `json:"group,omitempty"`
	Message string     `json:"message,omitempty"`
}

// LeaveGroupResponse represents the response for leaving a group
type LeaveGroupResponse struct {
	Success bool   `json:"success"`
	Message string `json:"message,omitempty"`
}

// UpdateGroupParticipantsResponse represents the response for managing group members
type UpdateGroupParticipantsResponse struct {
	Success      bool                       `json:"success"`
	Message      string                     `json:"message,omitempty"`
	Participants []GroupParticipantResponse `json:"participants,omitempty"`
}

// GroupParticipantResponse represents a participant result in the response
type GroupParticipantResponse struct {
	JID       string `json:"jid"`
	ErrorCode int    `json:"error_code,omitempty"` // Error code if operation failed for this participant (0 = success)
}

// PrivacySettingsResponse represents the response for getting privacy settings
type PrivacySettingsResponse struct {
	Success      bool   `json:"success"`
	GroupAdd     string `json:"group_add,omitempty"`     // Who can add you to groups
	LastSeen     string `json:"last_seen,omitempty"`     // Who can see your last seen
	Status       string `json:"status,omitempty"`        // Who can see your status
	Profile      string `json:"profile,omitempty"`       // Who can see your profile photo
	ReadReceipts string `json:"read_receipts,omitempty"` // Whether read receipts are sent
	Online       string `json:"online,omitempty"`        // Who can see you online
	CallAdd      string `json:"call_add,omitempty"`      // Who can call you
	Message      string `json:"message,omitempty"`
}

// BusinessProfileResponse represents the response for getting a business profile
type BusinessProfileResponse struct {
	Success   bool       `json:"success"`
	Profile   *BizProfile `json:"profile,omitempty"`
	Message   string     `json:"message,omitempty"`
}

// BizProfile contains business profile information
type BizProfile struct {
	JID                   string              `json:"jid"`
	Address               string              `json:"address,omitempty"`
	Email                 string              `json:"email,omitempty"`
	Categories            []BizCategory       `json:"categories,omitempty"`
	BusinessHoursTimezone string              `json:"business_hours_timezone,omitempty"`
	BusinessHours         []BizHoursConfig    `json:"business_hours,omitempty"`
}

// BizCategory represents a business category
type BizCategory struct {
	ID   string `json:"id"`
	Name string `json:"name"`
}

// BizHoursConfig represents business operating hours
type BizHoursConfig struct {
	DayOfWeek string `json:"day_of_week"`
	Mode      string `json:"mode"`
	OpenTime  string `json:"open_time,omitempty"`
	CloseTime string `json:"close_time,omitempty"`
}

// ListContactsResponse represents the response for listing contacts
type ListContactsResponse struct {
	Success  bool           `json:"success"`
	Contacts []ContactEntry `json:"contacts,omitempty"`
	Total    int            `json:"total"`
	Message  string         `json:"message,omitempty"`
}

// ListNewslettersResponse represents the response for listing subscribed newsletters
type ListNewslettersResponse struct {
	Success     bool                 `json:"success"`
	Newsletters []NewsletterMetadata `json:"newsletters,omitempty"`
	Message     string               `json:"message,omitempty"`
}

// GetNewsletterInfoResponse represents the response for getting newsletter info
type GetNewsletterInfoResponse struct {
	Success    bool                `json:"success"`
	Newsletter *NewsletterMetadata `json:"newsletter,omitempty"`
	Message    string              `json:"message,omitempty"`
}

// GetNewsletterMessagesResponse represents the response for getting newsletter messages
type GetNewsletterMessagesResponse struct {
	Success  bool                `json:"success"`
	Messages []NewsletterMessage `json:"messages,omitempty"`
	Message  string              `json:"message,omitempty"`
}

// =============================================================================
// Domain Types
// =============================================================================

// GroupInfo represents group information in API responses
type GroupInfo struct {
	JID              string        `json:"jid"`
	Name             string        `json:"name"`
	Topic            string        `json:"topic,omitempty"`
	TopicSetAt       string        `json:"topic_set_at,omitempty"`
	TopicSetBy       string        `json:"topic_set_by,omitempty"`
	OwnerJID         string        `json:"owner_jid,omitempty"`
	CreatedAt        string        `json:"created_at,omitempty"`
	ParticipantCount int           `json:"participant_count"`
	Participants     []GroupMember `json:"participants,omitempty"`
	IsAnnounce       bool          `json:"is_announce"` // Only admins can send messages
	IsLocked         bool          `json:"is_locked"`   // Only admins can edit group info
}

// GroupMember represents a group participant
type GroupMember struct {
	JID          string `json:"jid"`
	IsAdmin      bool   `json:"is_admin"`
	IsSuperAdmin bool   `json:"is_super_admin"`
}

// ContactEntry represents a contact from the WhatsApp contacts store
type ContactEntry struct {
	JID           string `json:"jid"`
	FirstName     string `json:"first_name,omitempty"`
	FullName      string `json:"full_name,omitempty"`
	PushName      string `json:"push_name,omitempty"`
	BusinessName  string `json:"business_name,omitempty"`
	RedactedPhone string `json:"redacted_phone,omitempty"`
}

// NewsletterMetadata represents WhatsApp channel/newsletter information
type NewsletterMetadata struct {
	ID              string `json:"id"`
	Name            string `json:"name"`
	Description     string `json:"description,omitempty"`
	SubscriberCount int64  `json:"subscriber_count,omitempty"`
	InviteLink      string `json:"invite_link,omitempty"`
	CreatedAt       string `json:"created_at,omitempty"`
	IsMuted         bool   `json:"is_muted,omitempty"`
}

// NewsletterMessage represents a message in a WhatsApp channel
type NewsletterMessage struct {
	ServerID   int    `json:"server_id"`
	Text       string `json:"text,omitempty"`
	Timestamp  string `json:"timestamp"`
	ViewCount  int    `json:"view_count,omitempty"`
	MediaType  string `json:"media_type,omitempty"`
}

// MediaDownloader implements the whatsmeow.DownloadableMessage interface
type MediaDownloader struct {
	URL           string
	DirectPath    string
	MediaKey      []byte
	FileLength    uint64
	FileSHA256    []byte
	FileEncSHA256 []byte
	MediaType     whatsmeow.MediaType
}
