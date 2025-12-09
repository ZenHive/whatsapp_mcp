# Go Bridge Refactoring Roadmap

This roadmap breaks down the refactoring of `bridge/main.go` (3,080 lines) into manageable, incremental tasks.

## Current State Analysis

**File:** `bridge/main.go`
**Lines:** 3,080
**Functions:** ~45
**Types:** ~35

### Problem Areas

| Function | Lines | % of File | Problem |
|----------|-------|-----------|---------|
| `startRESTServer` | 1,193 | 39% | God function - all HTTP handlers inline |
| `handleMessage` | 314 | 10% | Large event handler |
| `handleHistorySync` | ~160 | 5% | History sync logic mixed with message processing |
| (scattered types) | ~250 | 8% | 35 struct definitions spread throughout file |

### Target Structure

```
bridge/
├── main.go           # Entry point, main(), signal handling (~400 lines)
├── config.go         # Constants, getAPIPort() (~100 lines)
├── types.go          # All struct definitions (~250 lines)
├── database.go       # MessageStore and methods (~200 lines)
├── reconnect.go      # ReconnectManager (~120 lines)
├── server.go         # HTTP router setup (~100 lines)
├── handlers.go       # HTTP handler functions (~600 lines)
├── handlers_media.go # Media-related handlers (~300 lines)
├── handlers_groups.go# Group-related handlers (~200 lines)
├── messaging.go      # sendWhatsAppMessage, extractors (~200 lines)
├── media.go          # MediaDownloader, downloadMedia, audio analysis (~300 lines)
├── events.go         # handleMessage, handleHistorySync (~500 lines)
├── contacts.go       # GetChatName, cacheContactName (~150 lines)
└── groups.go         # convertGroupInfo, group utilities (~100 lines)
```

---

## Phase 1: Extract Types & Config (Low Risk)

These tasks extract code without changing any logic - pure file reorganization.

### Task 1: Extract Types to types.go
- [x] **Complete** [D:1/B:8 → Priority:8.0] 🎯

**Goal:** Move all struct definitions to a dedicated `types.go` file.

**Types to extract (35 total):**
```go
// Core types
Message
MessageStore
ReconnectManager

// Request types
SendMessageRequest
DownloadMediaRequest
ResolveLidRequest
TypingRequest
MarkReadRequest
ReactionRequest
DeleteMessageRequest
ReplyMessageRequest
LocationRequest
EditMessageRequest
PresenceRequest
SubscribePresenceRequest
DisappearingTimerRequest
IsOnWhatsAppRequest
GetProfilePictureRequest
UpdateBlocklistRequest
CreatePollRequest
GetGroupInfoRequest
MergeChatsRequest
GetGroupInviteLinkRequest
JoinGroupRequest

// Response types
SendMessageResponse
HealthResponse
DownloadMediaResponse
ResolveLidResponse
APIResponse
IsOnWhatsAppResponse
IsOnWhatsAppResult
GetProfilePictureResponse
BlocklistResponse
GroupInfo
GroupMember
ListGroupsResponse
GetGroupInfoResponse
GetGroupInviteLinkResponse
JoinGroupResponse
ContactEntry
ListContactsResponse
MergeChatsResponse
MediaDownloader
```

**Files to create:**
- `bridge/types.go`

**Files to modify:**
- `bridge/main.go` - Remove type definitions

**Acceptance criteria:**
- [x] All types moved to `types.go` (41 types, 332 lines)
- [x] `go build` succeeds
- [x] No logic changes

---

### Task 2: Extract Config to config.go
- [x] **Complete** [D:1/B:6 → Priority:6.0] 🎯

**Goal:** Move constants and configuration to dedicated file.

**Code to extract:**
```go
// Constants (lines 37-84)
const DeviceName = "WhatsApp MCP"
const (
    DefaultAPIPort = 8080
    QRCodeTimeoutMinutes = 3
    // ... all other constants
)

// Config function
func getAPIPort() int
```

**Files to create:**
- `bridge/config.go`

**Files to modify:**
- `bridge/main.go` - Remove constants and getAPIPort()

**Acceptance criteria:**
- [x] All constants in `config.go` (70 lines)
- [x] `getAPIPort()` in `config.go`
- [x] `go build` succeeds

---

### Task 3: Extract Database to database.go
- [x] **Complete** [D:2/B:7 → Priority:3.5] 🎯

**Goal:** Move MessageStore and all database operations to dedicated file.

**Code to extract:**
```go
// MessageStore struct (already in types.go after Task 1)

// Database functions
func NewMessageStore() (*MessageStore, error)
func (store *MessageStore) Close() error
func (store *MessageStore) StoreChat(...)
func (store *MessageStore) StoreMessage(...)
func (store *MessageStore) GetMessages(...)
func (store *MessageStore) StoreContact(...)
func (store *MessageStore) GetContact(...)
func (store *MessageStore) GetChats() (...)
func (store *MessageStore) MergeChats(...)
func (store *MessageStore) StoreMediaInfo(...)
func (store *MessageStore) GetMediaInfo(...)
```

