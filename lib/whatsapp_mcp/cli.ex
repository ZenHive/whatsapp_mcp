defmodule WhatsappMcp.CLI do
  @moduledoc """
  Command-line interface for WhatsApp MCP server.

  This module serves as the entry point for the escript.
  """

  @doc """
  Entry point for the escript.

  Starts the MCP server and blocks until the process terminates.
  """
  @spec main([String.t()]) :: no_return()
  def main(_args) do
    # Start the MCP server (application is already started but server is not)
    {:ok, _pid} = WhatsappMcp.Server.start_link([])

    # Keep the process alive
    receive do
      :never -> :ok
    end
  end
end
