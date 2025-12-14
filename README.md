# WhatsApp MCP Server

An Elixir MCP (Model Context Protocol) server that provides full read/write access to WhatsApp via an integrated Go bridge.

## Features

**14 MCP tools** for comprehensive WhatsApp integration:

**Reading:**
- `list_chats` - List all chats with pagination
- `get_messages` - Get messages by chat ID or name with pagination
- `search_messages` - Full-text search across all chats
- `search_contacts` - Find contacts by name or phone number
- `get_chat` - Get metadata for a specific chat by JID
- `get_direct_chat_by_contact` - Get chat by phone number
- `get_message_context` - Get surrounding messages for context
- `get_last_interaction` - Find most recent message with a contact
- `get_contact_chats` - List all chats involving a contact

**Writing:**
- `send_message` - Send text messages
- `send_file` - Send images, videos, documents
- `send_audio_message` - Send voice messages (OGG Opus)
- `download_media` - Download media from messages

**Utility:**
- `get_help` - Usage guide with phone formats and workflows

## Requirements

- Elixir 1.15+
- Go 1.21+ (for the WhatsApp bridge)
- A WhatsApp account (will need to scan QR code on first run)

## Installation

```bash
git clone https://github.com/ZenHive/whatsapp_mcp.git
cd whatsapp_mcp
mix deps.get
mix compile
```

## Quick Start

### 1. Start the Go Bridge (first terminal)

```bash
cd bridge
go run .
```

On first run, scan the QR code with your WhatsApp mobile app (Settings > Linked Devices > Link a Device).

The bridge runs an HTTP API on `localhost:8080` and stores messages in `bridge/store/messages.db`.

### 2. Register with Claude Code

```bash
claude mcp add whatsapp /path/to/whatsapp_mcp/bin/whatsapp-mcp
```

Or manually add to your Claude Code MCP settings:

```json
{
  "mcpServers": {
    "whatsapp": {
      "command": "/path/to/whatsapp_mcp/bin/whatsapp-mcp"
    }
  }
}
```

### 3. Restart Claude Code

After registering, restart Claude Code or run `/mcp` to reconnect.

## Available MCP Tools

### Reading Tools

| Tool | Description |
|------|-------------|
| `list_chats` | List all chats with IDs, names, last message. Supports `limit` and `offset` for pagination. |
| `get_messages` | Get messages by `chat_id` (JID) or `chat_name` (partial match). Supports `limit`, `offset`, and `before` timestamp filter. |
| `search_messages` | Full-text search across all chats or within a specific `chat_id`. |
| `search_contacts` | Search contacts by name or phone number. Returns individual contacts only (not groups). |
| `get_chat` | Get metadata for a specific chat by JID. |
| `get_direct_chat_by_contact` | Get chat metadata by phone number. |
| `get_message_context` | Get messages `before` and `after` a specific `message_id` for context. |
| `get_last_interaction` | Get the most recent message with a contact (direct chat or groups). |
| `get_contact_chats` | List all chats involving a contact, including groups where they've sent messages. |

### Writing Tools

| Tool | Description |
|------|-------------|
| `send_message` | Send text message to recipient (phone number or JID). |
| `send_file` | Send image/video/document with optional caption. |
| `send_audio_message` | Send voice message (requires `.ogg` Opus format). |
| `download_media` | Download media from a message. Returns file path on success. |

### Utility Tools

| Tool | Description |
|------|-------------|
| `get_help` | Get usage guide with phone number formats, JID conventions, and recommended workflows. Call this first if unsure how to find contacts. |

## Example Usage in Claude Code

```
"Show me my recent WhatsApp chats"
→ Uses list_chats tool

"What did John say about the meeting?"
→ Uses search_messages with query "meeting"

"Get the last 20 messages from Mom"
→ Uses get_messages with chat_name "Mom"

"Send 'On my way!' to +1234567890"
→ Uses send_message tool

"Find all my contacts named Smith"
→ Uses search_contacts with query "Smith"

"Show me the context around that message"
→ Uses get_message_context with the message_id

"When did I last talk to John?"
→ Uses get_last_interaction tool

"Send this screenshot to the family group"
→ Uses send_file with the image path

"Download that photo John sent"
→ Uses download_media with message_id and chat_jid
```

## Architecture

```
Claude Code ←→ Elixir MCP Server ←→ Go Bridge ←→ WhatsApp Web API
                    │                    │
                    │                    └── bridge/store/messages.db
                    │
                    └── Reads DB for queries, calls HTTP API for sends
```

## Development

```bash
# Run tests (unit tests, no bridge needed)
mix test

# Run integration tests (requires bridge running)
mix test --include integration

# Check code quality
mix credo
mix dialyzer

# Generate docs
mix docs
```

## Troubleshooting

### MCP server fails to connect

1. Ensure the Go bridge is running (`cd bridge && go run .`)
2. Check that `bridge/store/messages.db` exists
3. Restart Claude Code or run `/mcp` to reconnect

### Database not found error

The wrapper script must run from the project directory. Verify:
```bash
cat bin/whatsapp-mcp
# Should show: cd /path/to/whatsapp_mcp && exec mix run --no-halt -e "..."
```

### No messages showing

The Go bridge syncs messages in real-time. Historical messages may not be available until WhatsApp syncs them. Send/receive a few messages to populate the database.

## Privacy

- All data stays local - no external servers
- The Go bridge connects directly to WhatsApp's servers
- Messages are stored in a local SQLite database
- MCP server communicates with Claude Code via stdio only

## Acknowledgments

The Go bridge is based on [whatsapp-mcp](https://github.com/lharries/whatsapp-mcp) by Luke Harries, which uses the excellent [whatsmeow](https://github.com/tulir/whatsmeow) library for WhatsApp Web protocol implementation.

## License

MIT - See [LICENSE](LICENSE) for details.
