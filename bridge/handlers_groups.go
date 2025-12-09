package main

import (
	"context"
	"fmt"
	"net/http"
	"strings"

	"go.mau.fi/whatsmeow"
	"go.mau.fi/whatsmeow/types"
)

// handleListGroups lists joined groups
func (s *Server) handleListGroups(w http.ResponseWriter, r *http.Request) {
	if !requireGET(w, r) {
		return
	}

	groups, err := s.client.GetJoinedGroups(context.Background())
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, fmt.Sprintf("Failed to get joined groups: %v", err))
		return
	}

	groupInfos := make([]GroupInfo, len(groups))
	for i, g := range groups {
		groupInfos[i] = convertGroupInfo(g, false)
	}

	_ = writeJSON(w, ListGroupsResponse{
		Success: true,
		Groups:  groupInfos,
	})
}

// handleGroupInfo gets detailed group info
func (s *Server) handleGroupInfo(w http.ResponseWriter, r *http.Request) {
	if !requirePOST(w, r) {
		return
	}

	var req GetGroupInfoRequest
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

	if jid.Server != "g.us" {
		writeJSONError(w, http.StatusBadRequest, "JID is not a group (must end with @g.us)")
		return
	}

	groupInfo, err := s.client.GetGroupInfo(context.Background(), jid)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, fmt.Sprintf("Failed to get group info: %v", err))
		return
	}

	info := convertGroupInfo(groupInfo, true)

	_ = writeJSON(w, GetGroupInfoResponse{
		Success: true,
		Group:   &info,
	})
}

// handleGroupInviteLink gets or resets group invite link
func (s *Server) handleGroupInviteLink(w http.ResponseWriter, r *http.Request) {
	if !requirePOST(w, r) {
		return
	}

	var req GetGroupInviteLinkRequest
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

	if jid.Server != "g.us" {
		writeJSONError(w, http.StatusBadRequest, "JID must be a group (must end with @g.us)")
		return
	}

	inviteLink, err := s.client.GetGroupInviteLink(context.Background(), jid, req.Reset)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, fmt.Sprintf("Failed to get invite link: %v", err))
		return
	}

	message := "Invite link retrieved"
	if req.Reset {
		message = "Invite link reset successfully"
	}

	_ = writeJSON(w, GetGroupInviteLinkResponse{
		Success:    true,
		InviteLink: inviteLink,
		Message:    message,
	})
}

// handleJoinGroup joins a group via invite link
func (s *Server) handleJoinGroup(w http.ResponseWriter, r *http.Request) {
	if !requirePOST(w, r) {
		return
	}

	var req JoinGroupRequest
	if !decodeJSON(w, r, &req) {
		return
	}

	if !requireField(w, req.InviteLink, "invite_link") {
		return
	}

	inviteCode := req.InviteLink
	if strings.Contains(inviteCode, "chat.whatsapp.com/") {
		parts := strings.Split(inviteCode, "chat.whatsapp.com/")
		if len(parts) >= 2 {
			inviteCode = parts[len(parts)-1]
		}
	}
	inviteCode = strings.Split(inviteCode, "?")[0]
	inviteCode = strings.TrimSuffix(inviteCode, "/")

	if inviteCode == "" {
		writeJSONError(w, http.StatusBadRequest, "Invalid invite link format")
		return
	}

	groupJID, err := s.client.JoinGroupWithLink(context.Background(), inviteCode)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, fmt.Sprintf("Failed to join group: %v", err))
		return
	}

	_ = writeJSON(w, JoinGroupResponse{
		Success:  true,
		GroupJID: groupJID.String(),
		Message:  fmt.Sprintf("Successfully joined group %s", groupJID.String()),
	})
}

