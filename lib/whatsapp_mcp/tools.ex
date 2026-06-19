defmodule WhatsappMcp.Tools do
  @moduledoc """
  MCP tool definitions and implementations for WhatsApp access.

  ## Lazy Discovery Pattern

  This module exposes only 3 wrapper tools to MCP clients to minimize token overhead:
  - `tool_list` - List available tools with brief descriptions
  - `tool_get` - Get full schema for a specific tool
  - `tool_call` - Execute a tool by name with parameters

  Full tool schemas are accessed on-demand via `get_tool/1`.

  ## Submodules

  This module delegates to specialized submodules:
  - `WhatsappMcp.Tools.Definitions` - Tool schemas and registry
  - `WhatsappMcp.Tools.Handlers` - Tool implementation logic
  - `WhatsappMcp.Tools.Formatters` - Output formatting
  """

  alias WhatsappMcp.Tools.Definitions
  alias WhatsappMcp.Tools.Handlers

  @doc """
  Returns the list of tools exposed to MCP clients.

  Only returns wrapper tools (tool_list, tool_get, tool_call) to minimize
  token overhead. Use `get_tool/1` to access full tool schemas.
  """
  defdelegate list_tools(), to: Definitions

  @doc """
  Returns the full tool definition for a specific tool.

  Returns nil if the tool is not found.
  """
  defdelegate get_tool(name), to: Definitions

  @doc """
  Checks if a tool name exists in the registry.
  """
  defdelegate tool_exists?(name), to: Definitions

  @doc """
  Returns tool summaries (name + brief description) for discovery.

  Optionally filters by category.
  """
  defdelegate list_tool_summaries(category \\ nil), to: Definitions

  @doc """
  Returns all tool names in the registry.
  """
  defdelegate list_tool_names(), to: Definitions

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
