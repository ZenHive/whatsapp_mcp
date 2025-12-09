package main

import (
	"context"
	"fmt"
	"net/http"
	"strings"
	"time"

	"go.mau.fi/whatsmeow"
	"go.mau.fi/whatsmeow/types"

	waProto "go.mau.fi/whatsmeow/binary/proto"
	"google.golang.org/protobuf/proto"
)

// convertNewsletterMetadata converts a whatsmeow newsletter to our API format
func convertNewsletterMetadata(nl *types.NewsletterMetadata) NewsletterMetadata {
	meta := NewsletterMetadata{
		ID:              nl.ID.String(),
		Name:            nl.ThreadMeta.Name.Text,
		Description:     nl.ThreadMeta.Description.Text,
		SubscriberCount: int64(nl.ThreadMeta.SubscriberCount),
	}
	if nl.ThreadMeta.InviteCode != "" {
		meta.InviteLink = "https://whatsapp.com/channel/" + nl.ThreadMeta.InviteCode
	}
	if !nl.ThreadMeta.CreationTime.IsZero() {
		meta.CreatedAt = nl.ThreadMeta.CreationTime.Format("2006-01-02T15:04:05Z")
	}
	if nl.ViewerMeta != nil {
		meta.IsMuted = nl.ViewerMeta.Mute == "on"
	}
	return meta
}

// handleHealth checks WhatsApp connection status
func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	response := HealthResponse{Connected: s.client.IsConnected()}

	if s.client.Store.ID != nil {
		response.Phone = s.client.Store.ID.User
		response.Name = s.client.Store.PushName
	}

	_ = writeJSON(w, response)
}

// handleSend sends a WhatsApp message
func (s *Server) handleSend(w http.ResponseWriter, r *http.Request) {
	if !requirePOST(w, r) {
		return
	}

	var req SendMessageRequest
	if !decodeJSON(w, r, &req) {
		return
	}

	if !requireField(w, req.Recipient, "recipient") {
		return
	}

	if req.Message == "" && req.MediaPath == "" {
		writeJSONError(w, http.StatusBadRequest, "message or media_path is required")
		return
	}

	s.logger.Infof("Received request to send message to %s", req.Recipient)

	success, message := sendWhatsAppMessage(r.Context(), s.client, req.Recipient, req.Message, req.MediaPath, s.logger)
	s.logger.Infof("Message sent: success=%t message=%s", success, message)

	if !success {
		writeJSONError(w, http.StatusInternalServerError, message)
		return
	}

	writeJSONSuccess(w, message)
}

// handleDownload downloads media from a message
func (s *Server) handleDownload(w http.ResponseWriter, r *http.Request) {
	if !requirePOST(w, r) {
		return
	}

	var req DownloadMediaRequest
	if !decodeJSON(w, r, &req) {
		return
	}

	if !requireField(w, req.MessageID, "message_id") || !requireField(w, req.ChatJID, "chat_jid") {
		return
	}

	success, mediaType, filename, path, err := downloadMedia(r.Context(), s.client, s.store, req.MessageID, req.ChatJID, s.logger)

	if !success || err != nil {
		errMsg := "Unknown error"
		if err != nil {
			errMsg = err.Error()
		}
		writeJSONError(w, http.StatusInternalServerError, fmt.Sprintf("Failed to download media: %s", errMsg))
		return
	}

	_ = writeJSON(w, DownloadMediaResponse{
		Success:  true,
		Message:  fmt.Sprintf("Successfully downloaded %s media", mediaType),
		Filename: filename,
		Path:     path,
	})
}

// handleResolveLid resolves a LID to phone number
func (s *Server) handleResolveLid(w http.ResponseWriter, r *http.Request) {
	if !requirePOST(w, r) {
		return
	}

	var req ResolveLidRequest
	if !decodeJSON(w, r, &req) || !requireField(w, req.LID, "lid") {
		return
	}

	// Check cache first
	if phone, name, found := s.store.GetContact(req.LID); found {
		writeResolveLidResponse(w, phone, name)
		return
	}

	// Parse and fetch user info
	jid, err := types.ParseJID(req.LID)
	if err != nil {
		writeJSONError(w, http.StatusBadRequest, fmt.Sprintf("Invalid JID format: %v", err))
		return
	}

	userInfos, err := s.client.GetUserInfo(context.Background(), []types.JID{jid})
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, fmt.Sprintf("Failed to get user info: %v", err))
		return
	}

	userInfo, ok := userInfos[jid]
	if !ok {
		writeJSONError(w, http.StatusNotFound, "No user info found for this LID")
		return
	}

	// Extract phone and name
	phone := extractPhoneFromUserInfo(userInfo, jid)
	name := s.getContactName(jid)

	// Cache if we found a phone
	if phone != "" {
		if err := s.store.StoreContact(req.LID, phone, name); err != nil {
			s.logger.Warnf("Failed to cache contact: %v", err)
		}
	}

	writeResolveLidResponse(w, phone, name)
}