**Files to create:**
- `bridge/database.go`

**Files to modify:**
- `bridge/main.go` - Remove database functions

**Acceptance criteria:**
- [x] All MessageStore methods in `database.go` (258 lines)
- [x] `NewMessageStore()` in `database.go`
- [x] `go build` succeeds

---

### Task 4: Extract ReconnectManager to reconnect.go
- [x] **Complete** [D:1/B:5 → Priority:5.0] 🎯

**Goal:** Move reconnection logic to dedicated file.

**Code to extract:**
```go
// ReconnectManager struct (in types.go after Task 1)

func NewReconnectManager(client *whatsmeow.Client, logger waLog.Logger) *ReconnectManager
func (rm *ReconnectManager) calculateBackoff(attempt int) time.Duration
func (rm *ReconnectManager) StartReconnect(reason string)
func (rm *ReconnectManager) reconnectLoop(reason string)
func (rm *ReconnectManager) Stop()
```

**Files to create:**
- `bridge/reconnect.go`

**Files to modify:**
- `bridge/main.go` - Remove reconnect functions

**Acceptance criteria:**
- [x] All ReconnectManager methods in `reconnect.go` (113 lines)
- [x] `go build` succeeds

---

## Phase 2: Extract Business Logic (Medium Risk)

### Task 5: Extract Messaging to messaging.go
- [x] **Complete** [D:2/B:6 → Priority:3.0] 🚀

**Goal:** Move message sending and content extraction to dedicated file.

**Code extracted:**
```go
func extractTextContent(msg *waProto.Message) string
func sendWhatsAppMessage(client *whatsmeow.Client, recipient string, message string, mediaPath string) (bool, string)
func extractMediaInfo(msg *waProto.Message) (...)
```

**Files created:**
- `bridge/messaging.go` (237 lines)

**Acceptance criteria:**
- [x] Message sending logic isolated
- [x] Content extractors accessible to handlers
- [x] `go build` succeeds

---

### Task 6: Extract Media to media.go
- [x] **Complete** [D:2/B:6 → Priority:3.0] 🚀

**Goal:** Move media handling (download, audio analysis) to dedicated file.

**Code extracted:**
```go
// MediaDownloader interface methods
func (d *MediaDownloader) GetDirectPath() string
func (d *MediaDownloader) GetURL() string
func (d *MediaDownloader) GetMediaKey() []byte
func (d *MediaDownloader) GetFileLength() uint64
func (d *MediaDownloader) GetFileSHA256() []byte
func (d *MediaDownloader) GetFileEncSHA256() []byte
func (d *MediaDownloader) GetMediaType() whatsmeow.MediaType
func downloadMedia(client *whatsmeow.Client, messageStore *MessageStore, messageID, chatJID string) (...)
func extractDirectPathFromURL(url string) string
func analyzeOggOpus(data []byte) (duration uint32, waveform []byte, err error)
func min(x, y int) int
func placeholderWaveform(duration uint32) []byte
```

**Files created:**
- `bridge/media.go` (333 lines)

**Acceptance criteria:**
- [x] All media operations in `media.go`
- [x] Audio analysis functions included
- [x] `go build` succeeds

---

### Task 7: Extract Events to events.go
- [x] **Complete** [D:3/B:7 → Priority:2.3] 🚀

**Goal:** Move event handlers to dedicated file.

**Code extracted:**
```go
func handleMessage(client *whatsmeow.Client, messageStore *MessageStore, msg *events.Message, logger waLog.Logger)
func handleHistorySync(client *whatsmeow.Client, messageStore *MessageStore, historySync *events.HistorySync, logger waLog.Logger)
```

**Files created:**
- `bridge/events.go` (235 lines)

**Acceptance criteria:**
- [x] Event handlers in `events.go`
- [x] Handlers have access to required dependencies
- [x] `go build` succeeds

---

### Task 8: Extract Contacts to contacts.go
- [x] **Complete** [D:2/B:5 → Priority:2.5] 🚀

**Goal:** Move contact/name resolution to dedicated file.

**Code extracted:**
```go
func GetChatName(client *whatsmeow.Client, messageStore *MessageStore, jid types.JID, chatJID string, conversation interface{}, sender string, logger waLog.Logger) string
func cacheContactName(messageStore *MessageStore, jid string, phone string, name string, logger waLog.Logger)
```

**Files created:**
- `bridge/contacts.go` (111 lines)

**Acceptance criteria:**
- [x] Contact resolution in `contacts.go`
- [x] `go build` succeeds

---

