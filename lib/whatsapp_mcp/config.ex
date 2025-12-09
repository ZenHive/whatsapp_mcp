defmodule WhatsappMcp.Config do
  @moduledoc """
  Configuration and path detection for WhatsApp MCP server.

  Uses the Go bridge's SQLite database (messages.db) which stores
  messages synced via the WhatsApp Web Multi-Device API.

  The Go bridge must be started manually in a terminal. See `get_help` tool
  or `get_bridge_status` for startup instructions.
  """

  @doc """
  Returns the path to the Go bridge's SQLite database.

  ## Options

    * `:path` - Override the default database path (useful for testing)

  """
  @spec database_path(keyword()) :: String.t()
  def database_path(opts \\ []) do
    case Keyword.get(opts, :path) do
      nil -> default_database_path()
      path -> path
    end
  end

  @doc """
  Checks if the WhatsApp database exists and is readable.
  """
  @spec database_exists?(keyword()) :: boolean()
  def database_exists?(opts \\ []) do
    path = database_path(opts)
    File.exists?(path) and File.regular?(path)
  end

  @doc """
  Returns the path to the bridge source directory.
  """
  @spec bridge_source_path() :: String.t()
  def bridge_source_path do
    Path.join(project_root(), "bridge")
  end

  @doc """
  Returns the path to the compiled bridge binary.
  """
  @spec bridge_binary_path() :: String.t()
  def bridge_binary_path do
    Path.join(bridge_source_path(), "whatsapp-bridge")
  end

  @doc """
  Returns the bridge store directory path (where SQLite databases live).
  """
  @spec bridge_store_path() :: String.t()
  def bridge_store_path do
    Path.join(bridge_source_path(), "store")
  end

  # Private

  defp default_database_path do
    # Path relative to project root: bridge/store/messages.db
    Path.join([project_root(), "bridge", "store", "messages.db"])
  end

  defp project_root do
    # The wrapper script cds to the project directory before running.
    # Use cwd which should be the project root.
    File.cwd!()
  end
end