// extractPhoneFromUserInfo extracts phone number from WhatsApp UserInfo.
// Tries devices first, then JID user field, then LID field.
func extractPhoneFromUserInfo(userInfo types.UserInfo, jid types.JID) string {
	// Check devices for phone JID
	for _, deviceJID := range userInfo.Devices {
		if deviceJID.Device > 0 {
			continue
		}
		if deviceJID.User != "" && !strings.Contains(deviceJID.User, ":") {
			return deviceJID.User
		}
	}

	// Try main JID user field
	if jid.User != "" && !strings.Contains(jid.User, ":") {
		return jid.User
	}

	// Try LID field from UserInfo
	if !userInfo.LID.IsEmpty() && userInfo.LID.User != "" {
		return userInfo.LID.User
	}

	return ""
}

// getContactName retrieves the contact's full name from the store.
func (s *Server) getContactName(jid types.JID) string {
	contact, err := s.client.Store.Contacts.GetContact(context.Background(), jid)
	if err == nil && contact.FullName != "" {
		return contact.FullName
	}
	return ""
}

// writeResolveLidResponse writes the LID resolution response.
func writeResolveLidResponse(w http.ResponseWriter, phone, name string) {
	response := ResolveLidResponse{
		Success: phone != "",
		Phone:   phone,
		Name:    name,
	}
	if phone == "" {
		response.Message = "Could not resolve phone number from LID"
	}
	_ = writeJSON(w, response)
}

// handleTyping sends typing indicators
func (s *Server) handleTyping(w http.ResponseWriter, r *http.Request) {
	if !requirePOST(w, r) {
		return
	}

	var req TypingRequest
	if !decodeJSON(w, r, &req) {
		return
	}

	if !requireField(w, req.Recipient, "recipient") {
		return
	}

	recipientJID, err := parseRecipientJID(req.Recipient)
	if err != nil {
		writeJSONError(w, http.StatusBadRequest, fmt.Sprintf("Invalid JID format: %v", err))
		return
	}

	presence := types.ChatPresencePaused
	if req.Composing {
		presence = types.ChatPresenceComposing
	}

	if err := s.client.SendChatPresence(context.Background(), recipientJID, presence, types.ChatPresenceMediaText); err != nil {
		writeJSONError(w, http.StatusInternalServerError, fmt.Sprintf("Failed to send typing indicator: %v", err))
		return
	}

	action := "started"
	if !req.Composing {
		action = "stopped"
	}
	writeJSONSuccess(w, fmt.Sprintf("Typing indicator %s for %s", action, req.Recipient))
}

// handleMarkRead marks messages as read
func (s *Server) handleMarkRead(w http.ResponseWriter, r *http.Request) {
	if !requirePOST(w, r) {
		return
	}

	var req MarkReadRequest
	if !decodeJSON(w, r, &req) {
		return
	}

	if !requireField(w, req.ChatJID, "chat_jid") {
		return
	}
	if len(req.MessageIDs) == 0 {
		writeJSONError(w, http.StatusBadRequest, "message_ids is required")
		return
	}

	chatJID, ok := parseJIDField(w, req.ChatJID, "chat_jid")
	if !ok {
		return
	}

	messageIDs := make([]types.MessageID, len(req.MessageIDs))
	for i, id := range req.MessageIDs {
		messageIDs[i] = types.MessageID(id)
	}

	if err := s.client.MarkRead(context.Background(), messageIDs, time.Now(), chatJID, chatJID); err != nil {
		writeJSONError(w, http.StatusInternalServerError, fmt.Sprintf("Failed to mark messages as read: %v", err))
		return
	}

	writeJSONSuccess(w, fmt.Sprintf("Marked %d message(s) as read in %s", len(req.MessageIDs), req.ChatJID))
}

// handleReaction sends message reactions
func (s *Server) handleReaction(w http.ResponseWriter, r *http.Request) {
	if !requirePOST(w, r) {
		return
	}

	var req ReactionRequest
	if !decodeJSON(w, r, &req) {
		return
	}

	if !requireField(w, req.ChatJID, "chat_jid") || !requireField(w, req.MessageID, "message_id") || !requireField(w, req.Sender, "sender") {
		return
	}

	chatJID, ok := parseJIDField(w, req.ChatJID, "chat_jid")
	if !ok {
		return
	}
	senderJID, ok := parseJIDField(w, req.Sender, "sender")
	if !ok {
		return
	}

	reactionMsg := buildReactionMessage(req.ChatJID, req.MessageID, senderJID, s.client.Store.ID.User, req.Emoji)

	if _, err := s.client.SendMessage(context.Background(), chatJID, reactionMsg); err != nil {
		writeJSONError(w, http.StatusInternalServerError, fmt.Sprintf("Failed to send reaction: %v", err))
		return
	}

	action := "added"
	if req.Emoji == "" {
		action = "removed"
	}
	writeJSONSuccess(w, fmt.Sprintf("Reaction %s for message %s", action, req.MessageID))
}