### Task 9: Extract Groups to groups.go
- [x] **Complete** [D:1/B:4 → Priority:4.0] 🎯

**Goal:** Move group utilities to dedicated file.

**Code extracted:**
```go
func convertGroupInfo(g *types.GroupInfo, includeParticipants bool) GroupInfo
```

**Files created:**
- `bridge/groups.go` (48 lines)

**Acceptance criteria:**
- [x] Group utilities in `groups.go`
- [x] `go build` succeeds

---

## Phase 3: Refactor HTTP Server (High Impact)

This is the biggest win - breaking apart the 1,193-line `startRESTServer` function.

### Task 10: Create Server Struct
- [x] **Complete** [D:3/B:8 → Priority:2.7] 🎯

**Goal:** Create a Server struct to hold shared dependencies instead of passing them to every handler.

**Current pattern:**
```go
func startRESTServer(client *whatsmeow.Client, messageStore *MessageStore, port int) {
    http.HandleFunc("/api/send", func(w http.ResponseWriter, r *http.Request) {
        // Uses client and messageStore via closure
    })
}
```

**New pattern:**
```go
type Server struct {
    client       *whatsmeow.Client
    store        *MessageStore
    logger       waLog.Logger
}

func NewServer(client *whatsmeow.Client, store *MessageStore, logger waLog.Logger) *Server

func (s *Server) handleSend(w http.ResponseWriter, r *http.Request) {
    // Access s.client, s.store directly
}
```

**Files to create:**
- `bridge/server.go`

**Acceptance criteria:**
- [x] Server struct defined (75 lines in server.go)
- [x] NewServer constructor
- [x] Dependencies accessible via receiver
- [x] All 25 handlers converted to Server methods (1,137 lines in handlers.go)
- [x] main.go reduced from 2,309 → 1,106 lines (-52%)
- [x] `go build` succeeds

---

### Task 11: Extract HTTP Helpers to helpers.go
- [x] **Complete** [D:1/B:5 → Priority:5.0] 🎯

**Goal:** Move shared HTTP utilities to dedicated file.

**Code to extract:**
```go
func requirePOST(w http.ResponseWriter, r *http.Request) bool
func decodeJSON(w http.ResponseWriter, r *http.Request, v interface{}) bool
func requireField(w http.ResponseWriter, value, fieldName string) bool
func parseRecipientJID(recipient string) (types.JID, error)
func writeJSONError(w http.ResponseWriter, statusCode int, message string)
func writeJSONSuccess(w http.ResponseWriter, message string)
```

**Files to create:**
- `bridge/helpers.go`

**Acceptance criteria:**
- [x] HTTP helpers in `helpers.go` (66 lines)
- [x] Used by all handlers
- [x] `go build` succeeds

---

### Task 12: Extract Core Handlers to handlers.go
- [x] **Complete** [D:4/B:9 → Priority:2.25] 🎯

**Goal:** Extract core messaging handlers from `startRESTServer`.

**Note:** This task was completed as part of Task 10 (Server struct creation). All 25 handlers were extracted to handlers.go as Server methods.

**Handlers extracted (25 total):**
- handleHealth, handleSend, handleDownload, handleResolveLid
- handleTyping, handleMarkRead, handleReaction, handleDelete
- handleReply, handleEdit, handleLocation, handlePresence
- handleSubscribePresence, handleDisappearing, handleIsOnWhatsApp
- handleProfilePicture, handleBlocklist, handleBlock
- handleListGroups, handleGroupInfo, handleContacts
- handlePoll, handleMergeChats, handleGroupInviteLink, handleJoinGroup

**Files created:**
- `bridge/handlers.go` (1,137 lines)

**Files modified:**
- `bridge/server.go` - Route registration only (75 lines)
- `bridge/main.go` - Removed startRESTServer

**Acceptance criteria:**
- [x] All core handlers extracted (25 handlers)
- [x] `startRESTServer` replaced with Server.Start() and registerRoutes()
- [x] `go build` succeeds

---

### Task 13: Extract Group Handlers to handlers_groups.go
- [x] **Complete** [D:2/B:5 → Priority:2.5] 🎯

**Goal:** Extract group-related handlers to dedicated file.

**Handlers extracted:**
```go
func (s *Server) handleListGroups(w http.ResponseWriter, r *http.Request)
func (s *Server) handleGroupInfo(w http.ResponseWriter, r *http.Request)
func (s *Server) handleGroupInviteLink(w http.ResponseWriter, r *http.Request)
func (s *Server) handleJoinGroup(w http.ResponseWriter, r *http.Request)
```

**Files created:**
- `bridge/handlers_groups.go` (166 lines)

**Files modified:**
- `bridge/handlers.go` - Removed group handlers (1,137 → 949 lines)

**Acceptance criteria:**
- [x] Group handlers in dedicated file (4 handlers)
- [x] `go build` succeeds

