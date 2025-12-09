# Changelog

All notable changes to the WhatsApp MCP Server.

## [Unreleased]

## [0.2.0] - 2025-12-14

### Added
- **Group Lifecycle Tools** (Task 41c)
  - `create_group` - Create a new WhatsApp group with initial members (max 25 char name)
  - `leave_group` - Leave a WhatsApp group
- **Group Admin Tools** (Task 41d)
  - `update_group_name` - Update group name (max 25 chars, admin only)
  - `update_group_description` - Update or clear group description (admin only)
  - `update_group_settings` - Update locked/announce modes (admin only)
  - `manage_group_members` - Add/remove/promote/demote members (admin only)

### Changed
- **Go Bridge Refactoring Complete** (Task 49) - Reorganized `bridge/main.go` (3,080 lines) into 14 well-structured files:
  - `main.go` (191 lines) - Entry point and orchestration only
  - `handlers.go` (947 lines) - 21 HTTP handler methods
  - `handlers_groups.go` (165 lines) - 4 group-related handlers
  - `server.go` (73 lines) - Server struct and route registration
  - `helpers.go` (75 lines) - HTTP utilities
  - `types.go` (332 lines) - All struct definitions
  - `database.go` (258 lines) - MessageStore operations
  - `reconnect.go` (113 lines) - Automatic reconnection logic
  - `config.go` (70 lines) - Constants and configuration
  - `messaging.go` (237 lines) - Message sending and extraction
  - `media.go` (333 lines) - Media download and audio analysis
  - `events.go` (235 lines) - Message and history sync handlers
  - `contacts.go` (111 lines) - Contact name resolution
  - `groups.go` (48 lines) - Group info utilities
- **Task 46 Deferred** - Tool Definition DSL deferred until REST/GraphQL needed

## [0.1.0] - 2024

### Added

#### MCP Tools - Reading
- `list_chats` - List chats with JIDs, names, and last message preview
- `get_messages` - Fetch messages by chat_id or chat_name with pagination
- `search_messages` - Full-text search across chats with media filter
- `search_contacts` - Search contacts by name or phone number
- `get_chat` - Get single chat metadata by JID
- `get_direct_chat_by_contact` - Get chat metadata by phone number
- `get_message_context` - Get messages before/after a target message
- `get_last_interaction` - Get most recent message with a contact
- `get_contact_chats` - List all chats involving a contact
- `get_bridge_status` - Check bridge connection status
- `get_help` - Usage guide with phone formats and workflows

#### MCP Tools - Writing
- `send_message` - Send text messages
- `send_file` - Send images, videos, and documents with captions
- `send_audio_message` - Send voice messages (OGG Opus format)
- `download_media` - Download media attachments from messages
- `send_typing` - Send typing indicators
- `mark_read` - Mark messages as read (blue ticks)
- `react_to_message` - Add emoji reactions to messages
- `delete_message` - Delete messages for everyone
- `reply_to_message` - Quote-reply to messages
- `edit_message` - Edit sent messages
- `send_location` - Send location pins
- `set_presence` - Set online/offline status
- `subscribe_presence` - Subscribe to contact presence updates
- `set_disappearing_timer` - Configure disappearing messages
- `create_poll` - Create polls with 2-12 options

#### MCP Tools - Contacts & Groups
- `is_on_whatsapp` - Check if phone numbers are registered
- `get_profile_picture` - Get contact profile picture URL
- `get_blocklist` - List blocked contacts
- `update_blocklist` - Block/unblock contacts
- `list_groups` - List all joined WhatsApp groups
- `get_group_info` - Get detailed group info with participants
- `get_group_invite_link` - Get/reset group invite links
- `join_group` - Join groups via invite link
- `list_contacts` - List synced contacts from phone
- `merge_chats` - Merge duplicate LID/@s.whatsapp.net chats

#### Infrastructure
- Go bridge using whatsmeow library for WhatsApp Web API
- SQLite message store with full history sync
- Automatic reconnection with exponential backoff
- QR code authentication flow
- Media download with automatic decryption
- LID (Linked ID) to phone number resolution
- Contact name caching and enrichment

#### Developer Experience
- 695 tests with comprehensive coverage
- Integration tests for bridge HTTP API
- Elixir MCP server with JSON-RPC 2.0 over stdio
- Clean separation between Elixir MCP layer and Go bridge