// handleDelete deletes messages
func (s *Server) handleDelete(w http.ResponseWriter, r *http.Request) {
	if !requirePOST(w, r) {
		return
	}

	var req DeleteMessageRequest
	if !decodeJSON(w, r, &req) {
		return
	}

	if !requireField(w, req.ChatJID, "chat_jid") || !requireField(w, req.MessageID, "message_id") || !requireField(w, req.Sender, "sender") {
		return
	}

	chatJID, ok := parseJIDField(w, req.ChatJID, "chat_jid")
	if !ok {
		return
	}
	senderJID, ok := parseJIDField(w, req.Sender, "sender")
	if !ok {
		return
	}

	revokerJID := types.EmptyJID
	if senderJID.User != s.client.Store.ID.User {
		revokerJID = senderJID
	}
	revokeMsg := s.client.BuildRevoke(chatJID, revokerJID, types.MessageID(req.MessageID))

	if _, err := s.client.SendMessage(context.Background(), chatJID, revokeMsg); err != nil {
		writeJSONError(w, http.StatusInternalServerError, fmt.Sprintf("Failed to delete message: %v", err))
		return
	}

	writeJSONSuccess(w, fmt.Sprintf("Message %s deleted from %s", req.MessageID, req.ChatJID))
}

// handleReply replies to a message
func (s *Server) handleReply(w http.ResponseWriter, r *http.Request) {
	if !requirePOST(w, r) {
		return
	}

	var req ReplyMessageRequest
	if !decodeJSON(w, r, &req) {
		return
	}

	if !requireField(w, req.Recipient, "recipient") ||
		!requireField(w, req.Message, "message") ||
		!requireField(w, req.QuotedMessageID, "quoted_message_id") ||
		!requireField(w, req.QuotedChatJID, "quoted_chat_jid") ||
		!requireField(w, req.QuotedSender, "quoted_sender") {
		return
	}

	recipientJID, err := parseRecipientJID(req.Recipient)
	if err != nil {
		writeJSONError(w, http.StatusBadRequest, fmt.Sprintf("Invalid recipient JID format: %v", err))
		return
	}

	replyMsg := &waProto.Message{
		ExtendedTextMessage: &waProto.ExtendedTextMessage{
			Text: proto.String(req.Message),
			ContextInfo: &waProto.ContextInfo{
				StanzaID:      proto.String(req.QuotedMessageID),
				Participant:   proto.String(req.QuotedSender),
				QuotedMessage: &waProto.Message{Conversation: proto.String("")},
			},
		},
	}

	if _, err := s.client.SendMessage(context.Background(), recipientJID, replyMsg); err != nil {
		writeJSONError(w, http.StatusInternalServerError, fmt.Sprintf("Failed to send reply: %v", err))
		return
	}

	writeJSONSuccess(w, fmt.Sprintf("Reply sent to %s", req.Recipient))
}

// handleEdit edits a message
func (s *Server) handleEdit(w http.ResponseWriter, r *http.Request) {
	if !requirePOST(w, r) {
		return
	}

	var req EditMessageRequest
	if !decodeJSON(w, r, &req) {
		return
	}

	if !requireField(w, req.ChatJID, "chat_jid") ||
		!requireField(w, req.MessageID, "message_id") ||
		!requireField(w, req.NewContent, "new_content") {
		return
	}

	chatJID, ok := parseJIDField(w, req.ChatJID, "chat_jid")
	if !ok {
		return
	}

	newMessage := &waProto.Message{
		Conversation: proto.String(req.NewContent),
	}
	editMsg := s.client.BuildEdit(chatJID, types.MessageID(req.MessageID), newMessage)

	if _, err := s.client.SendMessage(context.Background(), chatJID, editMsg); err != nil {
		writeJSONError(w, http.StatusInternalServerError, fmt.Sprintf("Failed to edit message: %v", err))
		return
	}

	writeJSONSuccess(w, fmt.Sprintf("Message %s edited in %s", req.MessageID, req.ChatJID))
}

