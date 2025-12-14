# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

@include ~/.claude/includes/across-instances.md
@include ~/.claude/includes/critical-rules.md
@include ~/.claude/includes/task-prioritization.md
@include ~/.claude/includes/web-command.md
@include ~/.claude/includes/code-style.md
@include ~/.claude/includes/development-philosophy.md
@include ~/.claude/includes/development-commands.md
@include ~/.claude/includes/elixir-patterns.md

## Project Overview

WhatsApp MCP Server - An Elixir MCP (Model Context Protocol) server that provides full read/write access to WhatsApp via an integrated Go bridge. Communicates via JSON-RPC 2.0 over stdio.

**Key capability:** Send and receive WhatsApp messages, search chats, download media - all from Claude Code.

## Project Structure

```
whatsapp_mcp/
├── lib/                    # Elixir MCP server
│   └── whatsapp_mcp/
│       ├── application.ex  # OTP Application supervisor
│       ├── server.ex       # GenServer - MCP protocol (JSON-RPC 2.0 over stdio)
│       ├── tools.ex        # MCP tool definitions and handlers
│       ├── database.ex     # SQLite queries (read from bridge DB)
│       ├── bridge.ex       # HTTP client for Go bridge API
│       ├── config.ex       # Paths and configuration
│       └── cli.ex          # Escript entry point
├── bridge/                 # Go WhatsApp bridge (whatsmeow)
│   ├── main.go             # Bridge server with HTTP API on :8080
│   ├── go.mod
│   └── store/              # SQLite databases + downloaded media (gitignored)
├── scripts/
│   └── clean_bridge_store.sh  # Reset bridge data for full resync
├── mix.exs
├── roadmap.md              # Implementation roadmap with tasks
└── README.md
```

## Development Commands

```bash
# Elixir MCP Server
mix deps.get          # Install dependencies
mix compile           # Compile the project
mix test              # Run tests
mix credo             # Static analysis
mix dialyzer          # Type checking
mix run --no-halt     # Run as MCP server

# Go Bridge (run in separate terminal)
cd bridge
go run .        # First run: scan QR code with WhatsApp mobile app

# Reset bridge data (forces full resync, requires new QR scan)
./scripts/clean_bridge_store.sh
```

## Architecture

### Data Flow

```
Claude Code ←→ Elixir MCP Server ←→ Go Bridge ←→ WhatsApp Web API
                    │                    │
                    │                    └── store/messages.db (message history)
                    │
                    └── Reads from messages.db for queries
                    └── Calls HTTP API for send/download operations
```

