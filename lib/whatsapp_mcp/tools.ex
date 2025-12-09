defmodule WhatsappMcp.Tools do
  @moduledoc """
  MCP tool definitions and implementations for WhatsApp access.

  ## Submodules

  This module delegates to specialized submodules:
  - `WhatsappMcp.Tools.Definitions` - Tool schemas for MCP
  - `WhatsappMcp.Tools.Handlers` - Tool implementation logic
  - `WhatsappMcp.Tools.Formatters` - Output formatting
  """

  alias WhatsappMcp.Tools.Definitions
  alias WhatsappMcp.Tools.Handlers

  @doc """
  Returns the list of available tools in MCP format.
  """
  defdelegate list_tools(), to: Definitions

  @doc """
  Calls a tool by name with the given arguments.

  Returns `{:ok, text}` with formatted result or `{:error, reason}`.
  """
  defdelegate call_tool(name, args), to: Handlers

  @doc """
  Calls tools with options for testing.

  ## Options
  - `:plug` - Plug for testing HTTP calls with Req.Test
  - `:db_path` - Override database path for testing
  """
  defdelegate call_tool(name, args, opts), to: Handlers
end