// handleLocation sends a location message
func (s *Server) handleLocation(w http.ResponseWriter, r *http.Request) {
	if !requirePOST(w, r) {
		return
	}

	var req LocationRequest
	if !decodeJSON(w, r, &req) {
		return
	}

	if !requireField(w, req.Recipient, "recipient") {
		return
	}

	if req.Latitude < -90 || req.Latitude > 90 {
		writeJSONError(w, http.StatusBadRequest, "latitude must be between -90 and 90")
		return
	}
	if req.Longitude < -180 || req.Longitude > 180 {
		writeJSONError(w, http.StatusBadRequest, "longitude must be between -180 and 180")
		return
	}

	recipientJID, err := parseRecipientJID(req.Recipient)
	if err != nil {
		writeJSONError(w, http.StatusBadRequest, fmt.Sprintf("Invalid recipient JID format: %v", err))
		return
	}

	locationMsg := &waProto.Message{
		LocationMessage: &waProto.LocationMessage{
			DegreesLatitude:  proto.Float64(req.Latitude),
			DegreesLongitude: proto.Float64(req.Longitude),
		},
	}

	if req.Name != "" {
		locationMsg.LocationMessage.Name = proto.String(req.Name)
	}
	if req.Address != "" {
		locationMsg.LocationMessage.Address = proto.String(req.Address)
	}

	if _, err := s.client.SendMessage(context.Background(), recipientJID, locationMsg); err != nil {
		writeJSONError(w, http.StatusInternalServerError, fmt.Sprintf("Failed to send location: %v", err))
		return
	}

	writeJSONSuccess(w, fmt.Sprintf("Location sent to %s", req.Recipient))
}

// handlePresence sets online presence
func (s *Server) handlePresence(w http.ResponseWriter, r *http.Request) {
	if !requirePOST(w, r) {
		return
	}

	var req PresenceRequest
	if !decodeJSON(w, r, &req) {
		return
	}

	presence := types.PresenceUnavailable
	if req.Available {
		presence = types.PresenceAvailable
	}

	if err := s.client.SendPresence(context.Background(), presence); err != nil {
		writeJSONError(w, http.StatusInternalServerError, fmt.Sprintf("Failed to set presence: %v", err))
		return
	}

	status := "unavailable"
	if req.Available {
		status = "available"
	}
	writeJSONSuccess(w, fmt.Sprintf("Presence set to %s", status))
}

// handleSubscribePresence subscribes to presence updates
func (s *Server) handleSubscribePresence(w http.ResponseWriter, r *http.Request) {
	if !requirePOST(w, r) {
		return
	}

	var req SubscribePresenceRequest
	if !decodeJSON(w, r, &req) {
		return
	}

	if !requireField(w, req.JID, "jid") {
		return
	}

	jid, err := types.ParseJID(req.JID)
	if err != nil {
		writeJSONError(w, http.StatusBadRequest, fmt.Sprintf("Invalid JID format: %v", err))
		return
	}

	if err := s.client.SubscribePresence(context.Background(), jid); err != nil {
		writeJSONError(w, http.StatusInternalServerError, fmt.Sprintf("Failed to subscribe to presence: %v", err))
		return
	}

	writeJSONSuccess(w, fmt.Sprintf("Subscribed to presence updates for %s", req.JID))
}

// handleDisappearing sets disappearing messages timer
func (s *Server) handleDisappearing(w http.ResponseWriter, r *http.Request) {
	if !requirePOST(w, r) {
		return
	}

	var req DisappearingTimerRequest
	if !decodeJSON(w, r, &req) {
		return
	}

	if !requireField(w, req.ChatJID, "chat_jid") || !requireField(w, req.Timer, "timer") {
		return
	}

	chatJID, ok := parseJIDField(w, req.ChatJID, "chat_jid")
	if !ok {
		return
	}

	var timer time.Duration
	switch req.Timer {
	case "off":
		timer = 0
	case "24h":
		timer = 24 * time.Hour
	case "7d":
		timer = 7 * 24 * time.Hour
	case "90d":
		timer = 90 * 24 * time.Hour
	default:
		writeJSONError(w, http.StatusBadRequest, "timer must be one of: off, 24h, 7d, 90d")
		return
	}

	if err := s.client.SetDisappearingTimer(context.Background(), chatJID, timer, time.Now()); err != nil {
		writeJSONError(w, http.StatusInternalServerError, fmt.Sprintf("Failed to set disappearing timer: %v", err))
		return
	}

	writeJSONSuccess(w, fmt.Sprintf("Disappearing messages set to %s for %s", req.Timer, req.ChatJID))
}

// handleIsOnWhatsApp checks if phone numbers are on WhatsApp
func (s *Server) handleIsOnWhatsApp(w http.ResponseWriter, r *http.Request) {
	if !requirePOST(w, r) {
		return
	}

	var req IsOnWhatsAppRequest
	if !decodeJSON(w, r, &req) {
		return
	}

	if len(req.Phones) == 0 {
		writeJSONError(w, http.StatusBadRequest, "phones array is required and cannot be empty")
		return
	}

	if len(req.Phones) > 50 {
		writeJSONError(w, http.StatusBadRequest, "maximum 50 phone numbers allowed per request")
		return
	}

	results, err := s.client.IsOnWhatsApp(context.Background(), req.Phones)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, fmt.Sprintf("Failed to check phone numbers: %v", err))
		return
	}

	resultMap := make(map[string]types.IsOnWhatsAppResponse)
	for _, result := range results {
		resultMap[result.Query] = result
	}

	response := IsOnWhatsAppResponse{
		Success: true,
		Results: make([]IsOnWhatsAppResult, len(req.Phones)),
	}

	for i, phone := range req.Phones {
		if result, found := resultMap[phone]; found {
			response.Results[i] = IsOnWhatsAppResult{
				Phone:        phone,
				IsOnWhatsApp: result.IsIn,
				JID:          result.JID.String(),
			}
		} else {
			response.Results[i] = IsOnWhatsAppResult{
				Phone:        phone,
				IsOnWhatsApp: false,
				JID:          "",
			}
		}
	}

	_ = writeJSON(w, response)
}

