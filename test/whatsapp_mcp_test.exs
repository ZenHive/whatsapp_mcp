defmodule WhatsappMcpTest do
  use ExUnit.Case

  alias WhatsappMcp.Database
  alias WhatsappMcp.TestSupport.DatabaseFixtures
  alias WhatsappMcp.Tools

  @test_db_path Path.join(System.tmp_dir!(), "whatsapp_mcp_main_test_#{:rand.uniform(1_000_000)}.db")

  setup_all do
    DatabaseFixtures.create_standard_test_database(@test_db_path)
    on_exit(fn -> File.rm(@test_db_path) end)
    :ok
  end

  describe "WhatsappMcp.database_available?/0" do
    test "returns boolean" do
      assert is_boolean(WhatsappMcp.database_available?())
    end
  end

  describe "WhatsappMcp.list_chats/1" do
    test "delegates to Database" do
      assert {:ok, chats} = WhatsappMcp.list_chats(db_path: @test_db_path)
      assert is_list(chats)
    end
  end

  describe "WhatsappMcp.get_messages/1" do
    test "delegates to Database" do
      assert {:ok, msgs} = WhatsappMcp.get_messages(chat_id: "recent@s.whatsapp.net", db_path: @test_db_path)
      assert is_list(msgs)
    end
  end

  describe "WhatsappMcp.search_messages/1" do
    test "delegates to Database" do
      assert {:ok, results} = WhatsappMcp.search_messages(query: "message", db_path: @test_db_path)
      assert is_list(results)
    end
  end

  describe "Tools.list_tools/0" do
    test "returns wrapper tools for lazy discovery" do
      tools = Tools.list_tools()

      assert is_list(tools)
      # Only 3 wrapper tools exposed to minimize token overhead
      assert length(tools) == 3

      tool_names = Enum.map(tools, & &1["name"])
      assert "tool_list" in tool_names
      assert "tool_get" in tool_names
      assert "tool_call" in tool_names
    end

    test "each wrapper tool has required MCP fields" do
      for tool <- Tools.list_tools() do
        assert Map.has_key?(tool, "name")
        assert Map.has_key?(tool, "description")
        assert Map.has_key?(tool, "inputSchema")
      end
    end
  end

  describe "Tools.list_tool_names/0" do
    test "returns all available tool names" do
      tool_names = Tools.list_tool_names()

      assert is_list(tool_names)
      assert length(tool_names) >= 5

      assert "list_chats" in tool_names
      assert "get_messages" in tool_names
      assert "search_messages" in tool_names
      assert "send_message" in tool_names
      assert "send_file" in tool_names
    end
  end

  describe "Tools.call_tool/2" do
    test "unknown tool returns error" do
      result = Tools.call_tool("unknown_tool", %{})
      assert {:error, "Unknown tool: unknown_tool"} = result
    end
  end

  describe "Database.list_chats/1" do
    test "returns error when database does not exist" do
      result = Database.list_chats(db_path: "/nonexistent/path.db")
      assert {:error, _reason} = result
    end
  end

  describe "Database.get_messages/1" do
    test "returns error when chat_id or chat_name not provided" do
      assert {:error, :chat_id_or_name_required} = Database.get_messages([])
    end

    test "returns error when database does not exist" do
      result = Database.get_messages(chat_id: "test@s.whatsapp.net", db_path: "/nonexistent/path.db")
      assert {:error, _reason} = result
    end
  end

  describe "Database.search_messages/1" do
    test "returns error when query not provided" do
      assert {:error, :query_required} = Database.search_messages([])
    end

    test "returns error when database does not exist" do
      result = Database.search_messages(query: "test", db_path: "/nonexistent/path.db")
      assert {:error, _reason} = result
    end
  end
end
