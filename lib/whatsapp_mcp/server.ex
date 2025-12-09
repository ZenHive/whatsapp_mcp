defmodule WhatsappMcp.Server do
  @moduledoc """
  MCP (Model Context Protocol) server implementation.

  Implements JSON-RPC 2.0 over stdio for Claude Code integration.
  """

  use GenServer

  alias WhatsappMcp.Tools

  require Logger

  @protocol_version "2024-11-05"
  @server_name "whatsapp-mcp"
  @server_version "0.1.0"

  # Client API

  @doc """
  Starts the MCP server.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    # Start reading from stdin in a linked task.
    # The task is linked so it will be terminated automatically when this
    # GenServer terminates - no need to store the PID in state.
    {:ok, _reader_pid} = Task.start_link(fn -> read_loop() end)

    {:ok, %{initialized: false}}
  end

  @impl true
  def terminate(reason, _state) do
    Logger.info("MCP Server terminating: #{inspect(reason)}")
    # The reader task is linked, so it terminates automatically with us.
    :ok
  end

  @impl true
  def handle_cast({:request, request}, state) do
    response = handle_request(request, state)

    case response do
      {:reply, reply, new_state} ->
        send_response(reply)
        {:noreply, new_state}

      {:noreply, new_state} ->
        {:noreply, new_state}
    end
  end

  # Request handlers

  defp handle_request(%{"method" => "initialize", "id" => id} = _request, state) do
    result = %{
      "protocolVersion" => @protocol_version,
      "capabilities" => %{
        "tools" => %{}
      },
      "serverInfo" => %{
        "name" => @server_name,
        "version" => @server_version
      }
    }

    {:reply, success_response(id, result), %{state | initialized: true}}
  end

  defp handle_request(%{"method" => "notifications/initialized"}, state) do
    # Notification, no response needed
    {:noreply, state}
  end

  defp handle_request(%{"method" => "tools/list", "id" => id}, state) do
    result = %{
      "tools" => Tools.list_tools()
    }

    {:reply, success_response(id, result), state}
  end

  defp handle_request(%{"method" => "tools/call", "id" => id, "params" => params}, state) do
    tool_name = params["name"]
    arguments = params["arguments"] || %{}

    result =
      case Tools.call_tool(tool_name, arguments) do
        {:ok, content} ->
          %{
            "content" => [
              %{
                "type" => "text",
                "text" => content
              }
            ]
          }

        {:error, reason} ->
          %{
            "content" => [
              %{
                "type" => "text",
                "text" => "Error: #{inspect(reason)}"
              }
            ],
            "isError" => true
          }
      end

    {:reply, success_response(id, result), state}
  end

  defp handle_request(%{"method" => method, "id" => id}, state) do
    {:reply, error_response(id, -32_601, "Method not found: #{method}"), state}
  end

  defp handle_request(_request, state) do
    # Notification or malformed request, ignore
    {:noreply, state}
  end

  # Response helpers

  defp success_response(id, result) do
    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "result" => result
    }
  end

  defp error_response(id, code, message) do
    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "error" => %{
        "code" => code,
        "message" => message
      }
    }
  end

  defp send_response(response) do
    json = Jason.encode!(response)
    IO.puts(json)
  end

  # Stdin reader

  defp read_loop do
    case IO.gets("") do
      :eof ->
        Logger.info("EOF received, shutting down")
        System.stop(0)

      {:error, reason} ->
        Logger.error("Error reading stdin: #{inspect(reason)}")
        System.stop(1)

      line when is_binary(line) ->
        line |> String.trim() |> parse_and_dispatch()
        read_loop()
    end
  end

  defp parse_and_dispatch(""), do: :ok

  defp parse_and_dispatch(line) do
    case Jason.decode(line) do
      {:ok, request} ->
        GenServer.cast(__MODULE__, {:request, request})

      {:error, reason} ->
        Logger.warning("Failed to parse JSON: #{inspect(reason)}")
    end
  end
end