// handleProfilePicture gets profile picture
func (s *Server) handleProfilePicture(w http.ResponseWriter, r *http.Request) {
	if !requirePOST(w, r) {
		return
	}

	var req GetProfilePictureRequest
	if !decodeJSON(w, r, &req) {
		return
	}

	if !requireField(w, req.JID, "jid") {
		return
	}

	jid, err := types.ParseJID(req.JID)
	if err != nil {
		writeJSONError(w, http.StatusBadRequest, fmt.Sprintf("Invalid JID format: %v", err))
		return
	}

	picInfo, err := s.client.GetProfilePictureInfo(context.Background(), jid, nil)
	if err != nil {
		if strings.Contains(err.Error(), "item-not-found") || strings.Contains(err.Error(), "404") {
			_ = writeJSON(w, GetProfilePictureResponse{
				Success: false,
				Message: "No profile picture set for this contact",
			})
			return
		}
		writeJSONError(w, http.StatusInternalServerError, fmt.Sprintf("Failed to get profile picture: %v", err))
		return
	}

	_ = writeJSON(w, GetProfilePictureResponse{
		Success: true,
		URL:     picInfo.URL,
		ID:      picInfo.ID,
	})
}

// handleBlocklist gets the blocklist
func (s *Server) handleBlocklist(w http.ResponseWriter, r *http.Request) {
	if !requireGET(w, r) {
		return
	}

	blocklist, err := s.client.GetBlocklist(context.Background())
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, fmt.Sprintf("Failed to get blocklist: %v", err))
		return
	}

	jids := make([]string, len(blocklist.JIDs))
	for i, jid := range blocklist.JIDs {
		jids[i] = jid.String()
	}

	_ = writeJSON(w, BlocklistResponse{
		Success:   true,
		Blocklist: jids,
	})
}

// handleBlock blocks/unblocks contacts
func (s *Server) handleBlock(w http.ResponseWriter, r *http.Request) {
	if !requirePOST(w, r) {
		return
	}

	var req UpdateBlocklistRequest
	if !decodeJSON(w, r, &req) {
		return
	}

	if !requireField(w, req.JID, "jid") || !requireField(w, req.Action, "action") {
		return
	}

	jid, ok := parseJIDField(w, req.JID, "jid")
	if !ok {
		return
	}

	action, valid := parseBlocklistAction(req.Action)
	if !valid {
		writeJSONError(w, http.StatusBadRequest, "action must be 'block' or 'unblock'")
		return
	}

	_, err := s.client.UpdateBlocklist(context.Background(), jid, action)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, fmt.Sprintf("Failed to %s contact: %v", req.Action, err))
		return
	}

	verb := "blocked"
	if req.Action == "unblock" {
		verb = "unblocked"
	}
	writeJSONSuccess(w, fmt.Sprintf("Contact %s %s", req.JID, verb))
}

// handleContacts lists contacts from WhatsApp contacts store
func (s *Server) handleContacts(w http.ResponseWriter, r *http.Request) {
	if !requireGET(w, r) {
		return
	}

	query := r.URL.Query()
	limit := parseIntParam(query.Get("limit"), 100, 1, 1000)
	offset := parseIntParam(query.Get("offset"), 0, 0, -1)
	nameFilter := query.Get("query")

	allContacts, err := s.client.Store.Contacts.GetAllContacts(context.Background())
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, fmt.Sprintf("Failed to get contacts: %v", err))
		return
	}

	contacts, total := filterAndPaginateContacts(allContacts, nameFilter, offset, limit)

	_ = writeJSON(w, ListContactsResponse{
		Success:  true,
		Contacts: contacts,
		Total:    total,
	})
}

