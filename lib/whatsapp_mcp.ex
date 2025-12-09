defmodule WhatsappMcp do
  @moduledoc """
  MCP server for WhatsApp with full read/write access via Go bridge.

  This package provides a Model Context Protocol (MCP) server that allows
  AI assistants like Claude to read and send WhatsApp messages via the
  whatsmeow-based Go bridge.

  ## Prerequisites

  1. Start the Go bridge (first time will show QR code):

      cd bridge && go run main.go

  2. Scan the QR code with your WhatsApp mobile app

  ## Usage with Claude Code

  Add to your `~/.claude/settings.json`:

      {
        "mcpServers": {
          "whatsapp": {
            "command": "mix",
            "args": ["run", "--no-halt"],
            "cwd": "/path/to/whatsapp_mcp"
          }
        }
      }

  ## Available Tools

  - `list_chats` - List all WhatsApp chats with JIDs and last message preview
  - `get_messages` - Get messages from a specific chat
  - `search_messages` - Search messages across all chats

  ## Requirements

  - Go 1.21+ for the bridge
  - WhatsApp account (scan QR code on first run)
  """

  alias WhatsappMcp.Config
  alias WhatsappMcp.Database

  @doc """
  Checks if WhatsApp database is accessible.

  Returns `true` if the database file exists and is readable.
  """
  @spec database_available?() :: boolean()
  def database_available? do
    Config.database_exists?()
  end

  @doc """
  Lists all chats. Convenience wrapper around `WhatsappMcp.Database.list_chats/1`.
  """
  defdelegate list_chats(opts \\ []), to: Database

  @doc """
  Gets messages from a chat. Convenience wrapper around `WhatsappMcp.Database.get_messages/1`.
  """
  defdelegate get_messages(opts), to: Database

  @doc """
  Searches messages. Convenience wrapper around `WhatsappMcp.Database.search_messages/1`.
  """
  defdelegate search_messages(opts), to: Database
end