// handleCreateGroup creates a new group
func (s *Server) handleCreateGroup(w http.ResponseWriter, r *http.Request) {
	if !requirePOST(w, r) {
		return
	}

	var req CreateGroupRequest
	if !decodeJSON(w, r, &req) {
		return
	}

	if !requireField(w, req.Name, "name") {
		return
	}

	// Validate group name length (WhatsApp limit is 25 characters)
	if len(req.Name) > 25 {
		writeJSONError(w, http.StatusBadRequest, "Group name must be 25 characters or less")
		return
	}

	// Parse participant JIDs
	participants := make([]types.JID, 0, len(req.Participants))
	for _, p := range req.Participants {
		jid, err := types.ParseJID(p)
		if err != nil {
			writeJSONError(w, http.StatusBadRequest, fmt.Sprintf("Invalid participant JID %q: %v", p, err))
			return
		}
		participants = append(participants, jid)
	}

	// Create the group
	groupInfo, err := s.client.CreateGroup(context.Background(), whatsmeow.ReqCreateGroup{
		Name:         req.Name,
		Participants: participants,
	})
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, fmt.Sprintf("Failed to create group: %v", err))
		return
	}

	info := convertGroupInfo(groupInfo, true)

	_ = writeJSON(w, CreateGroupResponse{
		Success: true,
		Group:   &info,
		Message: fmt.Sprintf("Successfully created group %q", req.Name),
	})
}

// handleLeaveGroup leaves a group
func (s *Server) handleLeaveGroup(w http.ResponseWriter, r *http.Request) {
	if !requirePOST(w, r) {
		return
	}

	var req LeaveGroupRequest
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

	if jid.Server != "g.us" {
		writeJSONError(w, http.StatusBadRequest, "JID must be a group (must end with @g.us)")
		return
	}

	err = s.client.LeaveGroup(context.Background(), jid)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, fmt.Sprintf("Failed to leave group: %v", err))
		return
	}

	_ = writeJSON(w, LeaveGroupResponse{
		Success: true,
		Message: fmt.Sprintf("Successfully left group %s", jid.String()),
	})
}

// handleUpdateGroupName updates a group's name
func (s *Server) handleUpdateGroupName(w http.ResponseWriter, r *http.Request) {
	if !requirePOST(w, r) {
		return
	}

	var req UpdateGroupNameRequest
	if !decodeJSON(w, r, &req) {
		return
	}

	if !requireField(w, req.JID, "jid") {
		return
	}
	if !requireField(w, req.Name, "name") {
		return
	}

	jid, err := types.ParseJID(req.JID)
	if err != nil {
		writeJSONError(w, http.StatusBadRequest, fmt.Sprintf("Invalid JID format: %v", err))
		return
	}

	if jid.Server != "g.us" {
		writeJSONError(w, http.StatusBadRequest, "JID must be a group (must end with @g.us)")
		return
	}

	// WhatsApp limit is 25 characters for group names
	if len(req.Name) > 25 {
		writeJSONError(w, http.StatusBadRequest, "Group name must be 25 characters or less")
		return
	}

	err = s.client.SetGroupName(context.Background(), jid, req.Name)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, fmt.Sprintf("Failed to update group name: %v", err))
		return
	}

	_ = writeJSON(w, APIResponse{
		Success: true,
		Message: fmt.Sprintf("Group name updated to %q", req.Name),
	})
}

// handleUpdateGroupDescription updates a group's description/topic
func (s *Server) handleUpdateGroupDescription(w http.ResponseWriter, r *http.Request) {
	if !requirePOST(w, r) {
		return
	}

	var req UpdateGroupDescriptionRequest
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

	if jid.Server != "g.us" {
		writeJSONError(w, http.StatusBadRequest, "JID must be a group (must end with @g.us)")
		return
	}

	// SetGroupTopic handles fetching previousID and generating newID if empty strings passed
	err = s.client.SetGroupTopic(context.Background(), jid, "", "", req.Description)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, fmt.Sprintf("Failed to update group description: %v", err))
		return
	}

	message := "Group description updated"
	if req.Description == "" {
		message = "Group description cleared"
	}

	_ = writeJSON(w, APIResponse{
		Success: true,
		Message: message,
	})
}