// handlePoll creates and sends a poll
func (s *Server) handlePoll(w http.ResponseWriter, r *http.Request) {
	if !requirePOST(w, r) {
		return
	}

	var req CreatePollRequest
	if !decodeJSON(w, r, &req) {
		return
	}

	if !requireField(w, req.Recipient, "recipient") {
		return
	}
	if !requireField(w, req.Question, "question") {
		return
	}

	if len(req.Options) < MinPollOptions {
		writeJSONError(w, http.StatusBadRequest, fmt.Sprintf("at least %d options are required", MinPollOptions))
		return
	}
	if len(req.Options) > MaxPollOptions {
		writeJSONError(w, http.StatusBadRequest, fmt.Sprintf("maximum %d options allowed", MaxPollOptions))
		return
	}

	maxSelections := req.MaxSelections
	if maxSelections < 1 {
		maxSelections = 1
	}
	if maxSelections > len(req.Options) {
		maxSelections = len(req.Options)
	}

	recipientJID, err := parseRecipientJID(req.Recipient)
	if err != nil {
		writeJSONError(w, http.StatusBadRequest, fmt.Sprintf("Invalid recipient JID format: %v", err))
		return
	}

	pollMsg := s.client.BuildPollCreation(req.Question, req.Options, maxSelections)

	if _, err := s.client.SendMessage(context.Background(), recipientJID, pollMsg); err != nil {
		writeJSONError(w, http.StatusInternalServerError, fmt.Sprintf("Failed to send poll: %v", err))
		return
	}

	choiceType := "single-choice"
	if maxSelections > 1 {
		choiceType = fmt.Sprintf("multi-choice (up to %d)", maxSelections)
	}
	writeJSONSuccess(w, fmt.Sprintf("Poll sent to %s (%s with %d options)", req.Recipient, choiceType, len(req.Options)))
}

// handleMergeChats merges messages from source to target chat
func (s *Server) handleMergeChats(w http.ResponseWriter, r *http.Request) {
	if !requirePOST(w, r) {
		return
	}

	var req MergeChatsRequest
	if !decodeJSON(w, r, &req) {
		return
	}

	if !requireField(w, req.SourceJID, "source_jid") {
		return
	}
	if !requireField(w, req.TargetJID, "target_jid") {
		return
	}

	if req.SourceJID == req.TargetJID {
		writeJSONError(w, http.StatusBadRequest, "source_jid and target_jid cannot be the same")
		return
	}

	messagesMoved, err := s.store.MergeChats(req.SourceJID, req.TargetJID)
	if err != nil {
		writeJSONError(w, http.StatusBadRequest, err.Error())
		return
	}

	_ = writeJSON(w, MergeChatsResponse{
		Success:       true,
		Message:       fmt.Sprintf("Merged %d messages from %s into %s. Source chat deleted.", messagesMoved, req.SourceJID, req.TargetJID),
		MessagesMoved: messagesMoved,
	})
}

// handlePrivacySettings gets the user's privacy settings
func (s *Server) handlePrivacySettings(w http.ResponseWriter, r *http.Request) {
	if !requireGET(w, r) {
		return
	}

	// GetPrivacySettings returns just settings (errors are logged internally)
	settings := s.client.GetPrivacySettings(context.Background())

	_ = writeJSON(w, PrivacySettingsResponse{
		Success:      true,
		GroupAdd:     string(settings.GroupAdd),
		LastSeen:     string(settings.LastSeen),
		Status:       string(settings.Status),
		Profile:      string(settings.Profile),
		ReadReceipts: string(settings.ReadReceipts),
		Online:       string(settings.Online),
		CallAdd:      string(settings.CallAdd),
	})
}

// handleSetPrivacySetting updates a privacy setting
func (s *Server) handleSetPrivacySetting(w http.ResponseWriter, r *http.Request) {
	if !requirePOST(w, r) {
		return
	}

	var req SetPrivacySettingRequest
	if !decodeJSON(w, r, &req) {
		return
	}

	if !requireField(w, req.Setting, "setting") || !requireField(w, req.Value, "value") {
		return
	}

	// Validate setting type
	settingType, valid := parsePrivacySettingType(req.Setting)
	if !valid {
		writeJSONError(w, http.StatusBadRequest, "setting must be one of: groupadd, last, status, profile, readreceipts, online, calladd")
		return
	}

	// Validate value
	settingValue, valid := parsePrivacySettingValue(req.Value)
	if !valid {
		writeJSONError(w, http.StatusBadRequest, "value must be one of: all, contacts, contact_blacklist, match_last_seen, known, none")
		return
	}

	// SetPrivacySetting returns (settings, error)
	_, err := s.client.SetPrivacySetting(context.Background(), settingType, settingValue)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, fmt.Sprintf("Failed to set privacy setting: %v", err))
		return
	}

	writeJSONSuccess(w, fmt.Sprintf("Privacy setting '%s' updated to '%s'", req.Setting, req.Value))
}

// parsePrivacySettingType validates and converts a string to PrivacySettingType
func parsePrivacySettingType(s string) (types.PrivacySettingType, bool) {
	switch s {
	case "groupadd":
		return types.PrivacySettingTypeGroupAdd, true
	case "last":
		return types.PrivacySettingTypeLastSeen, true
	case "status":
		return types.PrivacySettingTypeStatus, true
	case "profile":
		return types.PrivacySettingTypeProfile, true
	case "readreceipts":
		return types.PrivacySettingTypeReadReceipts, true
	case "online":
		return types.PrivacySettingTypeOnline, true
	case "calladd":
		return types.PrivacySettingTypeCallAdd, true
	default:
		return "", false
	}
}

