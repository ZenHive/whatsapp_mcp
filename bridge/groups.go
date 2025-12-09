package main

import (
	"time"

	"go.mau.fi/whatsmeow/types"
)

// convertGroupInfo converts whatsmeow GroupInfo to our API GroupInfo struct.
// Set includeParticipants to true for detailed view, false for list view.
func convertGroupInfo(g *types.GroupInfo, includeParticipants bool) GroupInfo {
	info := GroupInfo{
		JID:              g.JID.String(),
		Name:             g.Name,
		Topic:            g.Topic,
		ParticipantCount: len(g.Participants),
		IsAnnounce:       g.IsAnnounce,
		IsLocked:         g.IsLocked,
	}

	if !g.OwnerJID.IsEmpty() {
		info.OwnerJID = g.OwnerJID.String()
	}
	if !g.GroupCreated.IsZero() {
		info.CreatedAt = g.GroupCreated.Format(time.RFC3339)
	}

	if includeParticipants {
		if !g.TopicSetAt.IsZero() {
			info.TopicSetAt = g.TopicSetAt.Format(time.RFC3339)
		}
		if !g.TopicSetBy.IsEmpty() {
			info.TopicSetBy = g.TopicSetBy.String()
		}

		participants := make([]GroupMember, len(g.Participants))
		for i, p := range g.Participants {
			participants[i] = GroupMember{
				JID:          p.JID.String(),
				IsAdmin:      p.IsAdmin,
				IsSuperAdmin: p.IsSuperAdmin,
			}
		}
		info.Participants = participants
	}

	return info
}