// handleUpdateGroupSettings updates group settings (locked, announce)
func (s *Server) handleUpdateGroupSettings(w http.ResponseWriter, r *http.Request) {
	if !requirePOST(w, r) {
		return
	}

	var req UpdateGroupSettingsRequest
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

	if jid.Server != "g.us" {
		writeJSONError(w, http.StatusBadRequest, "JID must be a group (must end with @g.us)")
		return
	}

	if req.Locked == nil && req.Announce == nil {
		writeJSONError(w, http.StatusBadRequest, "At least one of 'locked' or 'announce' must be specified")
		return
	}

	var changes []string

	if req.Locked != nil {
		err = s.client.SetGroupLocked(context.Background(), jid, *req.Locked)
		if err != nil {
			writeJSONError(w, http.StatusInternalServerError, fmt.Sprintf("Failed to update locked setting: %v", err))
			return
		}
		if *req.Locked {
			changes = append(changes, "locked (only admins can edit info)")
		} else {
			changes = append(changes, "unlocked (all members can edit info)")
		}
	}

	if req.Announce != nil {
		err = s.client.SetGroupAnnounce(context.Background(), jid, *req.Announce)
		if err != nil {
			writeJSONError(w, http.StatusInternalServerError, fmt.Sprintf("Failed to update announce setting: %v", err))
			return
		}
		if *req.Announce {
			changes = append(changes, "announce mode enabled (only admins can send)")
		} else {
			changes = append(changes, "announce mode disabled (all members can send)")
		}
	}

	_ = writeJSON(w, APIResponse{
		Success: true,
		Message: fmt.Sprintf("Group settings updated: %s", strings.Join(changes, ", ")),
	})
}

// handleUpdateGroupParticipants adds, removes, promotes, or demotes group members
func (s *Server) handleUpdateGroupParticipants(w http.ResponseWriter, r *http.Request) {
	if !requirePOST(w, r) {
		return
	}

	var req UpdateGroupParticipantsRequest
	if !decodeJSON(w, r, &req) {
		return
	}

	if !requireField(w, req.JID, "jid") {
		return
	}
	if !requireField(w, req.Action, "action") {
		return
	}

	// Validate action
	var action whatsmeow.ParticipantChange
	switch strings.ToLower(req.Action) {
	case "add":
		action = whatsmeow.ParticipantChangeAdd
	case "remove":
		action = whatsmeow.ParticipantChangeRemove
	case "promote":
		action = whatsmeow.ParticipantChangePromote
	case "demote":
		action = whatsmeow.ParticipantChangeDemote
	default:
		writeJSONError(w, http.StatusBadRequest, "Invalid action. Must be one of: add, remove, promote, demote")
		return
	}

	if len(req.Participants) == 0 {
		writeJSONError(w, http.StatusBadRequest, "At least one participant is required")
		return
	}

	jid, err := types.ParseJID(req.JID)
	if err != nil {
		writeJSONError(w, http.StatusBadRequest, fmt.Sprintf("Invalid group JID format: %v", err))
		return
	}

	if jid.Server != "g.us" {
		writeJSONError(w, http.StatusBadRequest, "JID must be a group (must end with @g.us)")
		return
	}

	// Parse participant JIDs
	participantJIDs := make([]types.JID, 0, len(req.Participants))
	for _, p := range req.Participants {
		pJID, err := types.ParseJID(p)
		if err != nil {
			writeJSONError(w, http.StatusBadRequest, fmt.Sprintf("Invalid participant JID %q: %v", p, err))
			return
		}
		participantJIDs = append(participantJIDs, pJID)
	}

	// Execute the participant change
	results, err := s.client.UpdateGroupParticipants(context.Background(), jid, participantJIDs, action)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, fmt.Sprintf("Failed to %s participants: %v", req.Action, err))
		return
	}

	// Build response with individual participant results
	participants := make([]GroupParticipantResponse, len(results))
	for i, result := range results {
		participants[i] = GroupParticipantResponse{
			JID:       result.JID.String(),
			ErrorCode: result.Error,
		}
	}

	actionVerb := map[string]string{
		"add":     "added to",
		"remove":  "removed from",
		"promote": "promoted in",
		"demote":  "demoted in",
	}[strings.ToLower(req.Action)]

	_ = writeJSON(w, UpdateGroupParticipantsResponse{
		Success:      true,
		Message:      fmt.Sprintf("Successfully %s group: %d participant(s)", actionVerb, len(results)),
		Participants: participants,
	})
}