// parsePrivacySettingValue validates and converts a string to PrivacySetting
func parsePrivacySettingValue(s string) (types.PrivacySetting, bool) {
	switch s {
	case "all":
		return types.PrivacySettingAll, true
	case "contacts":
		return types.PrivacySettingContacts, true
	case "contact_blacklist":
		return types.PrivacySettingContactBlacklist, true
	case "match_last_seen":
		return types.PrivacySettingMatchLastSeen, true
	case "known":
		return types.PrivacySettingKnown, true
	case "none":
		return types.PrivacySettingNone, true
	default:
		return "", false
	}
}

// handleBusinessProfile gets the business profile for a JID
func (s *Server) handleBusinessProfile(w http.ResponseWriter, r *http.Request) {
	if !requirePOST(w, r) {
		return
	}

	var req GetBusinessProfileRequest
	if !decodeJSON(w, r, &req) {
		return
	}

	if !requireField(w, req.JID, "jid") {
		return
	}

	jid, err := types.ParseJID(req.JID)
	if err != nil {
		writeJSONError(w, http.StatusBadRequest, fmt.Sprintf("Invalid JID format: %v", err))
		return
	}

	profile, err := s.client.GetBusinessProfile(context.Background(), jid)
	if err != nil {
		if strings.Contains(err.Error(), "item-not-found") || strings.Contains(err.Error(), "404") {
			_ = writeJSON(w, BusinessProfileResponse{
				Success: false,
				Message: "No business profile found for this contact",
			})
			return
		}
		writeJSONError(w, http.StatusInternalServerError, fmt.Sprintf("Failed to get business profile: %v", err))
		return
	}

	if profile == nil {
		_ = writeJSON(w, BusinessProfileResponse{
			Success: false,
			Message: "Contact is not a business account",
		})
		return
	}

	// Convert to our response format
	bizProfile := &BizProfile{
		JID:                   profile.JID.String(),
		Address:               profile.Address,
		Email:                 profile.Email,
		BusinessHoursTimezone: profile.BusinessHoursTimeZone,
	}

	// Convert categories
	for _, cat := range profile.Categories {
		bizProfile.Categories = append(bizProfile.Categories, BizCategory{
			ID:   cat.ID,
			Name: cat.Name,
		})
	}

	// Convert business hours
	for _, hours := range profile.BusinessHours {
		bizProfile.BusinessHours = append(bizProfile.BusinessHours, BizHoursConfig{
			DayOfWeek: hours.DayOfWeek,
			Mode:      hours.Mode,
			OpenTime:  hours.OpenTime,
			CloseTime: hours.CloseTime,
		})
	}

	_ = writeJSON(w, BusinessProfileResponse{
		Success: true,
		Profile: bizProfile,
	})
}

// handleRejectCall rejects an incoming WhatsApp call
func (s *Server) handleRejectCall(w http.ResponseWriter, r *http.Request) {
	if !requirePOST(w, r) {
		return
	}

	var req RejectCallRequest
	if !decodeJSON(w, r, &req) {
		return
	}

	if !requireField(w, req.CallFrom, "call_from") || !requireField(w, req.CallID, "call_id") {
		return
	}

	callFrom, err := types.ParseJID(req.CallFrom)
	if err != nil {
		writeJSONError(w, http.StatusBadRequest, fmt.Sprintf("Invalid call_from JID format: %v", err))
		return
	}

	if err := s.client.RejectCall(context.Background(), callFrom, req.CallID); err != nil {
		writeJSONError(w, http.StatusInternalServerError, fmt.Sprintf("Failed to reject call: %v", err))
		return
	}

	writeJSONSuccess(w, fmt.Sprintf("Call %s from %s rejected", req.CallID, req.CallFrom))
}

// handleListNewsletters lists all subscribed WhatsApp channels
func (s *Server) handleListNewsletters(w http.ResponseWriter, r *http.Request) {
	if !requireGET(w, r) {
		return
	}

	newsletters, err := s.client.GetSubscribedNewsletters(context.Background())
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, fmt.Sprintf("Failed to list newsletters: %v", err))
		return
	}

	result := make([]NewsletterMetadata, 0, len(newsletters))
	for _, nl := range newsletters {
		result = append(result, convertNewsletterMetadata(nl))
	}

	_ = writeJSON(w, ListNewslettersResponse{
		Success:     true,
		Newsletters: result,
	})
}

