# WhatsApp MCP Server

An Elixir MCP (Model Context Protocol) server that provides full read/write access to WhatsApp via an integrated Go bridge.

## Features

**50+ WhatsApp tools** exposed via lazy discovery pattern for minimal token overhead:

The MCP server exposes 3 meta-tools that provide on-demand access to all WhatsApp features:
- `tool_list` - List available tools with brief descriptions
- `tool_get` - Get full schema for a specific tool
- `tool_call` - Execute any tool by name

This reduces token overhead by ~90% compared to exposing all tool schemas upfront.

**Available tool categories:**

**Reading:** `list_chats`, `get_messages`, `search_messages`, `search_contacts`, `get_chat`, `get_direct_chat_by_contact`, `get_message_context`, `get_last_interaction`, `get_contact_chats`

**Writing:** `send_message`, `send_file`, `send_audio_message`, `download_media`, `create_poll`, `send_typing`, `mark_read`, `react_to_message`, `reply_to_message`, `edit_message`, `delete_message`, `send_location`

**Groups:** `list_groups`, `get_group_info`, `get_group_invite_link`, `join_group`, `create_group`, `leave_group`, `update_group_name`, `update_group_description`, `update_group_settings`, `manage_group_members`

**Newsletters:** `list_newsletters`, `get_newsletter_info`, `get_newsletter_messages`, `follow_newsletter`, `unfollow_newsletter`

**Privacy:** `get_privacy_settings`, `set_privacy_setting`, `get_blocklist`, `update_blocklist`, `set_disappearing_timer`, `set_presence`, `subscribe_presence`

**Utility:** `get_bridge_status`, `get_help`, `is_on_whatsapp`, `get_profile_picture`, `get_business_profile`, `list_contacts`, `merge_chats`, `reject_call`

## Requirements

- **Elixir 1.15+** with Erlang/OTP 26+
- **Go 1.25+** (for the WhatsApp bridge — see `bridge/go.mod`)
- **SQLite** (system library — Exqlite bundles its own, but `gcc`/`clang` is needed to build the NIF on first compile)
- A **WhatsApp account** (you'll scan a QR code on first bridge run)

### Installing the toolchains

**macOS (Homebrew):**

```bash
brew install elixir go sqlite
```

**asdf (multi-version manager, recommended for matching exact versions):**

```bash
asdf plugin add elixir
asdf plugin add erlang
asdf plugin add golang
asdf install   # reads .tool-versions if present
```

**Linux (Debian/Ubuntu):**

```bash
sudo apt-get install elixir erlang-dev golang-go sqlite3 build-essential
```

## Installation

Clone the repo and install both stacks' dependencies:

```bash
git clone https://github.com/ZenHive/whatsapp_mcp.git
cd whatsapp_mcp

# 1. Elixir MCP server dependencies
mix deps.get
mix compile

# 2. Go bridge dependencies
cd bridge
go mod download
go build -o whatsapp-bridge .
cd ..
```

`go build` is optional — `go run .` (used below) compiles on the fly. Building once up front gives you a `bridge/whatsapp-bridge` binary you can launch directly.

## Running the Two Servers

This project has **two long-running processes** that must both be alive for the MCP tools to work:

1. **Go bridge** — talks to WhatsApp Web, persists messages to SQLite, exposes an HTTP API on `localhost:8080`
2. **Elixir MCP server** — speaks JSON-RPC 2.0 over stdio to Claude Code, reads the SQLite DB, and calls the bridge's HTTP API for sends/downloads

The Go bridge runs continuously in its own terminal. The Elixir MCP server is typically launched **automatically by Claude Code** (via `bin/whatsapp-mcp`) — you don't run it by hand unless debugging.

### 1. Start the Go Bridge (terminal 1, leave running)

```bash
cd bridge
go run .
# or, if you ran `go build` above:
./whatsapp-bridge
```

On first run, scan the QR code printed to the terminal with your WhatsApp mobile app:
**Settings → Linked Devices → Link a Device**.

The bridge:
- Listens on `http://localhost:8080`
- Stores message history in `bridge/store/messages.db`
- Stores WhatsApp session credentials in `bridge/store/whatsapp.db` (so you only scan the QR once)
- Downloads media into `bridge/store/`

Keep this process running. If you stop and restart it, the session is preserved — no new QR scan needed unless `bridge/store/whatsapp.db` is deleted.

**To force a full resync (re-scan QR):**

```bash
./scripts/clean_bridge_store.sh
```

### 2. Register the Elixir MCP Server with Claude Code

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

Claude Code will spawn the Elixir MCP server on demand and pipe JSON-RPC over its stdio. You don't need a second terminal for it.

### 3. Restart Claude Code

After registering, restart Claude Code or run `/mcp` to reconnect.

### Running the Elixir MCP server manually (debugging only)

If you want to drive the MCP server by hand (e.g. piping JSON-RPC for testing):

```bash
./bin/whatsapp-mcp
# or
mix run --no-halt -e "WhatsappMcp.Server.start_link([])"
```

## Using the MCP Tools

The server uses a **lazy discovery pattern** - instead of exposing 50+ tool schemas, it exposes 3 wrapper tools:

| Wrapper Tool | Description |
|--------------|-------------|
| `tool_list` | List available tools with brief descriptions. Optionally filter by category. |
| `tool_get` | Get full JSON schema for a specific tool (parameters, types, descriptions). |
| `tool_call` | Execute a tool by name with arguments. |

**AI workflow:**
1. `tool_list` → See what's available
2. `tool_get("send_message")` → Get full schema if needed
3. `tool_call("send_message", {"recipient": "...", "message": "..."})` → Execute

**Tip:** Call `tool_call("get_help", {})` for phone number formats, JID conventions, and usage workflows.

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
