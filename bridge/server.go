package main

import (
	"fmt"
	"net/http"

	"go.mau.fi/whatsmeow"
	waLog "go.mau.fi/whatsmeow/util/log"
)

// Server holds shared dependencies for HTTP handlers
type Server struct {
	client *whatsmeow.Client
	store  *MessageStore
	logger waLog.Logger
	port   int
	mux    *http.ServeMux
}

// NewServer creates a new Server with the given dependencies
func NewServer(client *whatsmeow.Client, store *MessageStore, logger waLog.Logger, port int) *Server {
	return &Server{
		client: client,
		store:  store,
		logger: logger,
		port:   port,
		mux:    http.NewServeMux(),
	}
}

// Start initializes routes and starts the HTTP server
func (s *Server) Start() {
	s.registerRoutes()

	serverAddr := fmt.Sprintf(":%d", s.port)
	s.logger.Infof("Starting REST API server on %s...", serverAddr)

	// Run server in a goroutine so it doesn't block
	go func() {
		if err := http.ListenAndServe(serverAddr, s.mux); err != nil {
			s.logger.Errorf("REST API server error: %v", err)
		}
	}()
}

// registerRoutes sets up all HTTP route handlers
func (s *Server) registerRoutes() {
	s.mux.HandleFunc("/api/health", s.handleHealth)
	s.mux.HandleFunc("/api/send", s.handleSend)
	s.mux.HandleFunc("/api/download", s.handleDownload)
	s.mux.HandleFunc("/api/resolve-lid", s.handleResolveLid)
	s.mux.HandleFunc("/api/typing", s.handleTyping)
	s.mux.HandleFunc("/api/mark-read", s.handleMarkRead)
	s.mux.HandleFunc("/api/reaction", s.handleReaction)
	s.mux.HandleFunc("/api/delete", s.handleDelete)
	s.mux.HandleFunc("/api/reply", s.handleReply)
	s.mux.HandleFunc("/api/edit", s.handleEdit)
	s.mux.HandleFunc("/api/location", s.handleLocation)
	s.mux.HandleFunc("/api/presence", s.handlePresence)
	s.mux.HandleFunc("/api/subscribe-presence", s.handleSubscribePresence)
	s.mux.HandleFunc("/api/disappearing", s.handleDisappearing)
	s.mux.HandleFunc("/api/is-on-whatsapp", s.handleIsOnWhatsApp)
	s.mux.HandleFunc("/api/profile-picture", s.handleProfilePicture)
	s.mux.HandleFunc("/api/blocklist", s.handleBlocklist)
	s.mux.HandleFunc("/api/block", s.handleBlock)
	s.mux.HandleFunc("/api/groups", s.handleListGroups)
	s.mux.HandleFunc("/api/group-info", s.handleGroupInfo)
	s.mux.HandleFunc("/api/contacts", s.handleContacts)
	s.mux.HandleFunc("/api/poll", s.handlePoll)
	s.mux.HandleFunc("/api/merge-chats", s.handleMergeChats)
	s.mux.HandleFunc("/api/group-invite-link", s.handleGroupInviteLink)
	s.mux.HandleFunc("/api/join-group", s.handleJoinGroup)
	s.mux.HandleFunc("/api/create-group", s.handleCreateGroup)
	s.mux.HandleFunc("/api/leave-group", s.handleLeaveGroup)
	s.mux.HandleFunc("/api/update-group-name", s.handleUpdateGroupName)
	s.mux.HandleFunc("/api/update-group-description", s.handleUpdateGroupDescription)
	s.mux.HandleFunc("/api/update-group-settings", s.handleUpdateGroupSettings)
	s.mux.HandleFunc("/api/update-group-participants", s.handleUpdateGroupParticipants)
	s.mux.HandleFunc("/api/privacy-settings", s.handlePrivacySettings)
	s.mux.HandleFunc("/api/privacy-setting", s.handleSetPrivacySetting)
	s.mux.HandleFunc("/api/business-profile", s.handleBusinessProfile)
	s.mux.HandleFunc("/api/reject-call", s.handleRejectCall)
	s.mux.HandleFunc("/api/newsletters", s.handleListNewsletters)
	s.mux.HandleFunc("/api/newsletter-info", s.handleGetNewsletterInfo)
	s.mux.HandleFunc("/api/newsletter-messages", s.handleGetNewsletterMessages)
	s.mux.HandleFunc("/api/follow-newsletter", s.handleFollowNewsletter)
	s.mux.HandleFunc("/api/unfollow-newsletter", s.handleUnfollowNewsletter)
}