// handleGetNewsletterInfo gets info about a specific newsletter
func (s *Server) handleGetNewsletterInfo(w http.ResponseWriter, r *http.Request) {
	if !requirePOST(w, r) {
		return
	}

	var req GetNewsletterInfoRequest
	if !decodeJSON(w, r, &req) {
		return
	}

	if !requireField(w, req.JID, "jid") {
		return
	}

	jid, err := types.ParseJID(req.JID)
	if err != nil {
		writeJSONError(w, http.StatusBadRequest, fmt.Sprintf("Invalid JID format: %v", err))
		return
	}

	nl, err := s.client.GetNewsletterInfo(context.Background(), jid)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, fmt.Sprintf("Failed to get newsletter info: %v", err))
		return
	}

	if nl == nil {
		_ = writeJSON(w, GetNewsletterInfoResponse{
			Success: false,
			Message: "Newsletter not found",
		})
		return
	}

	meta := convertNewsletterMetadata(nl)

	_ = writeJSON(w, GetNewsletterInfoResponse{
		Success:    true,
		Newsletter: &meta,
	})
}

// handleGetNewsletterMessages gets messages from a newsletter
func (s *Server) handleGetNewsletterMessages(w http.ResponseWriter, r *http.Request) {
	if !requirePOST(w, r) {
		return
	}

	var req GetNewsletterMessagesRequest
	if !decodeJSON(w, r, &req) {
		return
	}

	if !requireField(w, req.JID, "jid") {
		return
	}

	jid, err := types.ParseJID(req.JID)
	if err != nil {
		writeJSONError(w, http.StatusBadRequest, fmt.Sprintf("Invalid JID format: %v", err))
		return
	}

	// Build params
	count := req.Count
	if count <= 0 {
		count = 50 // Default
	}
	var before types.MessageServerID
	if req.Before > 0 {
		before = types.MessageServerID(req.Before)
	}

	messages, err := s.client.GetNewsletterMessages(context.Background(), jid, &whatsmeow.GetNewsletterMessagesParams{
		Count:  count,
		Before: before,
	})
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, fmt.Sprintf("Failed to get newsletter messages: %v", err))
		return
	}

	result := make([]NewsletterMessage, 0, len(messages))
	for _, msg := range messages {
		nm := NewsletterMessage{
			ServerID:  int(msg.MessageServerID),
			Timestamp: msg.Timestamp.Format("2006-01-02T15:04:05Z"),
			ViewCount: msg.ViewsCount,
		}
		if msg.Message != nil && msg.Message.GetConversation() != "" {
			nm.Text = msg.Message.GetConversation()
		} else if msg.Message != nil && msg.Message.GetExtendedTextMessage() != nil {
			nm.Text = msg.Message.GetExtendedTextMessage().GetText()
		}
		// Determine media type
		if msg.Message != nil {
			if msg.Message.GetImageMessage() != nil {
				nm.MediaType = "image"
			} else if msg.Message.GetVideoMessage() != nil {
				nm.MediaType = "video"
			} else if msg.Message.GetAudioMessage() != nil {
				nm.MediaType = "audio"
			} else if msg.Message.GetDocumentMessage() != nil {
				nm.MediaType = "document"
			}
		}
		result = append(result, nm)
	}

	_ = writeJSON(w, GetNewsletterMessagesResponse{
		Success:  true,
		Messages: result,
	})
}

// handleFollowNewsletter subscribes to a newsletter
func (s *Server) handleFollowNewsletter(w http.ResponseWriter, r *http.Request) {
	if !requirePOST(w, r) {
		return
	}

	var req FollowNewsletterRequest
	if !decodeJSON(w, r, &req) {
		return
	}

	if !requireField(w, req.JID, "jid") {
		return
	}

	jid, err := types.ParseJID(req.JID)
	if err != nil {
		writeJSONError(w, http.StatusBadRequest, fmt.Sprintf("Invalid JID format: %v", err))
		return
	}

	if err := s.client.FollowNewsletter(context.Background(), jid); err != nil {
		writeJSONError(w, http.StatusInternalServerError, fmt.Sprintf("Failed to follow newsletter: %v", err))
		return
	}

	writeJSONSuccess(w, fmt.Sprintf("Successfully followed newsletter %s", req.JID))
}

// handleUnfollowNewsletter unsubscribes from a newsletter
func (s *Server) handleUnfollowNewsletter(w http.ResponseWriter, r *http.Request) {
	if !requirePOST(w, r) {
		return
	}

	var req FollowNewsletterRequest
	if !decodeJSON(w, r, &req) {
		return
	}

	if !requireField(w, req.JID, "jid") {
		return
	}

	jid, err := types.ParseJID(req.JID)
	if err != nil {
		writeJSONError(w, http.StatusBadRequest, fmt.Sprintf("Invalid JID format: %v", err))
		return
	}

	if err := s.client.UnfollowNewsletter(context.Background(), jid); err != nil {
		writeJSONError(w, http.StatusInternalServerError, fmt.Sprintf("Failed to unfollow newsletter: %v", err))
		return
	}

	writeJSONSuccess(w, fmt.Sprintf("Successfully unfollowed newsletter %s", req.JID))
}