---

### Task 14: Clean Up main.go
- [x] **Complete** [D:2/B:7 → Priority:3.5] 🎯

**Goal:** After all extractions, main.go should only contain:
- Package imports
- `main()` function
- Signal handling
- High-level orchestration

**Result:**
- main.go reduced from 1,106 → **191 lines** (83% reduction!)
- Contains only `main()` function with:
  - Logger setup
  - Store initialization
  - Client setup
  - QR code handling
  - Event registration
  - Server startup
  - Signal handling

**Files created during cleanup (Tasks 5-9):**
- `bridge/messaging.go` (237 lines) - Task 5
- `bridge/media.go` (333 lines) - Task 6
- `bridge/events.go` (235 lines) - Task 7
- `bridge/contacts.go` (111 lines) - Task 8
- `bridge/groups.go` (48 lines) - Task 9

**Acceptance criteria:**
- [x] main.go under 500 lines (achieved 191 lines!)
- [x] Only orchestration logic remains
- [x] `go build` succeeds
- [x] All functionality preserved

---

## Phase 4: Optional Improvements (Deferred)

### Task 15: Add Go Interfaces for Testing
- [x] **Deferred** [D:4/B:6 → Priority:1.5] ⏸️

**Status:** Deferred - Elixir integration tests already exercise the Go bridge through HTTP calls, providing sufficient test coverage without duplicating effort at the Go level.

**Original goal:** Define interfaces for major components to enable unit testing.

---

### Task 16: Add Go Tests
- [x] **Deferred** [D:5/B:7 → Priority:1.4] ⏸️

**Status:** Deferred - The Elixir MCP server's integration tests (`mix test --include integration`) call the Go bridge HTTP API, validating end-to-end behavior. Go-level unit tests would provide redundant coverage.

**Original goal:** Add unit tests for extracted components.

---

## Summary

| Phase | Tasks | Status | Impact |
|-------|-------|--------|--------|
| 1. Types & Config | 1-4 | ✅ Complete | main.go: 3,080→2,366 (-714 lines) |
| 2. Business Logic | 5-9 | ✅ Complete | 5 new files, clean separation |
| 3. HTTP Server | 10-14 | ✅ Complete | main.go: 2,366→191, handlers split |
| 4. Optional | 15-16 | ⏸️ Deferred | Elixir integration tests provide coverage |

### Priority Order (by D/B ratio)

| Priority | Task | Description | D/B/P |
|----------|------|-------------|-------|
| ✅ | 1 | Extract types to types.go | 1/8/8.0 |
| ✅ | 2 | Extract config to config.go | 1/6/6.0 |
| ✅ | 11 | Extract HTTP helpers | 1/5/5.0 |
| ✅ | 4 | Extract ReconnectManager | 1/5/5.0 |
| ✅ | 9 | Extract groups.go | 1/4/4.0 |
| ✅ | 3 | Extract database.go | 2/7/3.5 |
| ✅ | 14 | Clean up main.go | 2/7/3.5 |
| ✅ | 5 | Extract messaging.go | 2/6/3.0 |
| ✅ | 6 | Extract media.go | 2/6/3.0 |
| ✅ | 10 | Create Server struct | 3/8/2.7 |
| ✅ | 8 | Extract contacts.go | 2/5/2.5 |
| ✅ | 13 | Extract group handlers | 2/5/2.5 |
| ✅ | 12 | Extract core handlers | 4/9/2.25 |
| ✅ | 7 | Extract events.go | 3/7/2.3 |
| ⏸️ | 15 | Add interfaces for testing | 4/6/1.5 |
| ⏸️ | 16 | Add Go tests | 5/7/1.4 |

**Completed: 14 tasks | Deferred: 2 tasks | Total: 16 tasks**

**Refactoring Complete!** The Go bridge is now well-organized across 14 files with clean separation of concerns. Elixir integration tests provide sufficient coverage for the HTTP API.

### Current File Structure

| File | Lines | Purpose |
|------|-------|---------|
| handlers.go | 947 | HTTP handler methods (21 handlers) |
| media.go | 333 | Media download, audio analysis |
| types.go | 332 | All struct definitions |
| database.go | 258 | MessageStore methods |
| messaging.go | 237 | Message sending, content extraction |
| events.go | 235 | handleMessage, handleHistorySync |
| main.go | 191 | Entry point, orchestration only |
| handlers_groups.go | 165 | Group-related HTTP handlers (4 handlers) |
| reconnect.go | 113 | ReconnectManager |
| contacts.go | 111 | GetChatName, contact caching |
| helpers.go | 75 | HTTP utilities |
| server.go | 73 | Server struct, route registration |
| config.go | 70 | Constants |
| groups.go | 48 | convertGroupInfo utility |
| **Total** | **3,188** | |