### Go Bridge HTTP API (localhost:8080)

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/health` | GET | Check connection status, get phone/name |
| `/api/send` | POST | Send message or file |
| `/api/download` | POST | Download media from message |

### Database Schema (bridge/store/messages.db)

**chats table:**
- `jid` (TEXT PRIMARY KEY) - Chat identifier (e.g., `12025551234@s.whatsapp.net`)
- `name` (TEXT) - Contact or group name
- `last_message_time` (TIMESTAMP)

**messages table:**
- `id` (TEXT) - Message ID
- `chat_jid` (TEXT) - Foreign key to chats
- `sender` (TEXT) - Sender's phone/JID
- `content` (TEXT) - Message text
- `timestamp` (TIMESTAMP) - Unix timestamp
- `is_from_me` (BOOLEAN)
- `media_type` (TEXT) - "image", "video", "audio", "document", or null
- `filename` (TEXT)
- `url`, `media_key`, `file_sha256`, `file_enc_sha256`, `file_length` - Media download info

## MCP Tools

### Reading Tools
| Tool | Description |
|------|-------------|
| `list_chats` | List chats with IDs, names, last message. Supports pagination via `limit`/`offset`. |
| `get_messages` | Fetch messages by `chat_id` or `chat_name`. Supports pagination and `before` timestamp filter. |
| `search_messages` | Full-text search across chats or within a specific `chat_id`. |
| `search_contacts` | Search contacts by name/phone. Returns individual contacts only (not groups). |
| `get_chat` | Get single chat metadata by JID. |
| `get_direct_chat_by_contact` | Get chat metadata by phone number. |
| `get_message_context` | Get messages before/after a target message for context. |
| `get_last_interaction` | Get most recent message with a contact (direct or in groups). |
| `get_contact_chats` | List all chats involving a contact, including groups. |

### Writing Tools
| Tool | Description |
|------|-------------|
| `send_message` | Send text message to recipient (phone or JID). |
| `send_file` | Send image/video/document with optional caption. |
| `send_audio_message` | Send voice message (.ogg Opus format required). |
| `download_media` | Download media from message. Returns file path. |
| `create_poll` | Create and send a poll with 2-12 options. Supports single-choice (max_selections=1) or multi-choice. |

### Group Tools
| Tool | Description |
|------|-------------|
| `list_groups` | List all joined WhatsApp groups with JIDs, names, topics, and participant counts. |
| `get_group_info` | Get detailed group info including all participants and their roles (admin/member). |
| `get_group_invite_link` | Get or reset group invite link (admin only). Use `reset: true` to invalidate old links. |
| `join_group` | Join a group via invite link. Accepts full URL or just the invite code. |
| `create_group` | Create a new group with initial members. Group names limited to 25 characters. |
| `leave_group` | Leave a group. |
| `update_group_name` | Update group name (max 25 chars, admin only). |
| `update_group_description` | Update or clear group description (admin only). |
| `update_group_settings` | Update locked (only admins edit info) and announce (only admins send) modes. |
| `manage_group_members` | Add/remove/promote/demote group members (admin only). Action: "add", "remove", "promote", "demote". |

### Newsletter Tools
| Tool | Description |
|------|-------------|
| `list_newsletters` | List subscribed WhatsApp channels/newsletters. |
| `get_newsletter_info` | Get detailed info about a newsletter (subscribers, description, invite link). |
| `get_newsletter_messages` | Read posts from a newsletter. Supports `count` and `before` for pagination. |
| `follow_newsletter` | Subscribe to a newsletter/channel. |
| `unfollow_newsletter` | Unsubscribe from a newsletter/channel. |

### Privacy & Business Tools
| Tool | Description |
|------|-------------|
| `get_privacy_settings` | View all privacy settings (last seen, profile photo, groups, etc.). |
| `set_privacy_setting` | Update a privacy setting. Settings: groupadd, last, status, profile, readreceipts, online, calladd. |
| `get_business_profile` | Get business profile info (address, email, hours, categories). |
| `reject_call` | Reject an incoming WhatsApp call by call_from JID and call_id. |

### Utility Tools
| Tool | Description |
|------|-------------|
| `get_bridge_status` | Check if bridge is running and get connection status (phone, account name). |
| `get_help` | Usage guide with phone formats, JID conventions, and workflows. **Call this first if unsure how to find a contact.** |

### Phone Number Format & JIDs (Important!)

WhatsApp uses JIDs internally. When searching or sending:
- Strip all formatting: `+60 18-252 3837` → `14155555678`
- Remove plus sign, spaces, dashes, parentheses
- Include country code without the `+`

**JID formats:**
- `{phone}@s.whatsapp.net` - Traditional individual chats
- `{id}@lid` - Linked ID format (newer WhatsApp accounts)
- `{id}@g.us` - Group chats

**Best approach:**
1. Use `search_contacts` or `search_messages` with part of the name
2. Use the returned JID exactly as-is (don't modify it)
3. If `search_contacts` doesn't find someone, try `search_messages` instead

## Key Implementation Details

- **Database path:** `bridge/store/messages.db` (Go bridge's SQLite)
- **Bridge API:** `http://localhost:8080/api`
- **Timestamps:** Unix epoch (seconds since Jan 1, 1970)
- **JID format:** `{phone}@s.whatsapp.net` (individual) or `{id}@g.us` (group)
- **Read-only DB access:** All Exqlite connections use `mode: :readonly`
- **HTTP client:** Req library for bridge API calls

## Testing

**Test commands:**
```bash
mix test                              # Unit tests only (fast, no bridge needed)
mix test --include integration        # + read-only bridge tests (needs bridge running)
mix test --include sends_message      # + sends real WhatsApp messages (careful!)
```

**Test structure:**
- Unit tests use `Req.Test` for HTTP mocking (no external dependencies)
- Integration tests tagged with `@moduletag :integration`
- Send tests tagged with `@describetag :sends_message` (excluded by default)

**Running integration tests:**
1. Start the Go bridge (`cd bridge && go run .`)
2. Ensure QR code is scanned and bridge is connected
3. Run `mix test --include integration`

## Roadmap

All 13 tasks from `roadmap.md` are **complete**:
1. ✅ Foundation (HTTP client, DB schema switch)
2. ✅ Send features (send_message, send_file, send_audio)
3. ✅ Media download
4. ✅ Enhanced queries (contacts, context, pagination)
5. ✅ Polish (tests, docs)


Check todays date, to avoid searching in the wrong year.
