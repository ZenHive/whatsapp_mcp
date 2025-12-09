defmodule WhatsappMcp.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # The MCP server is started by CLI escript or manually.
    # The Go bridge must be started separately in a terminal.
    children = []

    opts = [strategy: :one_for_one, name: WhatsappMcp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
