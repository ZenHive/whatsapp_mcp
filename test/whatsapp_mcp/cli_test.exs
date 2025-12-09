defmodule WhatsappMcp.CLITest do
  use ExUnit.Case, async: false

  alias WhatsappMcp.CLI
  alias WhatsappMcp.Server

  describe "main/1" do
    test "main/1 function exists and has correct arity" do
      # Ensure module is loaded
      Code.ensure_loaded!(CLI)
      # Verify the function exists with the expected arity
      assert function_exported?(CLI, :main, 1)
    end

    test "main/1 has documentation" do
      # The spec indicates it never returns (blocks forever)
      # We can verify the module compiles with this spec
      {:docs_v1, _, :elixir, _, _, _, docs} = Code.fetch_docs(CLI)

      # Find the main/1 function doc
      main_doc =
        Enum.find(docs, fn
          {{:function, :main, 1}, _, _, _, _} -> true
          _ -> false
        end)

      assert main_doc
    end
  end

  describe "Server.start_link/1" do
    test "server can be started and registers with expected name" do
      # Stop any existing server
      stop_server_if_running()

      # Start the server directly (main/1 blocks forever, so we test the
      # underlying Server.start_link/1 which main/1 calls)
      assert {:ok, pid} = Server.start_link([])
      assert is_pid(pid)

      # Verify server is registered under the expected name
      assert Process.whereis(Server) == pid

      # Clean up
      stop_server_if_running()
    end
  end

  # Helper to stop the server if it's running
  defp stop_server_if_running do
    case Process.whereis(Server) do
      nil -> :ok
      pid -> GenServer.stop(pid, :normal, 1000)
    end
  catch
    :exit, _ -> :ok
  end
end
