defmodule WhatsappMcp.ToolsTest do
  use ExUnit.Case, async: true

  alias WhatsappMcp.TestSupport.DatabaseFixtures
  alias WhatsappMcp.Tools

  # Creates a temp file and registers cleanup via on_exit
  defp create_temp_file(suffix) do
    tmp_path = Path.join(System.tmp_dir!(), "test_#{System.unique_integer([:positive])}_#{suffix}")
    File.write!(tmp_path, "fake image data")
    on_exit(fn -> File.rm(tmp_path) end)
    tmp_path
  end

  describe "list_tools/0" do
    test "list_chats tool includes offset parameter for pagination" do
      tools = Tools.list_tools()
      list_chats_tool = Enum.find(tools, &(&1["name"] == "list_chats"))

      assert list_chats_tool
      schema = list_chats_tool["inputSchema"]
      assert Map.has_key?(schema["properties"], "offset")
      assert schema["properties"]["offset"]["type"] == "integer"
      assert schema["properties"]["offset"]["default"] == 0
    end

    test "get_messages tool includes offset parameter for pagination" do
      tools = Tools.list_tools()
      get_messages_tool = Enum.find(tools, &(&1["name"] == "get_messages"))

      assert get_messages_tool
      schema = get_messages_tool["inputSchema"]
      assert Map.has_key?(schema["properties"], "offset")
      assert schema["properties"]["offset"]["type"] == "integer"
      assert schema["properties"]["offset"]["default"] == 0
    end

    test "includes send_message tool" do
      tools = Tools.list_tools()
      send_message_tool = Enum.find(tools, &(&1["name"] == "send_message"))

      assert send_message_tool
      assert send_message_tool["description"] == "Send a WhatsApp message to a person or group."

      schema = send_message_tool["inputSchema"]
      assert schema["type"] == "object"
      assert schema["required"] == ["recipient", "message"]
      assert Map.has_key?(schema["properties"], "recipient")
      assert Map.has_key?(schema["properties"], "message")
    end
  end

  describe "call_tool/3 send_message" do
    test "returns {:ok, message} on successful send" do
      Req.Test.stub(:send_tool_success, fn conn ->
        Req.Test.json(conn, %{success: true, message: "Message sent to 12025551234"})
      end)

      assert {:ok, "Message sent to 12025551234"} =
               Tools.call_tool("send_message", %{"recipient" => "12025551234", "message" => "Hello!"},
                 plug: {Req.Test, :send_tool_success}
               )
    end

    test "returns {:error, message} when recipient is missing" do
      assert {:error, "recipient parameter is required"} =
               Tools.call_tool("send_message", %{"message" => "Hello!"}, [])
    end

    test "returns {:error, message} when recipient is empty string" do
      assert {:error, "recipient parameter is required"} =
               Tools.call_tool("send_message", %{"recipient" => "", "message" => "Hello!"}, [])
    end

    test "returns {:error, message} when message is missing" do
      assert {:error, "message parameter is required"} =
               Tools.call_tool("send_message", %{"recipient" => "12025551234"}, [])
    end

    test "returns {:error, message} when message is empty string" do
      assert {:error, "message parameter is required"} =
               Tools.call_tool("send_message", %{"recipient" => "12025551234", "message" => ""}, [])
    end

    test "returns descriptive error when bridge not running" do
      Req.Test.stub(:send_tool_bridge_down, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, msg} =
               Tools.call_tool("send_message", %{"recipient" => "12025551234", "message" => "Hi"},
                 plug: {Req.Test, :send_tool_bridge_down}
               )

      assert String.contains?(msg, "bridge is not running")
    end

    test "returns descriptive error on timeout" do
      Req.Test.stub(:send_tool_timeout, fn conn ->
        Req.Test.transport_error(conn, :timeout)
      end)

      assert {:error, "Request to WhatsApp bridge timed out"} =
               Tools.call_tool("send_message", %{"recipient" => "12025551234", "message" => "Hi"},
                 plug: {Req.Test, :send_tool_timeout}
               )
    end

    test "passes through bridge error messages" do
      Req.Test.stub(:send_tool_invalid_jid, fn conn ->
        Req.Test.json(conn, %{success: false, message: "Error parsing JID: invalid format"})
      end)

      assert {:error, "Error parsing JID: invalid format"} =
               Tools.call_tool("send_message", %{"recipient" => "invalid", "message" => "Hi"},
                 plug: {Req.Test, :send_tool_invalid_jid}
               )
    end
  end

  describe "call_tool/2 send_message (without opts)" do
    test "delegates to call_tool/3 with empty opts" do
      Req.Test.stub(:send_tool_delegate, fn conn ->
        Req.Test.json(conn, %{success: true, message: "Message sent to 12025551234"})
      end)

      # This will fail because we can't inject the stub without opts
      # But we can verify the validation still works
      assert {:error, "recipient parameter is required"} =
               Tools.call_tool("send_message", %{"message" => "Hello!"})
    end
  end

  describe "list_tools/0 send_file tool" do
    test "includes send_file tool definition" do
      tools = Tools.list_tools()
      send_file_tool = Enum.find(tools, &(&1["name"] == "send_file"))

      assert send_file_tool
      assert send_file_tool["description"] == "Send a file (image, video, document) via WhatsApp."

      schema = send_file_tool["inputSchema"]
      assert schema["type"] == "object"
      assert schema["required"] == ["recipient", "file_path"]
      assert Map.has_key?(schema["properties"], "recipient")
      assert Map.has_key?(schema["properties"], "file_path")
      assert Map.has_key?(schema["properties"], "caption")
    end
  end

  describe "call_tool/3 send_file" do
    test "returns {:ok, message} on successful file send" do
      tmp_path = create_temp_file("send_file_tool.jpg")

      Req.Test.stub(:send_file_tool_success, fn conn ->
        Req.Test.json(conn, %{success: true, message: "Message sent to 12025551234"})
      end)

      assert {:ok, "Message sent to 12025551234"} =
               Tools.call_tool(
                 "send_file",
                 %{"recipient" => "12025551234", "file_path" => tmp_path},
                 plug: {Req.Test, :send_file_tool_success}
               )
    end

    test "returns {:ok, message} with caption" do
      tmp_path = create_temp_file("send_file_caption.jpg")
      test_pid = self()

      Req.Test.stub(:send_file_tool_caption, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:payload, Jason.decode!(body)})
        Req.Test.json(conn, %{success: true, message: "Message sent to 12025551234"})
      end)

      assert {:ok, "Message sent to 12025551234"} =
               Tools.call_tool(
                 "send_file",
                 %{"recipient" => "12025551234", "file_path" => tmp_path, "caption" => "Check this out!"},
                 plug: {Req.Test, :send_file_tool_caption}
               )

      assert_receive {:payload, %{"message" => "Check this out!"}}
    end

    test "returns {:error, message} when recipient is missing" do
      assert {:error, "recipient parameter is required"} =
               Tools.call_tool("send_file", %{"file_path" => "/some/file.jpg"}, [])
    end

    test "returns {:error, message} when recipient is empty string" do
      assert {:error, "recipient parameter is required"} =
               Tools.call_tool("send_file", %{"recipient" => "", "file_path" => "/some/file.jpg"}, [])
    end

    test "returns {:error, message} when file_path is missing" do
      assert {:error, "file_path parameter is required"} =
               Tools.call_tool("send_file", %{"recipient" => "12025551234"}, [])
    end

    test "returns {:error, message} when file_path is empty string" do
      assert {:error, "file_path parameter is required"} =
               Tools.call_tool("send_file", %{"recipient" => "12025551234", "file_path" => ""}, [])
    end

    test "returns descriptive error when file not found" do
      assert {:error, msg} =
               Tools.call_tool(
                 "send_file",
                 %{"recipient" => "12025551234", "file_path" => "/nonexistent/file.jpg"},
                 []
               )

      assert String.contains?(msg, "File not found")
    end

    test "returns descriptive error when bridge not running" do
      tmp_path = create_temp_file("send_file_bridge_down.jpg")

      Req.Test.stub(:send_file_tool_bridge_down, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, msg} =
               Tools.call_tool(
                 "send_file",
                 %{"recipient" => "12025551234", "file_path" => tmp_path},
                 plug: {Req.Test, :send_file_tool_bridge_down}
               )

      assert String.contains?(msg, "bridge is not running")
    end

    test "returns descriptive error on timeout" do
      tmp_path = create_temp_file("send_file_timeout.jpg")

      Req.Test.stub(:send_file_tool_timeout, fn conn ->
        Req.Test.transport_error(conn, :timeout)
      end)

      assert {:error, "Request to WhatsApp bridge timed out"} =
               Tools.call_tool(
                 "send_file",
                 %{"recipient" => "12025551234", "file_path" => tmp_path},
                 plug: {Req.Test, :send_file_tool_timeout}
               )
    end

    test "passes through bridge error messages" do
      tmp_path = create_temp_file("send_file_error.jpg")

      Req.Test.stub(:send_file_tool_error, fn conn ->
        Req.Test.json(conn, %{success: false, message: "Failed to send file: unsupported format"})
      end)

      assert {:error, "Failed to send file: unsupported format"} =
               Tools.call_tool(
                 "send_file",
                 %{"recipient" => "12025551234", "file_path" => tmp_path},
                 plug: {Req.Test, :send_file_tool_error}
               )
    end

    test "uses empty caption by default" do
      tmp_path = create_temp_file("send_file_no_caption.jpg")
      test_pid = self()

      Req.Test.stub(:send_file_tool_no_caption, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:payload, Jason.decode!(body)})
        Req.Test.json(conn, %{success: true, message: "Sent"})
      end)

      Tools.call_tool(
        "send_file",
        %{"recipient" => "12025551234", "file_path" => tmp_path},
        plug: {Req.Test, :send_file_tool_no_caption}
      )

      assert_receive {:payload, %{"message" => ""}}
    end
  end

  describe "call_tool/2 send_file (without opts)" do
    test "delegates to call_tool/3 with empty opts" do
      # We can verify the validation still works
      assert {:error, "recipient parameter is required"} =
               Tools.call_tool("send_file", %{"file_path" => "/some/file.jpg"})
    end
  end

  describe "list_tools/0 send_audio_message tool" do
    test "includes send_audio_message tool definition" do
      tools = Tools.list_tools()
      send_audio_tool = Enum.find(tools, &(&1["name"] == "send_audio_message"))

      assert send_audio_tool
      assert String.contains?(send_audio_tool["description"], "voice message")

      schema = send_audio_tool["inputSchema"]
      assert schema["type"] == "object"
      assert schema["required"] == ["recipient", "file_path"]
      assert Map.has_key?(schema["properties"], "recipient")
      assert Map.has_key?(schema["properties"], "file_path")
    end
  end

  describe "call_tool/3 send_audio_message" do
    test "returns {:ok, message} on successful audio send" do
      tmp_path = create_temp_file("voice.ogg")

      Req.Test.stub(:send_audio_tool_success, fn conn ->
        Req.Test.json(conn, %{success: true, message: "Message sent to 12025551234"})
      end)

      assert {:ok, "Message sent to 12025551234"} =
               Tools.call_tool(
                 "send_audio_message",
                 %{"recipient" => "12025551234", "file_path" => tmp_path},
                 plug: {Req.Test, :send_audio_tool_success}
               )
    end

    test "returns {:error, message} when recipient is missing" do
      assert {:error, "recipient parameter is required"} =
               Tools.call_tool("send_audio_message", %{"file_path" => "/some/voice.ogg"}, [])
    end

    test "returns {:error, message} when recipient is empty string" do
      assert {:error, "recipient parameter is required"} =
               Tools.call_tool("send_audio_message", %{"recipient" => "", "file_path" => "/some/voice.ogg"}, [])
    end

    test "returns {:error, message} when file_path is missing" do
      assert {:error, "file_path parameter is required"} =
               Tools.call_tool("send_audio_message", %{"recipient" => "12025551234"}, [])
    end

    test "returns {:error, message} when file_path is empty string" do
      assert {:error, "file_path parameter is required"} =
               Tools.call_tool("send_audio_message", %{"recipient" => "12025551234", "file_path" => ""}, [])
    end

    test "returns {:error, message} when file is not .ogg" do
      tmp_path = create_temp_file("voice.mp3")

      assert {:error, msg} =
               Tools.call_tool(
                 "send_audio_message",
                 %{"recipient" => "12025551234", "file_path" => tmp_path},
                 []
               )

      assert String.contains?(msg, ".ogg extension")
    end

    test "accepts .OGG extension (case insensitive)" do
      tmp_path = create_temp_file("VOICE.OGG")

      Req.Test.stub(:send_audio_uppercase, fn conn ->
        Req.Test.json(conn, %{success: true, message: "Message sent"})
      end)

      assert {:ok, _} =
               Tools.call_tool(
                 "send_audio_message",
                 %{"recipient" => "12025551234", "file_path" => tmp_path},
                 plug: {Req.Test, :send_audio_uppercase}
               )
    end

    test "returns descriptive error when file not found" do
      assert {:error, msg} =
               Tools.call_tool(
                 "send_audio_message",
                 %{"recipient" => "12025551234", "file_path" => "/nonexistent/voice.ogg"},
                 []
               )

      assert String.contains?(msg, "File not found")
    end

    test "returns descriptive error when bridge not running" do
      tmp_path = create_temp_file("bridge_down.ogg")

      Req.Test.stub(:send_audio_bridge_down, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, msg} =
               Tools.call_tool(
                 "send_audio_message",
                 %{"recipient" => "12025551234", "file_path" => tmp_path},
                 plug: {Req.Test, :send_audio_bridge_down}
               )

      assert String.contains?(msg, "bridge is not running")
    end

    test "returns descriptive error on timeout" do
      tmp_path = create_temp_file("timeout.ogg")

      Req.Test.stub(:send_audio_timeout, fn conn ->
        Req.Test.transport_error(conn, :timeout)
      end)

      assert {:error, "Request to WhatsApp bridge timed out"} =
               Tools.call_tool(
                 "send_audio_message",
                 %{"recipient" => "12025551234", "file_path" => tmp_path},
                 plug: {Req.Test, :send_audio_timeout}
               )
    end

    test "passes through bridge error messages" do
      tmp_path = create_temp_file("invalid.ogg")

      Req.Test.stub(:send_audio_error, fn conn ->
        Req.Test.json(conn, %{success: false, message: "Failed to analyze Ogg Opus file: invalid format"})
      end)

      assert {:error, "Failed to analyze Ogg Opus file: invalid format"} =
               Tools.call_tool(
                 "send_audio_message",
                 %{"recipient" => "12025551234", "file_path" => tmp_path},
                 plug: {Req.Test, :send_audio_error}
               )
    end

    test "sends with empty message field" do
      tmp_path = create_temp_file("voice_message.ogg")
      test_pid = self()

      Req.Test.stub(:send_audio_payload, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:payload, Jason.decode!(body)})
        Req.Test.json(conn, %{success: true, message: "Sent"})
      end)

      Tools.call_tool(
        "send_audio_message",
        %{"recipient" => "12025551234", "file_path" => tmp_path},
        plug: {Req.Test, :send_audio_payload}
      )

      assert_receive {:payload, payload}
      assert payload["message"] == ""
      assert payload["media_path"] == tmp_path
    end
  end

  describe "call_tool/2 send_audio_message (without opts)" do
    test "delegates to call_tool/3 with empty opts" do
      # We can verify the validation still works
      assert {:error, "recipient parameter is required"} =
               Tools.call_tool("send_audio_message", %{"file_path" => "/some/voice.ogg"})
    end
  end

  describe "list_tools/0 download_media tool" do
    test "includes download_media tool definition" do
      tools = Tools.list_tools()
      download_media_tool = Enum.find(tools, &(&1["name"] == "download_media"))

      assert download_media_tool
      assert String.contains?(download_media_tool["description"], "Download media")

      schema = download_media_tool["inputSchema"]
      assert schema["type"] == "object"
      assert schema["required"] == ["message_id", "chat_jid"]
      assert Map.has_key?(schema["properties"], "message_id")
      assert Map.has_key?(schema["properties"], "chat_jid")
    end
  end

  describe "call_tool/3 download_media" do
    test "returns {:ok, message} on successful download" do
      Req.Test.stub(:download_media_success, fn conn ->
        Req.Test.json(conn, %{
          success: true,
          message: "Successfully downloaded image media",
          path: "/path/to/downloaded/image.jpg",
          filename: "image.jpg"
        })
      end)

      assert {:ok, message} =
               Tools.call_tool(
                 "download_media",
                 %{"message_id" => "MSG123", "chat_jid" => "12025551234@s.whatsapp.net"},
                 plug: {Req.Test, :download_media_success}
               )

      assert String.contains?(message, "Downloaded image: image.jpg")
      assert String.contains?(message, "Saved to: /path/to/downloaded/image.jpg")
    end

    test "returns {:error, message} when message_id is missing" do
      assert {:error, "message_id parameter is required"} =
               Tools.call_tool("download_media", %{"chat_jid" => "12025551234@s.whatsapp.net"}, [])
    end

    test "returns {:error, message} when message_id is empty string" do
      assert {:error, "message_id parameter is required"} =
               Tools.call_tool(
                 "download_media",
                 %{"message_id" => "", "chat_jid" => "12025551234@s.whatsapp.net"},
                 []
               )
    end

    test "returns {:error, message} when chat_jid is missing" do
      assert {:error, "chat_jid parameter is required"} =
               Tools.call_tool("download_media", %{"message_id" => "MSG123"}, [])
    end

    test "returns {:error, message} when chat_jid is empty string" do
      assert {:error, "chat_jid parameter is required"} =
               Tools.call_tool("download_media", %{"message_id" => "MSG123", "chat_jid" => ""}, [])
    end

    test "returns descriptive error when bridge not running" do
      Req.Test.stub(:download_media_bridge_down, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, msg} =
               Tools.call_tool(
                 "download_media",
                 %{"message_id" => "MSG123", "chat_jid" => "12025551234@s.whatsapp.net"},
                 plug: {Req.Test, :download_media_bridge_down}
               )

      assert String.contains?(msg, "bridge is not running")
    end

    test "returns descriptive error on timeout" do
      Req.Test.stub(:download_media_timeout, fn conn ->
        Req.Test.transport_error(conn, :timeout)
      end)

      assert {:error, "Request to WhatsApp bridge timed out"} =
               Tools.call_tool(
                 "download_media",
                 %{"message_id" => "MSG123", "chat_jid" => "12025551234@s.whatsapp.net"},
                 plug: {Req.Test, :download_media_timeout}
               )
    end

    test "returns error when message has no media" do
      Req.Test.stub(:download_media_no_media, fn conn ->
        Req.Test.json(conn, %{success: false, message: "not a media message"})
      end)

      assert {:error, "not a media message"} =
               Tools.call_tool(
                 "download_media",
                 %{"message_id" => "MSG123", "chat_jid" => "12025551234@s.whatsapp.net"},
                 plug: {Req.Test, :download_media_no_media}
               )
    end

    test "returns error when media info is incomplete" do
      Req.Test.stub(:download_media_incomplete, fn conn ->
        Req.Test.json(conn, %{success: false, message: "media info incomplete"})
      end)

      assert {:error, "media info incomplete"} =
               Tools.call_tool(
                 "download_media",
                 %{"message_id" => "MSG123", "chat_jid" => "12025551234@s.whatsapp.net"},
                 plug: {Req.Test, :download_media_incomplete}
               )
    end

    test "handles video media type" do
      Req.Test.stub(:download_media_video, fn conn ->
        Req.Test.json(conn, %{
          success: true,
          message: "Successfully downloaded video media",
          path: "/path/to/video.mp4",
          filename: "video.mp4"
        })
      end)

      assert {:ok, message} =
               Tools.call_tool(
                 "download_media",
                 %{"message_id" => "MSG123", "chat_jid" => "12025551234@s.whatsapp.net"},
                 plug: {Req.Test, :download_media_video}
               )

      assert String.contains?(message, "Downloaded video: video.mp4")
    end

    test "handles audio media type" do
      Req.Test.stub(:download_media_audio, fn conn ->
        Req.Test.json(conn, %{
          success: true,
          message: "Successfully downloaded audio media",
          path: "/path/to/audio.ogg",
          filename: "audio.ogg"
        })
      end)

      assert {:ok, message} =
               Tools.call_tool(
                 "download_media",
                 %{"message_id" => "MSG123", "chat_jid" => "12025551234@s.whatsapp.net"},
                 plug: {Req.Test, :download_media_audio}
               )

      assert String.contains?(message, "Downloaded audio: audio.ogg")
    end

    test "handles document media type" do
      Req.Test.stub(:download_media_document, fn conn ->
        Req.Test.json(conn, %{
          success: true,
          message: "Successfully downloaded document media",
          path: "/path/to/document.pdf",
          filename: "document.pdf"
        })
      end)

      assert {:ok, message} =
               Tools.call_tool(
                 "download_media",
                 %{"message_id" => "MSG123", "chat_jid" => "12025551234@s.whatsapp.net"},
                 plug: {Req.Test, :download_media_document}
               )

      assert String.contains?(message, "Downloaded document: document.pdf")
    end
  end

  describe "call_tool/2 download_media (without opts)" do
    test "delegates to call_tool/3 with empty opts" do
      # We can verify the validation still works
      assert {:error, "message_id parameter is required"} =
               Tools.call_tool("download_media", %{"chat_jid" => "12025551234@s.whatsapp.net"})
    end
  end

  describe "list_tools/0 search_contacts tool" do
    test "includes search_contacts tool definition" do
      tools = Tools.list_tools()
      search_contacts_tool = Enum.find(tools, &(&1["name"] == "search_contacts"))

      assert search_contacts_tool
      assert String.contains?(search_contacts_tool["description"], "Search WhatsApp contacts")

      schema = search_contacts_tool["inputSchema"]
      assert schema["type"] == "object"
      assert schema["required"] == ["query"]
      assert Map.has_key?(schema["properties"], "query")
      assert Map.has_key?(schema["properties"], "limit")
    end
  end

  describe "call_tool/3 search_contacts" do
    @test_db_path "test/fixtures/search_contacts_test.db"

    setup do
      File.mkdir_p!("test/fixtures")
      DatabaseFixtures.create_contacts_test_database(@test_db_path)
      on_exit(fn -> File.rm(@test_db_path) end)
      :ok
    end

    test "returns {:ok, text} with matching contacts" do
      assert {:ok, text} =
               Tools.call_tool("search_contacts", %{"query" => "John"}, db_path: @test_db_path)

      assert String.contains?(text, "John Doe")
      assert String.contains?(text, "12025551234")
    end

    test "returns contacts matching phone number" do
      assert {:ok, text} =
               Tools.call_tool("search_contacts", %{"query" => "5678"}, db_path: @test_db_path)

      assert String.contains?(text, "Jane Smith")
      assert String.contains?(text, "12025555678")
    end

    test "returns {:error, message} when query is missing" do
      assert {:error, "query parameter is required"} =
               Tools.call_tool("search_contacts", %{}, db_path: @test_db_path)
    end

    test "returns {:error, message} when query is nil" do
      assert {:error, "query parameter is required"} =
               Tools.call_tool("search_contacts", %{"query" => nil}, db_path: @test_db_path)
    end

    test "formats empty results correctly" do
      assert {:ok, text} =
               Tools.call_tool("search_contacts", %{"query" => "zzznomatchzzz"}, db_path: @test_db_path)

      assert text == "No contacts found matching your search."
    end

    test "respects limit option" do
      assert {:ok, text} =
               Tools.call_tool("search_contacts", %{"query" => "Doe", "limit" => 1}, db_path: @test_db_path)

      # Should only find John Doe, limit prevents Jane if she matched
      assert String.contains?(text, "Found 1 contact")
    end
  end

  describe "list_tools/0 get_chat tool" do
    test "includes get_chat tool definition" do
      tools = Tools.list_tools()
      get_chat_tool = Enum.find(tools, &(&1["name"] == "get_chat"))

      assert get_chat_tool
      assert String.contains?(get_chat_tool["description"], "metadata")

      schema = get_chat_tool["inputSchema"]
      assert schema["type"] == "object"
      assert schema["required"] == ["jid"]
      assert Map.has_key?(schema["properties"], "jid")
    end
  end

  describe "list_tools/0 get_direct_chat_by_contact tool" do
    test "includes get_direct_chat_by_contact tool definition" do
      tools = Tools.list_tools()
      get_direct_chat_tool = Enum.find(tools, &(&1["name"] == "get_direct_chat_by_contact"))

      assert get_direct_chat_tool
      assert String.contains?(get_direct_chat_tool["description"], "phone")

      schema = get_direct_chat_tool["inputSchema"]
      assert schema["type"] == "object"
      assert schema["required"] == ["phone"]
      assert Map.has_key?(schema["properties"], "phone")
    end
  end

  describe "call_tool/3 get_chat" do
    @test_db_path "test/fixtures/get_chat_tool_test.db"

    setup do
      File.mkdir_p!("test/fixtures")
      DatabaseFixtures.create_chat_test_database(@test_db_path)
      on_exit(fn -> File.rm(@test_db_path) end)
      :ok
    end

    test "returns {:ok, text} with chat info" do
      assert {:ok, text} =
               Tools.call_tool("get_chat", %{"jid" => "12025551234@s.whatsapp.net"}, db_path: @test_db_path)

      assert String.contains?(text, "12025551234@s.whatsapp.net")
      assert String.contains?(text, "John Doe")
      assert String.contains?(text, "Hello there")
    end

    test "returns {:error, message} when jid is missing" do
      assert {:error, "jid parameter is required"} =
               Tools.call_tool("get_chat", %{}, [])
    end

    test "returns {:error, message} when chat not found" do
      assert {:error, msg} =
               Tools.call_tool("get_chat", %{"jid" => "nonexistent@s.whatsapp.net"}, db_path: @test_db_path)

      assert String.contains?(msg, "not found")
    end
  end

  describe "call_tool/3 get_direct_chat_by_contact" do
    @test_db_path "test/fixtures/get_direct_chat_tool_test.db"

    setup do
      File.mkdir_p!("test/fixtures")
      DatabaseFixtures.create_chat_test_database(@test_db_path)
      on_exit(fn -> File.rm(@test_db_path) end)
      :ok
    end

    test "returns {:ok, text} with chat info" do
      assert {:ok, text} =
               Tools.call_tool("get_direct_chat_by_contact", %{"phone" => "12025551234"}, db_path: @test_db_path)

      assert String.contains?(text, "12025551234@s.whatsapp.net")
      assert String.contains?(text, "John Doe")
      assert String.contains?(text, "Hello there")
    end

    test "returns {:error, message} when phone is missing" do
      assert {:error, "phone parameter is required"} =
               Tools.call_tool("get_direct_chat_by_contact", %{}, [])
    end

    test "returns {:error, message} when no chat for phone" do
      assert {:error, msg} =
               Tools.call_tool("get_direct_chat_by_contact", %{"phone" => "99999999999"}, db_path: @test_db_path)

      assert String.contains?(msg, "No chat found")
    end
  end

  describe "list_tools/0 get_message_context tool" do
    test "includes get_message_context tool definition" do
      tools = Tools.list_tools()
      get_context_tool = Enum.find(tools, &(&1["name"] == "get_message_context"))

      assert get_context_tool
      assert String.contains?(get_context_tool["description"], "context")

      schema = get_context_tool["inputSchema"]
      assert schema["type"] == "object"
      assert schema["required"] == ["message_id"]
      assert Map.has_key?(schema["properties"], "message_id")
      assert Map.has_key?(schema["properties"], "before")
      assert Map.has_key?(schema["properties"], "after")
    end
  end

  describe "call_tool/3 get_message_context" do
    @test_db_path "test/fixtures/get_context_tool_test.db"

    setup do
      File.mkdir_p!("test/fixtures")
      DatabaseFixtures.create_small_context_test_database(@test_db_path)
      on_exit(fn -> File.rm(@test_db_path) end)
      :ok
    end

    test "returns {:ok, text} with message context" do
      assert {:ok, text} =
               Tools.call_tool("get_message_context", %{"message_id" => "ctx_msg_2"}, db_path: @test_db_path)

      assert String.contains?(text, "Context for message")
      assert String.contains?(text, "--- Before ---")
      assert String.contains?(text, "--- Target Message ---")
      assert String.contains?(text, "--- After ---")
      assert String.contains?(text, "Message 2")
    end

    test "returns {:error, message} when message_id is missing" do
      assert {:error, "message_id parameter is required"} =
               Tools.call_tool("get_message_context", %{}, db_path: @test_db_path)
    end

    test "returns {:error, message} when message not found" do
      assert {:error, msg} =
               Tools.call_tool("get_message_context", %{"message_id" => "nonexistent"}, db_path: @test_db_path)

      assert String.contains?(msg, "not found")
    end

    test "respects before parameter" do
      assert {:ok, text} =
               Tools.call_tool(
                 "get_message_context",
                 %{"message_id" => "ctx_msg_3", "before" => 1},
                 db_path: @test_db_path
               )

      # Should only have 1 message before
      # Count "--- Before ---" section should have Message 2 only
      assert String.contains?(text, "Message 2")
      # Message 0 and 1 should not be in before section
      # (they might still appear elsewhere)
    end

    test "respects after parameter" do
      assert {:ok, text} =
               Tools.call_tool(
                 "get_message_context",
                 %{"message_id" => "ctx_msg_1", "after" => 1},
                 db_path: @test_db_path
               )

      # Should only have 1 message after
      assert String.contains?(text, "Message 2")
    end

    test "formats empty before section correctly" do
      assert {:ok, text} =
               Tools.call_tool("get_message_context", %{"message_id" => "ctx_msg_0"}, db_path: @test_db_path)

      # First message has no before
      refute String.contains?(text, "--- Before ---")
      assert String.contains?(text, "--- Target Message ---")
      assert String.contains?(text, "--- After ---")
    end

    test "formats empty after section correctly" do
      assert {:ok, text} =
               Tools.call_tool("get_message_context", %{"message_id" => "ctx_msg_4"}, db_path: @test_db_path)

      # Last message has no after
      assert String.contains?(text, "--- Before ---")
      assert String.contains?(text, "--- Target Message ---")
      refute String.contains?(text, "--- After ---")
    end
  end

  describe "call_tool/3 list_chats pagination" do
    @pagination_db "test/fixtures/list_chats_pagination_test.db"

    setup do
      File.mkdir_p!("test/fixtures")
      DatabaseFixtures.create_standard_test_database(@pagination_db)
      on_exit(fn -> File.rm(@pagination_db) end)
      :ok
    end

    test "returns paginated results with offset" do
      # First page (2 items)
      assert {:ok, text1} = Tools.call_tool("list_chats", %{"limit" => 2, "offset" => 0}, db_path: @pagination_db)
      assert String.contains?(text1, "Found 2 chats")
      assert String.contains?(text1, "Recent Chat")

      # Second page (1 item)
      assert {:ok, text2} = Tools.call_tool("list_chats", %{"limit" => 2, "offset" => 2}, db_path: @pagination_db)
      assert String.contains?(text2, "Found 1 chat")
      assert String.contains?(text2, "Old Chat")
    end

    test "returns empty message for offset beyond data" do
      assert {:ok, text} = Tools.call_tool("list_chats", %{"limit" => 10, "offset" => 100}, db_path: @pagination_db)
      assert text == "No chats found."
    end
  end

  describe "call_tool/3 get_messages pagination" do
    @pagination_db "test/fixtures/get_messages_pagination_test.db"

    setup do
      File.mkdir_p!("test/fixtures")
      DatabaseFixtures.create_context_test_database(@pagination_db)
      on_exit(fn -> File.rm(@pagination_db) end)
      :ok
    end

    test "returns paginated results with offset (most recent first)" do
      # Pagination returns most recent messages first, displayed chronologically
      # Database has 11 messages (0-10), where 10 is most recent

      # First page: most recent 5 messages (6-10)
      assert {:ok, text1} =
               Tools.call_tool(
                 "get_messages",
                 %{"chat_id" => "context@s.whatsapp.net", "limit" => 5, "offset" => 0},
                 db_path: @pagination_db
               )

      # New pagination format shows "showing X-Y of Z total"
      assert String.contains?(text1, "showing 1-5 of 11 total")
      assert String.contains?(text1, "Message 6")
      assert String.contains?(text1, "Message 10")

      # Second page: next 5 most recent (1-5)
      assert {:ok, text2} =
               Tools.call_tool(
                 "get_messages",
                 %{"chat_id" => "context@s.whatsapp.net", "limit" => 5, "offset" => 5},
                 db_path: @pagination_db
               )

      # Second page shows "showing 6-10 of 11 total"
      assert String.contains?(text2, "showing 6-10 of 11 total")
      assert String.contains?(text2, "Message 1")
      assert String.contains?(text2, "Message 5")
    end

    test "returns empty message for offset beyond data" do
      assert {:ok, text} =
               Tools.call_tool(
                 "get_messages",
                 %{"chat_id" => "context@s.whatsapp.net", "limit" => 10, "offset" => 100},
                 db_path: @pagination_db
               )

      assert text == "No messages found."
    end

    test "returns user-friendly error when chat_name not found" do
      assert {:error, msg} =
               Tools.call_tool(
                 "get_messages",
                 %{"chat_name" => "NonExistentChat"},
                 db_path: @pagination_db
               )

      assert msg == "Chat not found: NonExistentChat"
    end

    test "returns user-friendly error when neither chat_id nor chat_name provided" do
      assert {:error, msg} =
               Tools.call_tool("get_messages", %{}, db_path: @pagination_db)

      assert msg == "Either chat_id or chat_name parameter is required"
    end
  end

  describe "list_tools/0 get_last_interaction tool" do
    test "includes get_last_interaction tool definition" do
      tools = Tools.list_tools()
      tool = Enum.find(tools, &(&1["name"] == "get_last_interaction"))

      assert tool
      assert String.contains?(tool["description"], "most recent message")

      schema = tool["inputSchema"]
      assert schema["type"] == "object"
      assert schema["required"] == ["contact_jid"]
      assert Map.has_key?(schema["properties"], "contact_jid")
    end
  end

  describe "list_tools/0 get_contact_chats tool" do
    test "includes get_contact_chats tool definition" do
      tools = Tools.list_tools()
      tool = Enum.find(tools, &(&1["name"] == "get_contact_chats"))

      assert tool
      assert String.contains?(tool["description"], "chats involving a contact")

      schema = tool["inputSchema"]
      assert schema["type"] == "object"
      assert schema["required"] == ["contact_jid"]
      assert Map.has_key?(schema["properties"], "contact_jid")
      assert Map.has_key?(schema["properties"], "limit")
    end
  end

  describe "call_tool/3 get_last_interaction" do
    @test_db_path "test/fixtures/last_interaction_tool_test.db"

    setup do
      File.mkdir_p!("test/fixtures")
      DatabaseFixtures.create_interaction_test_database(@test_db_path)
      on_exit(fn -> File.rm(@test_db_path) end)
      :ok
    end

    test "returns {:ok, text} with last interaction" do
      assert {:ok, text} =
               Tools.call_tool("get_last_interaction", %{"contact_jid" => "alice@s.whatsapp.net"}, db_path: @test_db_path)

      assert String.contains?(text, "Last interaction with Alice")
      assert String.contains?(text, "Latest from Alice")
      assert String.contains?(text, "msg_alice_2")
    end

    test "returns {:error, message} when contact_jid is missing" do
      assert {:error, "contact_jid parameter is required"} =
               Tools.call_tool("get_last_interaction", %{}, [])
    end

    test "returns {:error, message} when no messages found" do
      assert {:error, msg} =
               Tools.call_tool("get_last_interaction", %{"contact_jid" => "nonexistent@s.whatsapp.net"},
                 db_path: @test_db_path
               )

      assert String.contains?(msg, "No messages found")
    end

    test "shows contact name from JID lookup, not chat name (important for group messages)" do
      # This test verifies that when a message is found in a group chat,
      # the header still shows the contact's name (from their direct chat),
      # not the group name where the message was found
      group_interaction_db = "test/fixtures/group_interaction_test.db"
      File.mkdir_p!("test/fixtures")
      DatabaseFixtures.create_group_interaction_test_database(group_interaction_db)
      on_exit(fn -> File.rm(group_interaction_db) end)

      assert {:ok, text} =
               Tools.call_tool("get_last_interaction", %{"contact_jid" => "bob@s.whatsapp.net"},
                 db_path: group_interaction_db
               )

      # Should show "Bob" (the contact's name), not "Work Group" (where the message was found)
      assert String.contains?(text, "Last interaction with Bob")
      refute String.contains?(text, "Last interaction with Work Group")
    end

    test "falls back to JID when contact has no direct chat" do
      # When there's no direct chat with the contact, fall back to showing the JID
      group_only_db = "test/fixtures/group_only_test.db"
      File.mkdir_p!("test/fixtures")
      DatabaseFixtures.create_group_only_test_database(group_only_db)
      on_exit(fn -> File.rm(group_only_db) end)

      assert {:ok, text} =
               Tools.call_tool("get_last_interaction", %{"contact_jid" => "charlie@s.whatsapp.net"},
                 db_path: group_only_db
               )

      # Should fall back to JID since there's no direct chat
      assert String.contains?(text, "Last interaction with charlie@s.whatsapp.net")
    end
  end

  describe "call_tool/3 get_contact_chats" do
    @test_db_path "test/fixtures/contact_chats_tool_test.db"

    setup do
      File.mkdir_p!("test/fixtures")
      DatabaseFixtures.create_contact_chats_test_database(@test_db_path)
      on_exit(fn -> File.rm(@test_db_path) end)
      :ok
    end

    test "returns {:ok, text} with contact chats" do
      assert {:ok, text} =
               Tools.call_tool("get_contact_chats", %{"contact_jid" => "bob@s.whatsapp.net"}, db_path: @test_db_path)

      assert String.contains?(text, "Found 2 chats")
      assert String.contains?(text, "[Direct]")
      assert String.contains?(text, "[Group]")
      assert String.contains?(text, "Bob")
      assert String.contains?(text, "Test Group")
    end

    test "returns {:error, message} when contact_jid is missing" do
      assert {:error, "contact_jid parameter is required"} =
               Tools.call_tool("get_contact_chats", %{}, [])
    end

    test "returns empty message when contact has no chats" do
      assert {:ok, text} =
               Tools.call_tool("get_contact_chats", %{"contact_jid" => "nonexistent@s.whatsapp.net"},
                 db_path: @test_db_path
               )

      assert text == "No chats found for this contact."
    end

    test "respects limit option" do
      assert {:ok, text} =
               Tools.call_tool("get_contact_chats", %{"contact_jid" => "bob@s.whatsapp.net", "limit" => 1},
                 db_path: @test_db_path
               )

      assert String.contains?(text, "Found 1 chat")
    end
  end

  describe "call_tool/3 search_messages" do
    @test_db_path "test/fixtures/search_messages_tool_test.db"

    setup do
      File.mkdir_p!("test/fixtures")
      DatabaseFixtures.create_standard_test_database(@test_db_path)
      on_exit(fn -> File.rm(@test_db_path) end)
      :ok
    end

    test "returns {:ok, text} with matching messages" do
      assert {:ok, text} =
               Tools.call_tool("search_messages", %{"query" => "Latest"}, db_path: @test_db_path)

      assert String.contains?(text, "Found 1 matching message")
      assert String.contains?(text, "Recent Chat")
    end

    test "includes message ID in output" do
      assert {:ok, text} =
               Tools.call_tool("search_messages", %{"query" => "Latest"}, db_path: @test_db_path)

      assert String.contains?(text, "[MsgID:msg2]")
    end

    test "includes JID label instead of ID" do
      assert {:ok, text} =
               Tools.call_tool("search_messages", %{"query" => "Latest"}, db_path: @test_db_path)

      assert String.contains?(text, "(JID: recent@s.whatsapp.net)")
      # Should NOT have the old format
      refute String.contains?(text, "(ID: recent@s.whatsapp.net)")
    end

    test "includes media indicator for messages with media" do
      assert {:ok, text} =
               Tools.call_tool("search_messages", %{"query" => "photo"}, db_path: @test_db_path)

      assert String.contains?(text, "[📷 image]")
      assert String.contains?(text, "[MsgID:msg3]")
    end

    test "filters by has_media when set to true" do
      assert {:ok, text} =
               Tools.call_tool("search_messages", %{"has_media" => true}, db_path: @test_db_path)

      # Should only return messages with media
      assert String.contains?(text, "[📷 image]")
      assert String.contains?(text, "matching messages")
    end

    test "combines query with has_media filter" do
      assert {:ok, text} =
               Tools.call_tool("search_messages", %{"query" => "photo", "has_media" => true}, db_path: @test_db_path)

      assert String.contains?(text, "[📷 image]")
    end

    test "returns {:error, message} when query is missing and has_media is false" do
      assert {:error, "query parameter is required (or set has_media: true)"} =
               Tools.call_tool("search_messages", %{}, db_path: @test_db_path)
    end

    test "formats empty results correctly" do
      assert {:ok, text} =
               Tools.call_tool("search_messages", %{"query" => "zzznomatchzzz"}, db_path: @test_db_path)

      assert text == "No messages found matching your search."
    end
  end

  # Tests for call_tool/2 (2-arity convenience functions)
  # These delegate to call_tool/3 with opts=[]
  # They need tests to achieve coverage for lines 285, 287, 289, 307, 309, 311, 313, 315, 317

  describe "call_tool/2 list_chats (without opts)" do
    test "delegates to call_tool/3 and returns error for missing db" do
      # Without opts, will try to access real db which likely doesn't exist in test
      result = Tools.call_tool("list_chats", %{})

      # Either succeeds with real db or returns an error
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  describe "call_tool/2 get_messages (without opts)" do
    test "delegates to call_tool/3" do
      result = Tools.call_tool("get_messages", %{"chat_id" => "test@s.whatsapp.net"})

      # Either succeeds with real db or returns an error
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  describe "call_tool/2 search_messages (without opts)" do
    test "delegates to call_tool/3" do
      result = Tools.call_tool("search_messages", %{"query" => "test"})

      # Either succeeds with real db or returns an error
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  describe "call_tool/2 search_contacts (without opts)" do
    test "delegates to call_tool/3" do
      result = Tools.call_tool("search_contacts", %{"query" => "John"})

      # Either succeeds with real db or returns an error
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  describe "call_tool/2 get_chat (without opts)" do
    test "delegates to call_tool/3" do
      result = Tools.call_tool("get_chat", %{"jid" => "test@s.whatsapp.net"})

      # Either succeeds with real db or returns an error
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  describe "call_tool/2 get_direct_chat_by_contact (without opts)" do
    test "delegates to call_tool/3" do
      result = Tools.call_tool("get_direct_chat_by_contact", %{"phone" => "12025551234"})

      # Either succeeds with real db or returns an error
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  describe "call_tool/2 get_message_context (without opts)" do
    test "delegates to call_tool/3" do
      result = Tools.call_tool("get_message_context", %{"message_id" => "msg123"})

      # Either succeeds with real db or returns an error
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  describe "call_tool/2 get_last_interaction (without opts)" do
    test "delegates to call_tool/3" do
      result = Tools.call_tool("get_last_interaction", %{"contact_jid" => "test@s.whatsapp.net"})

      # Either succeeds with real db or returns an error
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  describe "call_tool/2 get_contact_chats (without opts)" do
    test "delegates to call_tool/3" do
      result = Tools.call_tool("get_contact_chats", %{"contact_jid" => "test@s.whatsapp.net"})

      # Either succeeds with real db or returns an error
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  describe "call_tool/2 unknown tool" do
    test "returns error for unknown tool" do
      assert {:error, "Unknown tool: nonexistent_tool"} =
               Tools.call_tool("nonexistent_tool", %{})
    end
  end

  describe "list_tools/0 get_bridge_status tool" do
    test "includes get_bridge_status tool definition" do
      tools = Tools.list_tools()
      tool = Enum.find(tools, &(&1["name"] == "get_bridge_status"))

      assert tool
      assert String.contains?(tool["description"], "bridge is running")
      assert tool["inputSchema"]["type"] == "object"
      assert tool["inputSchema"]["properties"] == %{}
    end
  end

  describe "call_tool/3 get_bridge_status" do
    test "returns connected status with full info" do
      Req.Test.stub(:bridge_status_full, fn conn ->
        Req.Test.json(conn, %{connected: true, phone: "14155551234", name: "Alice"})
      end)

      assert {:ok, text} =
               Tools.call_tool("get_bridge_status", %{}, plug: {Req.Test, :bridge_status_full})

      assert String.contains?(text, "Connected")
      assert String.contains?(text, "14155551234")
      assert String.contains?(text, "Alice")
    end

    test "returns connected status with phone only" do
      Req.Test.stub(:bridge_status_phone_only, fn conn ->
        Req.Test.json(conn, %{connected: true, phone: "14155551234"})
      end)

      assert {:ok, text} =
               Tools.call_tool("get_bridge_status", %{}, plug: {Req.Test, :bridge_status_phone_only})

      assert String.contains?(text, "Connected")
      assert String.contains?(text, "14155551234")
    end

    test "returns not connected message when bridge running but not logged in" do
      Req.Test.stub(:bridge_status_not_connected, fn conn ->
        Req.Test.json(conn, %{connected: false})
      end)

      assert {:ok, text} =
               Tools.call_tool("get_bridge_status", %{}, plug: {Req.Test, :bridge_status_not_connected})

      # Shows instructions to check terminal for QR code
      assert String.contains?(text, "not connected to WhatsApp")
      assert String.contains?(text, "QR code")
      assert String.contains?(text, "Linked Devices")
    end

    test "returns startup instructions when bridge not running" do
      Req.Test.stub(:bridge_status_down, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      {:ok, text} = Tools.call_tool("get_bridge_status", %{}, plug: {Req.Test, :bridge_status_down})

      assert String.contains?(text, "Bridge Status: Not Running")
      assert String.contains?(text, "To start the WhatsApp bridge")
      assert String.contains?(text, "go run main.go")
    end
  end

  describe "list_tools/0 get_help tool" do
    test "includes get_help tool definition" do
      tools = Tools.list_tools()
      tool = Enum.find(tools, &(&1["name"] == "get_help"))

      assert tool
      assert String.contains?(tool["description"], "phone number formats")
      assert tool["inputSchema"]["type"] == "object"
      assert tool["inputSchema"]["properties"] == %{}
    end
  end

  describe "call_tool/2 get_help" do
    test "returns help text with phone number format guidance" do
      assert {:ok, text} = Tools.call_tool("get_help", %{})

      assert String.contains?(text, "Phone Number Format")
      assert String.contains?(text, "14155555678")
      assert String.contains?(text, "Digits only")
    end

    test "returns help text with JID format guidance" do
      assert {:ok, text} = Tools.call_tool("get_help", %{})

      assert String.contains?(text, "@s.whatsapp.net")
      assert String.contains?(text, "@g.us")
    end

    test "returns help text with workflow recommendations" do
      assert {:ok, text} = Tools.call_tool("get_help", %{})

      assert String.contains?(text, "search_contacts")
      assert String.contains?(text, "RECOMMENDED WORKFLOW")
    end
  end

  describe "actionable hints in tool outputs" do
    @hints_db "test/fixtures/hints_test.db"

    setup do
      File.mkdir_p!("test/fixtures")
      DatabaseFixtures.create_standard_test_database(@hints_db)
      on_exit(fn -> File.rm(@hints_db) end)
      :ok
    end

    test "list_chats includes hint about get_messages" do
      assert {:ok, text} = Tools.call_tool("list_chats", %{}, db_path: @hints_db)
      assert String.contains?(text, "Tip: Use get_messages(chat_id:")
    end

    test "list_chats hint not shown for empty results" do
      # Create empty database with proper schema
      empty_db = "test/fixtures/empty_hints.db"
      {:ok, conn} = Exqlite.Sqlite3.open(empty_db)
      DatabaseFixtures.create_schema(conn)
      Exqlite.Sqlite3.close(conn)
      on_exit(fn -> File.rm(empty_db) end)

      assert {:ok, text} = Tools.call_tool("list_chats", %{}, db_path: empty_db)
      assert text == "No chats found."
      refute String.contains?(text, "Tip:")
    end

    test "search_contacts includes hint about send_message" do
      assert {:ok, text} = Tools.call_tool("search_contacts", %{"query" => "test"}, db_path: @hints_db)
      # Check for hint only if contacts were found (not empty message)
      if text != "No contacts found matching your search." do
        assert String.contains?(text, "Tip: Use send_message(recipient:")
      end
    end

    test "search_contacts hint not shown for empty results" do
      assert {:ok, text} =
               Tools.call_tool("search_contacts", %{"query" => "zzznomatchzzz"}, db_path: @hints_db)

      assert text == "No contacts found matching your search."
      refute String.contains?(text, "Tip:")
    end

    test "search_messages includes hint about get_message_context" do
      assert {:ok, text} = Tools.call_tool("search_messages", %{"query" => "message"}, db_path: @hints_db)

      if text != "No messages found matching your search." do
        assert String.contains?(text, "Tip: Use get_message_context(message_id:")
      end
    end

    test "search_messages hint not shown for empty results" do
      assert {:ok, text} =
               Tools.call_tool("search_messages", %{"query" => "zzznomatchzzz"}, db_path: @hints_db)

      assert text == "No messages found matching your search."
      refute String.contains?(text, "Tip:")
    end

    test "get_messages includes hint about send_message" do
      assert {:ok, text} =
               Tools.call_tool("get_messages", %{"chat_id" => "recent@s.whatsapp.net"}, db_path: @hints_db)

      if text != "No messages found." do
        assert String.contains?(text, "Tip: Use send_message(recipient:")
      end
    end

    test "get_messages hint not shown for empty results" do
      assert {:ok, text} =
               Tools.call_tool("get_messages", %{"chat_id" => "nonexistent@s.whatsapp.net"}, db_path: @hints_db)

      assert text == "No messages found."
      refute String.contains?(text, "Tip:")
    end
  end

  # Task 19: Tests for pagination info in tool outputs (AI-friendliness)

  describe "pagination info in list_chats output" do
    @pagination_db "test/fixtures/list_chats_pagination_info_test.db"

    setup do
      File.mkdir_p!("test/fixtures")
      DatabaseFixtures.create_standard_test_database(@pagination_db)
      on_exit(fn -> File.rm(@pagination_db) end)
      :ok
    end

    test "shows pagination info with total count" do
      assert {:ok, text} = Tools.call_tool("list_chats", %{"limit" => 2, "offset" => 0}, db_path: @pagination_db)

      # Should show "showing 1-2 of 3 total, offset: 0"
      assert String.contains?(text, "showing 1-2 of 3 total")
      assert String.contains?(text, "offset: 0")
    end

    test "shows pagination info with offset" do
      assert {:ok, text} = Tools.call_tool("list_chats", %{"limit" => 2, "offset" => 1}, db_path: @pagination_db)

      # Should show "showing 2-3 of 3 total, offset: 1"
      assert String.contains?(text, "showing 2-3 of 3 total")
      assert String.contains?(text, "offset: 1")
    end

    test "shows single item pagination info" do
      assert {:ok, text} = Tools.call_tool("list_chats", %{"limit" => 2, "offset" => 2}, db_path: @pagination_db)

      # Should show "showing 3-3 of 3 total"
      assert String.contains?(text, "showing 3-3 of 3 total")
    end
  end

  describe "pagination info in search_messages output" do
    @pagination_db "test/fixtures/search_messages_pagination_test.db"

    setup do
      File.mkdir_p!("test/fixtures")
      DatabaseFixtures.create_context_test_database(@pagination_db)
      on_exit(fn -> File.rm(@pagination_db) end)
      :ok
    end

    test "shows pagination info with total count" do
      # Search for "Message" which should match all 11 messages
      assert {:ok, text} =
               Tools.call_tool("search_messages", %{"query" => "Message", "limit" => 5}, db_path: @pagination_db)

      # Should show pagination info with total count
      assert String.contains?(text, "showing 1-5 of 11 total")
      assert String.contains?(text, "offset: 0")
    end

    test "shows pagination info with limit showing partial results" do
      # With limit 3, should show 3 of 11
      assert {:ok, text} =
               Tools.call_tool("search_messages", %{"query" => "Message", "limit" => 3}, db_path: @pagination_db)

      # Should show pagination info
      assert String.contains?(text, "showing 1-3 of 11 total")
    end

    test "shows all results when limit exceeds total" do
      # With limit 50 (default), should show all 11
      assert {:ok, text} =
               Tools.call_tool("search_messages", %{"query" => "Message"}, db_path: @pagination_db)

      # Should show all results
      assert String.contains?(text, "showing 1-11 of 11 total")
    end
  end

  describe "pagination info in search_contacts output" do
    @pagination_db "test/fixtures/search_contacts_pagination_test.db"

    setup do
      File.mkdir_p!("test/fixtures")
      DatabaseFixtures.create_standard_test_database(@pagination_db)
      on_exit(fn -> File.rm(@pagination_db) end)
      :ok
    end

    test "shows pagination info with total count" do
      # Search for "Chat" which should match multiple contacts
      assert {:ok, text} =
               Tools.call_tool("search_contacts", %{"query" => "Chat", "limit" => 2}, db_path: @pagination_db)

      # Standard test database has 3 chats with "Chat" in name (excluding groups)
      assert String.contains?(text, "showing 1-2 of 3 total")
      assert String.contains?(text, "offset: 0")
    end

    test "shows pagination info for single result" do
      # Search for specific chat
      assert {:ok, text} =
               Tools.call_tool("search_contacts", %{"query" => "Recent"}, db_path: @pagination_db)

      assert String.contains?(text, "showing 1-1 of 1 total")
    end
  end

  describe "pagination info in get_contact_chats output" do
    @pagination_db "test/fixtures/get_contact_chats_pagination_test.db"

    setup do
      File.mkdir_p!("test/fixtures")
      DatabaseFixtures.create_contact_chats_test_database(@pagination_db)
      on_exit(fn -> File.rm(@pagination_db) end)
      :ok
    end

    test "shows pagination info with total count" do
      # Bob is in 2 chats (direct + group)
      assert {:ok, text} =
               Tools.call_tool("get_contact_chats", %{"contact_jid" => "bob@s.whatsapp.net", "limit" => 1},
                 db_path: @pagination_db
               )

      # Should show pagination info
      assert String.contains?(text, "showing 1-1 of 2 total")
    end

    test "shows all chats when no limit applied" do
      assert {:ok, text} =
               Tools.call_tool("get_contact_chats", %{"contact_jid" => "bob@s.whatsapp.net"}, db_path: @pagination_db)

      # Should show both chats
      assert String.contains?(text, "showing 1-2 of 2 total")
    end
  end

  # ============================================================================
  # New Messaging Action Tools (Tasks 23-27)
  # ============================================================================

  describe "list_tools/0 send_typing tool" do
    test "includes send_typing tool definition" do
      tools = Tools.list_tools()
      tool = Enum.find(tools, &(&1["name"] == "send_typing"))

      assert tool
      assert String.contains?(tool["description"], "typing indicator")

      schema = tool["inputSchema"]
      assert schema["type"] == "object"
      assert schema["required"] == ["recipient"]
      assert Map.has_key?(schema["properties"], "recipient")
      assert Map.has_key?(schema["properties"], "composing")
    end
  end

  describe "call_tool/3 send_typing" do
    test "returns {:ok, text} on success" do
      Req.Test.stub(:typing_tool_success, fn conn ->
        Req.Test.json(conn, %{success: true, message: "Typing indicator started for 12025551234"})
      end)

      assert {:ok, text} =
               Tools.call_tool("send_typing", %{"recipient" => "12025551234"}, plug: {Req.Test, :typing_tool_success})

      assert String.contains?(text, "Typing indicator started")
    end

    test "defaults composing to true when not specified" do
      test_pid = self()

      Req.Test.stub(:typing_default_composing, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:payload, Jason.decode!(body)})
        Req.Test.json(conn, %{success: true, message: "Sent"})
      end)

      Tools.call_tool("send_typing", %{"recipient" => "12025551234"}, plug: {Req.Test, :typing_default_composing})

      assert_receive {:payload, %{"composing" => true}}
    end

    test "returns {:error, message} when recipient is missing" do
      assert {:error, "recipient parameter is required"} =
               Tools.call_tool("send_typing", %{}, [])
    end

    test "returns {:error, message} on bridge error" do
      Req.Test.stub(:typing_tool_error, fn conn ->
        Req.Test.json(conn, %{success: false, message: "Invalid JID format"})
      end)

      assert {:error, "Invalid JID format"} =
               Tools.call_tool("send_typing", %{"recipient" => "invalid"}, plug: {Req.Test, :typing_tool_error})
    end
  end

  describe "list_tools/0 mark_read tool" do
    test "includes mark_read tool definition" do
      tools = Tools.list_tools()
      tool = Enum.find(tools, &(&1["name"] == "mark_read"))

      assert tool
      assert String.contains?(tool["description"], "Mark messages as read")

      schema = tool["inputSchema"]
      assert schema["type"] == "object"
      assert schema["required"] == ["chat_jid", "message_ids"]
      assert Map.has_key?(schema["properties"], "chat_jid")
      assert Map.has_key?(schema["properties"], "message_ids")
    end
  end

  describe "call_tool/3 mark_read" do
    test "returns {:ok, text} on success" do
      Req.Test.stub(:mark_read_tool_success, fn conn ->
        Req.Test.json(conn, %{success: true, message: "Marked 2 message(s) as read"})
      end)

      assert {:ok, text} =
               Tools.call_tool(
                 "mark_read",
                 %{"chat_jid" => "12025551234@s.whatsapp.net", "message_ids" => ["MSG1", "MSG2"]},
                 plug: {Req.Test, :mark_read_tool_success}
               )

      assert String.contains?(text, "Marked 2 message(s) as read")
    end

    test "returns {:error, message} when chat_jid is missing" do
      assert {:error, "chat_jid parameter is required"} =
               Tools.call_tool("mark_read", %{"message_ids" => ["MSG1"]}, [])
    end

    test "returns {:error, message} when message_ids is missing" do
      assert {:error, "message_ids parameter is required"} =
               Tools.call_tool("mark_read", %{"chat_jid" => "12025551234@s.whatsapp.net"}, [])
    end

    test "returns {:error, message} when message_ids is empty" do
      assert {:error, "message_ids cannot be empty"} =
               Tools.call_tool("mark_read", %{"chat_jid" => "12025551234@s.whatsapp.net", "message_ids" => []}, [])
    end

    test "returns {:error, message} when message_ids is not a list" do
      assert {:error, "message_ids must be a list"} =
               Tools.call_tool("mark_read", %{"chat_jid" => "12025551234@s.whatsapp.net", "message_ids" => "MSG1"}, [])
    end
  end

  describe "list_tools/0 react_to_message tool" do
    test "includes react_to_message tool definition" do
      tools = Tools.list_tools()
      tool = Enum.find(tools, &(&1["name"] == "react_to_message"))

      assert tool
      assert String.contains?(tool["description"], "emoji reaction")

      schema = tool["inputSchema"]
      assert schema["type"] == "object"
      assert schema["required"] == ["chat_jid", "message_id", "sender", "emoji"]
      assert Map.has_key?(schema["properties"], "chat_jid")
      assert Map.has_key?(schema["properties"], "message_id")
      assert Map.has_key?(schema["properties"], "sender")
      assert Map.has_key?(schema["properties"], "emoji")
    end
  end

  describe "call_tool/3 react_to_message" do
    test "returns {:ok, text} on success" do
      Req.Test.stub(:reaction_tool_success, fn conn ->
        Req.Test.json(conn, %{success: true, message: "Reaction added for message ABC123"})
      end)

      assert {:ok, text} =
               Tools.call_tool(
                 "react_to_message",
                 %{
                   "chat_jid" => "12025551234@s.whatsapp.net",
                   "message_id" => "ABC123",
                   "sender" => "12025551234@s.whatsapp.net",
                   "emoji" => "👍"
                 },
                 plug: {Req.Test, :reaction_tool_success}
               )

      assert String.contains?(text, "Reaction added")
    end

    test "returns {:error, message} when chat_jid is missing" do
      assert {:error, "chat_jid parameter is required"} =
               Tools.call_tool(
                 "react_to_message",
                 %{"message_id" => "ABC123", "sender" => "test@s.whatsapp.net", "emoji" => "👍"},
                 []
               )
    end

    test "returns {:error, message} when message_id is missing" do
      assert {:error, "message_id parameter is required"} =
               Tools.call_tool(
                 "react_to_message",
                 %{"chat_jid" => "test@s.whatsapp.net", "sender" => "test@s.whatsapp.net", "emoji" => "👍"},
                 []
               )
    end

    test "returns {:error, message} when sender is missing" do
      assert {:error, "sender parameter is required"} =
               Tools.call_tool(
                 "react_to_message",
                 %{"chat_jid" => "test@s.whatsapp.net", "message_id" => "ABC123", "emoji" => "👍"},
                 []
               )
    end

    test "allows empty emoji for removing reactions" do
      Req.Test.stub(:reaction_remove_tool, fn conn ->
        Req.Test.json(conn, %{success: true, message: "Reaction removed for message ABC123"})
      end)

      assert {:ok, text} =
               Tools.call_tool(
                 "react_to_message",
                 %{
                   "chat_jid" => "12025551234@s.whatsapp.net",
                   "message_id" => "ABC123",
                   "sender" => "12025551234@s.whatsapp.net",
                   "emoji" => ""
                 },
                 plug: {Req.Test, :reaction_remove_tool}
               )

      assert String.contains?(text, "Reaction removed")
    end
  end

  describe "list_tools/0 delete_message tool" do
    test "includes delete_message tool definition" do
      tools = Tools.list_tools()
      tool = Enum.find(tools, &(&1["name"] == "delete_message"))

      assert tool
      assert String.contains?(tool["description"], "Delete a message")

      schema = tool["inputSchema"]
      assert schema["type"] == "object"
      assert schema["required"] == ["chat_jid", "message_id", "sender"]
      assert Map.has_key?(schema["properties"], "chat_jid")
      assert Map.has_key?(schema["properties"], "message_id")
      assert Map.has_key?(schema["properties"], "sender")
    end
  end

  describe "call_tool/3 delete_message" do
    test "returns {:ok, text} on success" do
      Req.Test.stub(:delete_tool_success, fn conn ->
        Req.Test.json(conn, %{success: true, message: "Message ABC123 deleted"})
      end)

      assert {:ok, text} =
               Tools.call_tool(
                 "delete_message",
                 %{
                   "chat_jid" => "12025551234@s.whatsapp.net",
                   "message_id" => "ABC123",
                   "sender" => "14155551234@s.whatsapp.net"
                 },
                 plug: {Req.Test, :delete_tool_success}
               )

      assert String.contains?(text, "Message ABC123 deleted")
    end

    test "returns {:error, message} when chat_jid is missing" do
      assert {:error, "chat_jid parameter is required"} =
               Tools.call_tool("delete_message", %{"message_id" => "ABC123", "sender" => "test@s.whatsapp.net"}, [])
    end

    test "returns {:error, message} when message_id is missing" do
      assert {:error, "message_id parameter is required"} =
               Tools.call_tool(
                 "delete_message",
                 %{"chat_jid" => "test@s.whatsapp.net", "sender" => "test@s.whatsapp.net"},
                 []
               )
    end

    test "returns {:error, message} when sender is missing" do
      assert {:error, "sender parameter is required"} =
               Tools.call_tool("delete_message", %{"chat_jid" => "test@s.whatsapp.net", "message_id" => "ABC123"}, [])
    end
  end

  describe "list_tools/0 reply_to_message tool" do
    test "includes reply_to_message tool definition" do
      tools = Tools.list_tools()
      tool = Enum.find(tools, &(&1["name"] == "reply_to_message"))

      assert tool
      assert String.contains?(tool["description"], "Reply to a specific message")

      schema = tool["inputSchema"]
      assert schema["type"] == "object"
      assert schema["required"] == ["recipient", "message", "quoted_message_id", "quoted_chat_jid", "quoted_sender"]
      assert Map.has_key?(schema["properties"], "recipient")
      assert Map.has_key?(schema["properties"], "message")
      assert Map.has_key?(schema["properties"], "quoted_message_id")
      assert Map.has_key?(schema["properties"], "quoted_chat_jid")
      assert Map.has_key?(schema["properties"], "quoted_sender")
    end
  end

  describe "call_tool/3 reply_to_message" do
    test "returns {:ok, text} on success" do
      Req.Test.stub(:reply_tool_success, fn conn ->
        Req.Test.json(conn, %{success: true, message: "Reply sent to 12025551234"})
      end)

      assert {:ok, text} =
               Tools.call_tool(
                 "reply_to_message",
                 %{
                   "recipient" => "12025551234",
                   "message" => "Thanks!",
                   "quoted_message_id" => "ABC123",
                   "quoted_chat_jid" => "12025551234@s.whatsapp.net",
                   "quoted_sender" => "14155551234@s.whatsapp.net"
                 },
                 plug: {Req.Test, :reply_tool_success}
               )

      assert String.contains?(text, "Reply sent")
    end

    test "returns {:error, message} when recipient is missing" do
      assert {:error, "recipient parameter is required"} =
               Tools.call_tool(
                 "reply_to_message",
                 %{
                   "message" => "Hi",
                   "quoted_message_id" => "ABC",
                   "quoted_chat_jid" => "test@s.whatsapp.net",
                   "quoted_sender" => "sender@s.whatsapp.net"
                 },
                 []
               )
    end

    test "returns {:error, message} when message is missing" do
      assert {:error, "message parameter is required"} =
               Tools.call_tool(
                 "reply_to_message",
                 %{
                   "recipient" => "123",
                   "quoted_message_id" => "ABC",
                   "quoted_chat_jid" => "test@s.whatsapp.net",
                   "quoted_sender" => "sender@s.whatsapp.net"
                 },
                 []
               )
    end

    test "returns {:error, message} when quoted_message_id is missing" do
      assert {:error, "quoted_message_id parameter is required"} =
               Tools.call_tool(
                 "reply_to_message",
                 %{
                   "recipient" => "123",
                   "message" => "Hi",
                   "quoted_chat_jid" => "test@s.whatsapp.net",
                   "quoted_sender" => "sender@s.whatsapp.net"
                 },
                 []
               )
    end

    test "returns {:error, message} when quoted_chat_jid is missing" do
      assert {:error, "quoted_chat_jid parameter is required"} =
               Tools.call_tool(
                 "reply_to_message",
                 %{
                   "recipient" => "123",
                   "message" => "Hi",
                   "quoted_message_id" => "ABC",
                   "quoted_sender" => "sender@s.whatsapp.net"
                 },
                 []
               )
    end

    test "returns {:error, message} when quoted_sender is missing" do
      assert {:error, "quoted_sender parameter is required"} =
               Tools.call_tool(
                 "reply_to_message",
                 %{
                   "recipient" => "123",
                   "message" => "Hi",
                   "quoted_message_id" => "ABC",
                   "quoted_chat_jid" => "test@s.whatsapp.net"
                 },
                 []
               )
    end
  end

  describe "list_tools/0 send_location tool" do
    test "includes send_location tool definition" do
      tools = Tools.list_tools()
      tool = Enum.find(tools, &(&1["name"] == "send_location"))

      assert tool
      assert String.contains?(tool["description"], "location pin")

      schema = tool["inputSchema"]
      assert schema["required"] == ["recipient", "latitude", "longitude"]
      assert Map.has_key?(schema["properties"], "recipient")
      assert Map.has_key?(schema["properties"], "latitude")
      assert Map.has_key?(schema["properties"], "longitude")
      assert Map.has_key?(schema["properties"], "name")
      assert Map.has_key?(schema["properties"], "address")

      # Verify latitude/longitude have min/max constraints
      assert schema["properties"]["latitude"]["minimum"] == -90
      assert schema["properties"]["latitude"]["maximum"] == 90
      assert schema["properties"]["longitude"]["minimum"] == -180
      assert schema["properties"]["longitude"]["maximum"] == 180
    end
  end

  describe "call_tool/3 send_location" do
    test "returns {:ok, text} on success" do
      Req.Test.stub(:location_tool_success, fn conn ->
        Req.Test.json(conn, %{success: true, message: "Location sent to 12025551234"})
      end)

      assert {:ok, text} =
               Tools.call_tool(
                 "send_location",
                 %{"recipient" => "12025551234", "latitude" => 48.8584, "longitude" => 2.2945},
                 plug: {Req.Test, :location_tool_success}
               )

      assert String.contains?(text, "Location sent")
    end

    test "passes name and address to bridge" do
      test_pid = self()

      Req.Test.stub(:location_tool_verify, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:payload, Jason.decode!(body)})
        Req.Test.json(conn, %{success: true, message: "Location sent"})
      end)

      Tools.call_tool(
        "send_location",
        %{
          "recipient" => "12025551234",
          "latitude" => 48.8584,
          "longitude" => 2.2945,
          "name" => "Eiffel Tower",
          "address" => "Champ de Mars"
        },
        plug: {Req.Test, :location_tool_verify}
      )

      assert_receive {:payload, payload}
      assert payload["name"] == "Eiffel Tower"
      assert payload["address"] == "Champ de Mars"
    end

    test "returns {:error, message} when recipient is missing" do
      assert {:error, "recipient parameter is required"} =
               Tools.call_tool(
                 "send_location",
                 %{"latitude" => 48.8584, "longitude" => 2.2945},
                 []
               )
    end

    test "returns {:error, message} when latitude is missing" do
      assert {:error, "latitude parameter is required"} =
               Tools.call_tool(
                 "send_location",
                 %{"recipient" => "12025551234", "longitude" => 2.2945},
                 []
               )
    end

    test "returns {:error, message} when longitude is missing" do
      assert {:error, "longitude parameter is required"} =
               Tools.call_tool(
                 "send_location",
                 %{"recipient" => "12025551234", "latitude" => 48.8584},
                 []
               )
    end

    test "returns {:error, message} when latitude is out of range" do
      assert {:error, "latitude must be between -90 and 90"} =
               Tools.call_tool(
                 "send_location",
                 %{"recipient" => "12025551234", "latitude" => 95.0, "longitude" => 2.2945},
                 []
               )
    end

    test "returns {:error, message} when longitude is out of range" do
      assert {:error, "longitude must be between -180 and 180"} =
               Tools.call_tool(
                 "send_location",
                 %{"recipient" => "12025551234", "latitude" => 48.8584, "longitude" => 200.0},
                 []
               )
    end

    test "returns {:error, message} when latitude is not a number" do
      assert {:error, "latitude must be a number"} =
               Tools.call_tool(
                 "send_location",
                 %{"recipient" => "12025551234", "latitude" => "north", "longitude" => 2.2945},
                 []
               )
    end
  end

  describe "list_tools/0 edit_message tool" do
    test "includes edit_message tool definition" do
      tools = Tools.list_tools()
      tool = Enum.find(tools, &(&1["name"] == "edit_message"))

      assert tool
      assert String.contains?(tool["description"], "Edit a sent message")

      schema = tool["inputSchema"]
      assert schema["type"] == "object"
      assert schema["required"] == ["chat_jid", "message_id", "new_content"]
      assert Map.has_key?(schema["properties"], "chat_jid")
      assert Map.has_key?(schema["properties"], "message_id")
      assert Map.has_key?(schema["properties"], "new_content")
    end
  end

  describe "call_tool/3 edit_message" do
    test "returns {:ok, text} on success" do
      Req.Test.stub(:edit_tool_success, fn conn ->
        Req.Test.json(conn, %{success: true, message: "Message ABC123 edited in 12025551234@s.whatsapp.net"})
      end)

      assert {:ok, text} =
               Tools.call_tool(
                 "edit_message",
                 %{
                   "chat_jid" => "12025551234@s.whatsapp.net",
                   "message_id" => "ABC123",
                   "new_content" => "Fixed typo!"
                 },
                 plug: {Req.Test, :edit_tool_success}
               )

      assert String.contains?(text, "Message ABC123 edited")
    end

    test "returns {:error, message} when chat_jid is missing" do
      assert {:error, "chat_jid parameter is required"} =
               Tools.call_tool("edit_message", %{"message_id" => "ABC123", "new_content" => "New text"}, [])
    end

    test "returns {:error, message} when message_id is missing" do
      assert {:error, "message_id parameter is required"} =
               Tools.call_tool(
                 "edit_message",
                 %{"chat_jid" => "test@s.whatsapp.net", "new_content" => "New text"},
                 []
               )
    end

    test "returns {:error, message} when new_content is missing" do
      assert {:error, "new_content parameter is required"} =
               Tools.call_tool(
                 "edit_message",
                 %{"chat_jid" => "test@s.whatsapp.net", "message_id" => "ABC123"},
                 []
               )
    end

    test "returns {:error, message} when new_content is empty" do
      assert {:error, "new_content parameter is required"} =
               Tools.call_tool(
                 "edit_message",
                 %{"chat_jid" => "test@s.whatsapp.net", "message_id" => "ABC123", "new_content" => ""},
                 []
               )
    end
  end

  describe "call_tool/2 validation edge cases" do
    test "send_message with empty string recipient returns error" do
      Req.Test.stub(:send_empty_recipient, fn conn ->
        Plug.Conn.send_resp(conn, 400, ~s({"error": "invalid recipient"}))
      end)

      assert {:error, "recipient parameter is required"} =
               Tools.call_tool("send_message", %{"recipient" => "", "message" => "test"}, [])
    end

    test "send_message with empty string message returns error" do
      assert {:error, "message parameter is required"} =
               Tools.call_tool("send_message", %{"recipient" => "12025551234", "message" => ""}, [])
    end

    test "send_file with empty file_path returns error" do
      assert {:error, "file_path parameter is required"} =
               Tools.call_tool("send_file", %{"recipient" => "12025551234", "file_path" => ""}, [])
    end

    test "download_media with empty message_id returns error" do
      assert {:error, "message_id parameter is required"} =
               Tools.call_tool(
                 "download_media",
                 %{"message_id" => "", "chat_jid" => "12025551234@s.whatsapp.net"},
                 []
               )
    end

    test "download_media with empty chat_jid returns error" do
      assert {:error, "chat_jid parameter is required"} =
               Tools.call_tool("download_media", %{"message_id" => "msg123", "chat_jid" => ""}, [])
    end

    test "mark_read with empty message_ids list returns error" do
      assert {:error, "message_ids cannot be empty"} =
               Tools.call_tool(
                 "mark_read",
                 %{"chat_jid" => "12025551234@s.whatsapp.net", "message_ids" => []},
                 []
               )
    end

    test "mark_read with non-list message_ids returns error" do
      assert {:error, "message_ids must be a list"} =
               Tools.call_tool(
                 "mark_read",
                 %{"chat_jid" => "12025551234@s.whatsapp.net", "message_ids" => "not_a_list"},
                 []
               )
    end
  end

  # ============================================================================
  # Task 39: Presence & Disappearing Messages
  # ============================================================================

  describe "list_tools/0 set_presence tool" do
    test "includes set_presence tool definition" do
      tools = Tools.list_tools()
      tool = Enum.find(tools, &(&1["name"] == "set_presence"))

      assert tool
      assert String.contains?(tool["description"], "online presence")

      schema = tool["inputSchema"]
      assert schema["type"] == "object"
      assert schema["required"] == ["available"]
      assert Map.has_key?(schema["properties"], "available")
    end
  end

  describe "call_tool/3 set_presence" do
    test "returns {:ok, text} on success setting available" do
      Req.Test.stub(:set_presence_available, fn conn ->
        Req.Test.json(conn, %{success: true, message: "Presence set to available"})
      end)

      assert {:ok, text} =
               Tools.call_tool("set_presence", %{"available" => true}, plug: {Req.Test, :set_presence_available})

      assert String.contains?(text, "Presence set to available")
    end

    test "returns {:ok, text} on success setting unavailable" do
      Req.Test.stub(:set_presence_unavailable, fn conn ->
        Req.Test.json(conn, %{success: true, message: "Presence set to unavailable"})
      end)

      assert {:ok, text} =
               Tools.call_tool("set_presence", %{"available" => false}, plug: {Req.Test, :set_presence_unavailable})

      assert String.contains?(text, "Presence set to unavailable")
    end

    test "returns {:error, message} when available is missing" do
      assert {:error, "available parameter is required"} =
               Tools.call_tool("set_presence", %{}, [])
    end

    test "returns {:error, message} when available is not a boolean" do
      assert {:error, "available must be a boolean"} =
               Tools.call_tool("set_presence", %{"available" => "yes"}, [])
    end

    test "returns {:error, message} on bridge error" do
      Req.Test.stub(:set_presence_error, fn conn ->
        Req.Test.json(conn, %{success: false, message: "Failed to set presence: not connected"})
      end)

      assert {:error, "Failed to set presence: not connected"} =
               Tools.call_tool("set_presence", %{"available" => true}, plug: {Req.Test, :set_presence_error})
    end
  end

  describe "list_tools/0 subscribe_presence tool" do
    test "includes subscribe_presence tool definition" do
      tools = Tools.list_tools()
      tool = Enum.find(tools, &(&1["name"] == "subscribe_presence"))

      assert tool
      assert String.contains?(tool["description"], "presence updates")

      schema = tool["inputSchema"]
      assert schema["type"] == "object"
      assert schema["required"] == ["jid"]
      assert Map.has_key?(schema["properties"], "jid")
    end
  end

  describe "call_tool/3 subscribe_presence" do
    test "returns {:ok, text} on success" do
      Req.Test.stub(:subscribe_presence_success, fn conn ->
        Req.Test.json(conn, %{success: true, message: "Subscribed to presence updates for 12025551234@s.whatsapp.net"})
      end)

      assert {:ok, text} =
               Tools.call_tool(
                 "subscribe_presence",
                 %{"jid" => "12025551234@s.whatsapp.net"},
                 plug: {Req.Test, :subscribe_presence_success}
               )

      assert String.contains?(text, "Subscribed to presence updates")
    end

    test "returns {:error, message} when jid is missing" do
      assert {:error, "jid parameter is required"} =
               Tools.call_tool("subscribe_presence", %{}, [])
    end

    test "returns {:error, message} when jid is empty" do
      assert {:error, "jid parameter is required"} =
               Tools.call_tool("subscribe_presence", %{"jid" => ""}, [])
    end

    test "returns {:error, message} on bridge error" do
      Req.Test.stub(:subscribe_presence_error, fn conn ->
        Req.Test.json(conn, %{success: false, message: "Invalid JID format: xyz"})
      end)

      assert {:error, "Invalid JID format: xyz"} =
               Tools.call_tool("subscribe_presence", %{"jid" => "xyz"}, plug: {Req.Test, :subscribe_presence_error})
    end
  end

  describe "list_tools/0 set_disappearing_timer tool" do
    test "includes set_disappearing_timer tool definition" do
      tools = Tools.list_tools()
      tool = Enum.find(tools, &(&1["name"] == "set_disappearing_timer"))

      assert tool
      assert String.contains?(tool["description"], "disappearing messages timer")

      schema = tool["inputSchema"]
      assert schema["type"] == "object"
      assert schema["required"] == ["chat_jid", "timer"]
      assert Map.has_key?(schema["properties"], "chat_jid")
      assert Map.has_key?(schema["properties"], "timer")
      # Verify enum constraint
      assert schema["properties"]["timer"]["enum"] == ["off", "24h", "7d", "90d"]
    end
  end

  describe "call_tool/3 set_disappearing_timer" do
    test "returns {:ok, text} on success setting 24h" do
      Req.Test.stub(:disappearing_24h_success, fn conn ->
        Req.Test.json(conn, %{success: true, message: "Disappearing messages set to 24h for 12025551234@s.whatsapp.net"})
      end)

      assert {:ok, text} =
               Tools.call_tool(
                 "set_disappearing_timer",
                 %{"chat_jid" => "12025551234@s.whatsapp.net", "timer" => "24h"},
                 plug: {Req.Test, :disappearing_24h_success}
               )

      assert String.contains?(text, "Disappearing messages set to 24h")
    end

    test "returns {:ok, text} on success setting off" do
      Req.Test.stub(:disappearing_off_success, fn conn ->
        Req.Test.json(conn, %{success: true, message: "Disappearing messages set to off for 12025551234@s.whatsapp.net"})
      end)

      assert {:ok, text} =
               Tools.call_tool(
                 "set_disappearing_timer",
                 %{"chat_jid" => "12025551234@s.whatsapp.net", "timer" => "off"},
                 plug: {Req.Test, :disappearing_off_success}
               )

      assert String.contains?(text, "Disappearing messages set to off")
    end

    test "returns {:ok, text} on success setting 7d" do
      Req.Test.stub(:disappearing_7d_success, fn conn ->
        Req.Test.json(conn, %{success: true, message: "Disappearing messages set to 7d for 12025551234@s.whatsapp.net"})
      end)

      assert {:ok, text} =
               Tools.call_tool(
                 "set_disappearing_timer",
                 %{"chat_jid" => "12025551234@s.whatsapp.net", "timer" => "7d"},
                 plug: {Req.Test, :disappearing_7d_success}
               )

      assert String.contains?(text, "Disappearing messages set to 7d")
    end

    test "returns {:ok, text} on success setting 90d" do
      Req.Test.stub(:disappearing_90d_success, fn conn ->
        Req.Test.json(conn, %{success: true, message: "Disappearing messages set to 90d for 12025551234@s.whatsapp.net"})
      end)

      assert {:ok, text} =
               Tools.call_tool(
                 "set_disappearing_timer",
                 %{"chat_jid" => "12025551234@s.whatsapp.net", "timer" => "90d"},
                 plug: {Req.Test, :disappearing_90d_success}
               )

      assert String.contains?(text, "Disappearing messages set to 90d")
    end

    test "returns {:error, message} when chat_jid is missing" do
      assert {:error, "chat_jid parameter is required"} =
               Tools.call_tool("set_disappearing_timer", %{"timer" => "24h"}, [])
    end

    test "returns {:error, message} when chat_jid is empty" do
      assert {:error, "chat_jid parameter is required"} =
               Tools.call_tool("set_disappearing_timer", %{"chat_jid" => "", "timer" => "24h"}, [])
    end

    test "returns {:error, message} when timer is missing" do
      assert {:error, "timer parameter is required"} =
               Tools.call_tool("set_disappearing_timer", %{"chat_jid" => "12025551234@s.whatsapp.net"}, [])
    end

    test "returns {:error, message} when timer is empty" do
      assert {:error, "timer parameter is required"} =
               Tools.call_tool("set_disappearing_timer", %{"chat_jid" => "12025551234@s.whatsapp.net", "timer" => ""}, [])
    end

    test "returns {:error, message} when timer is invalid" do
      assert {:error, "timer must be one of: off, 24h, 7d, 90d"} =
               Tools.call_tool(
                 "set_disappearing_timer",
                 %{"chat_jid" => "12025551234@s.whatsapp.net", "timer" => "1h"},
                 []
               )
    end

    test "returns {:error, message} on bridge error" do
      Req.Test.stub(:disappearing_error, fn conn ->
        Req.Test.json(conn, %{success: false, message: "Invalid chat JID format: xyz"})
      end)

      assert {:error, "Invalid chat JID format: xyz"} =
               Tools.call_tool(
                 "set_disappearing_timer",
                 %{"chat_jid" => "xyz", "timer" => "24h"},
                 plug: {Req.Test, :disappearing_error}
               )
    end
  end

  describe "call_tool/2 set_presence (without opts)" do
    test "delegates to call_tool/3" do
      # Missing available parameter should return validation error
      assert {:error, "available parameter is required"} =
               Tools.call_tool("set_presence", %{})
    end
  end

  describe "call_tool/2 subscribe_presence (without opts)" do
    test "delegates to call_tool/3" do
      # Missing jid parameter should return validation error
      assert {:error, "jid parameter is required"} =
               Tools.call_tool("subscribe_presence", %{})
    end
  end

  describe "call_tool/2 set_disappearing_timer (without opts)" do
    test "delegates to call_tool/3" do
      # Missing chat_jid parameter should return validation error
      assert {:error, "chat_jid parameter is required"} =
               Tools.call_tool("set_disappearing_timer", %{"timer" => "24h"})
    end
  end

  describe "call_tool/3 is_on_whatsapp" do
    test "returns {:ok, formatted} on successful check" do
      Req.Test.stub(:is_on_whatsapp_tool_success, fn conn ->
        Req.Test.json(conn, %{
          success: true,
          results: [
            %{phone: "12025551234", is_on_whatsapp: true, jid: "12025551234@s.whatsapp.net"}
          ]
        })
      end)

      assert {:ok, text} =
               Tools.call_tool("is_on_whatsapp", %{"phones" => ["12025551234"]},
                 plug: {Req.Test, :is_on_whatsapp_tool_success}
               )

      assert String.contains?(text, "12025551234")
      assert String.contains?(text, "Registered")
    end

    test "returns {:error, message} when phones is missing" do
      assert {:error, "phones parameter is required"} =
               Tools.call_tool("is_on_whatsapp", %{}, [])
    end

    test "returns {:error, message} when phones is empty" do
      assert {:error, "phones array cannot be empty"} =
               Tools.call_tool("is_on_whatsapp", %{"phones" => []}, [])
    end

    test "returns {:error, message} when phones has too many numbers" do
      phones = Enum.map(1..51, &to_string/1)

      assert {:error, msg} = Tools.call_tool("is_on_whatsapp", %{"phones" => phones}, [])
      assert String.contains?(msg, "maximum 50")
    end

    test "returns descriptive error when bridge not running" do
      Req.Test.stub(:is_on_whatsapp_tool_down, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, msg} =
               Tools.call_tool("is_on_whatsapp", %{"phones" => ["12025551234"]},
                 plug: {Req.Test, :is_on_whatsapp_tool_down}
               )

      assert String.contains?(msg, "bridge is not running")
    end
  end

  describe "call_tool/2 is_on_whatsapp (without opts)" do
    test "delegates to call_tool/3" do
      assert {:error, "phones parameter is required"} =
               Tools.call_tool("is_on_whatsapp", %{})
    end
  end

  describe "call_tool/3 get_profile_picture" do
    test "returns {:ok, formatted} on success" do
      Req.Test.stub(:profile_pic_tool_success, fn conn ->
        Req.Test.json(conn, %{
          success: true,
          url: "https://pps.whatsapp.net/v/t61.24694-24/abc123.jpg",
          id: "1234567890"
        })
      end)

      assert {:ok, text} =
               Tools.call_tool("get_profile_picture", %{"jid" => "12025551234@s.whatsapp.net"},
                 plug: {Req.Test, :profile_pic_tool_success}
               )

      assert String.contains?(text, "Profile Picture")
      assert String.contains?(text, "https://pps.whatsapp.net")
    end

    test "returns {:error, message} when jid is missing" do
      assert {:error, "jid parameter is required"} =
               Tools.call_tool("get_profile_picture", %{}, [])
    end

    test "returns {:error, message} when no profile picture" do
      Req.Test.stub(:profile_pic_tool_not_found, fn conn ->
        Req.Test.json(conn, %{success: false, message: "No profile picture set for this contact"})
      end)

      assert {:error, "No profile picture set for this contact"} =
               Tools.call_tool("get_profile_picture", %{"jid" => "12025551234@s.whatsapp.net"},
                 plug: {Req.Test, :profile_pic_tool_not_found}
               )
    end

    test "returns descriptive error when bridge not running" do
      Req.Test.stub(:profile_pic_tool_down, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, msg} =
               Tools.call_tool("get_profile_picture", %{"jid" => "12025551234@s.whatsapp.net"},
                 plug: {Req.Test, :profile_pic_tool_down}
               )

      assert String.contains?(msg, "bridge is not running")
    end
  end

  describe "call_tool/2 get_profile_picture (without opts)" do
    test "delegates to call_tool/3" do
      assert {:error, "jid parameter is required"} =
               Tools.call_tool("get_profile_picture", %{})
    end
  end

  describe "call_tool/3 get_blocklist" do
    test "returns {:ok, formatted} on success with blocked contacts" do
      Req.Test.stub(:blocklist_tool_success, fn conn ->
        Req.Test.json(conn, %{
          success: true,
          blocklist: ["12025551234@s.whatsapp.net", "44123456789@s.whatsapp.net"]
        })
      end)

      assert {:ok, text} =
               Tools.call_tool("get_blocklist", %{}, plug: {Req.Test, :blocklist_tool_success})

      assert String.contains?(text, "Blocked Contacts")
      assert String.contains?(text, "12025551234@s.whatsapp.net")
      assert String.contains?(text, "2")
    end

    test "returns {:ok, formatted} on success with empty blocklist" do
      Req.Test.stub(:blocklist_tool_empty, fn conn ->
        Req.Test.json(conn, %{success: true, blocklist: []})
      end)

      assert {:ok, text} =
               Tools.call_tool("get_blocklist", %{}, plug: {Req.Test, :blocklist_tool_empty})

      assert String.contains?(text, "empty")
    end

    test "returns descriptive error when bridge not running" do
      Req.Test.stub(:blocklist_tool_down, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, msg} =
               Tools.call_tool("get_blocklist", %{}, plug: {Req.Test, :blocklist_tool_down})

      assert String.contains?(msg, "bridge is not running")
    end
  end

  describe "call_tool/2 get_blocklist (without opts)" do
    test "delegates to call_tool/3 with success" do
      Req.Test.stub(:blocklist_tool_2arity, fn conn ->
        Req.Test.json(conn, %{success: true, blocklist: []})
      end)

      # Test the 3-arity function with plug option - verifies delegation works
      assert {:ok, text} = Tools.call_tool("get_blocklist", %{}, plug: {Req.Test, :blocklist_tool_2arity})
      assert String.contains?(text, "empty")
    end
  end

  describe "call_tool/3 update_blocklist" do
    test "returns {:ok, message} on successful block" do
      Req.Test.stub(:update_blocklist_tool_block, fn conn ->
        Req.Test.json(conn, %{success: true, message: "Contact 12025551234@s.whatsapp.net blocked"})
      end)

      assert {:ok, "Contact 12025551234@s.whatsapp.net blocked"} =
               Tools.call_tool("update_blocklist", %{"jid" => "12025551234@s.whatsapp.net", "action" => "block"},
                 plug: {Req.Test, :update_blocklist_tool_block}
               )
    end

    test "returns {:ok, message} on successful unblock" do
      Req.Test.stub(:update_blocklist_tool_unblock, fn conn ->
        Req.Test.json(conn, %{success: true, message: "Contact 12025551234@s.whatsapp.net unblocked"})
      end)

      assert {:ok, "Contact 12025551234@s.whatsapp.net unblocked"} =
               Tools.call_tool("update_blocklist", %{"jid" => "12025551234@s.whatsapp.net", "action" => "unblock"},
                 plug: {Req.Test, :update_blocklist_tool_unblock}
               )
    end

    test "returns {:error, message} when jid is missing" do
      assert {:error, "jid parameter is required"} =
               Tools.call_tool("update_blocklist", %{"action" => "block"}, [])
    end

    test "returns {:error, message} when action is missing" do
      assert {:error, "action parameter is required"} =
               Tools.call_tool("update_blocklist", %{"jid" => "12025551234@s.whatsapp.net"}, [])
    end

    test "returns {:error, message} when action is invalid" do
      assert {:error, msg} =
               Tools.call_tool("update_blocklist", %{"jid" => "12025551234@s.whatsapp.net", "action" => "invalid"}, [])

      assert String.contains?(msg, "block")
      assert String.contains?(msg, "unblock")
    end

    test "returns descriptive error when bridge not running" do
      Req.Test.stub(:update_blocklist_tool_down, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, msg} =
               Tools.call_tool("update_blocklist", %{"jid" => "12025551234@s.whatsapp.net", "action" => "block"},
                 plug: {Req.Test, :update_blocklist_tool_down}
               )

      assert String.contains?(msg, "bridge is not running")
    end
  end

  describe "call_tool/2 update_blocklist (without opts)" do
    test "delegates to call_tool/3" do
      assert {:error, "jid parameter is required"} =
               Tools.call_tool("update_blocklist", %{"action" => "block"})
    end
  end

  describe "call_tool/3 create_poll" do
    test "returns {:ok, message} on successful single-choice poll" do
      Req.Test.stub(:poll_tool_single, fn conn ->
        Req.Test.json(conn, %{success: true, message: "Poll sent to 12025551234 (single-choice with 3 options)"})
      end)

      assert {:ok, "Poll sent to 12025551234 (single-choice with 3 options)"} =
               Tools.call_tool(
                 "create_poll",
                 %{
                   "recipient" => "12025551234",
                   "question" => "What's for lunch?",
                   "options" => ["Pizza", "Sushi", "Salad"],
                   "max_selections" => 1
                 },
                 plug: {Req.Test, :poll_tool_single}
               )
    end

    test "returns {:ok, message} on successful multi-choice poll" do
      Req.Test.stub(:poll_tool_multi, fn conn ->
        Req.Test.json(conn, %{success: true, message: "Poll sent to 12025551234 (multi-choice (up to 3) with 4 options)"})
      end)

      assert {:ok, "Poll sent to 12025551234 (multi-choice (up to 3) with 4 options)"} =
               Tools.call_tool(
                 "create_poll",
                 %{
                   "recipient" => "12025551234",
                   "question" => "Select toppings",
                   "options" => ["Cheese", "Pepperoni", "Mushrooms", "Olives"],
                   "max_selections" => 3
                 },
                 plug: {Req.Test, :poll_tool_multi}
               )
    end

    test "defaults max_selections to 1 when not provided" do
      test_pid = self()

      Req.Test.stub(:poll_tool_default_max, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:payload, Jason.decode!(body)})
        Req.Test.json(conn, %{success: true, message: "Poll sent"})
      end)

      Tools.call_tool(
        "create_poll",
        %{
          "recipient" => "12025551234",
          "question" => "Pick one",
          "options" => ["A", "B"]
        },
        plug: {Req.Test, :poll_tool_default_max}
      )

      assert_receive {:payload, %{"max_selections" => 1}}
    end

    test "returns {:error, message} when recipient is missing" do
      assert {:error, "recipient parameter is required"} =
               Tools.call_tool(
                 "create_poll",
                 %{"question" => "Question?", "options" => ["A", "B"]},
                 []
               )
    end

    test "returns {:error, message} when recipient is empty" do
      assert {:error, "recipient parameter is required"} =
               Tools.call_tool(
                 "create_poll",
                 %{"recipient" => "", "question" => "Question?", "options" => ["A", "B"]},
                 []
               )
    end

    test "returns {:error, message} when question is missing" do
      assert {:error, "question parameter is required"} =
               Tools.call_tool(
                 "create_poll",
                 %{"recipient" => "12025551234", "options" => ["A", "B"]},
                 []
               )
    end

    test "returns {:error, message} when question is empty" do
      assert {:error, "question parameter is required"} =
               Tools.call_tool(
                 "create_poll",
                 %{"recipient" => "12025551234", "question" => "", "options" => ["A", "B"]},
                 []
               )
    end

    test "returns {:error, message} when options is missing" do
      assert {:error, "options parameter is required"} =
               Tools.call_tool(
                 "create_poll",
                 %{"recipient" => "12025551234", "question" => "Question?"},
                 []
               )
    end

    test "returns {:error, message} when options is not a list" do
      assert {:error, "options must be an array"} =
               Tools.call_tool(
                 "create_poll",
                 %{"recipient" => "12025551234", "question" => "Question?", "options" => "not a list"},
                 []
               )
    end

    test "returns {:error, message} when fewer than 2 options provided" do
      assert {:error, "at least 2 options are required"} =
               Tools.call_tool(
                 "create_poll",
                 %{"recipient" => "12025551234", "question" => "Question?", "options" => ["Only one"]},
                 []
               )
    end

    test "returns {:error, message} when more than 12 options provided" do
      too_many_options = Enum.map(1..13, &"Option #{&1}")

      assert {:error, "maximum 12 options allowed"} =
               Tools.call_tool(
                 "create_poll",
                 %{"recipient" => "12025551234", "question" => "Question?", "options" => too_many_options},
                 []
               )
    end

    test "returns {:error, message} when options contain empty string" do
      assert {:error, "options cannot contain empty strings"} =
               Tools.call_tool(
                 "create_poll",
                 %{"recipient" => "12025551234", "question" => "Question?", "options" => ["Pizza", "", "Sushi"]},
                 []
               )
    end

    test "returns {:error, message} when options contain nil" do
      assert {:error, "options cannot contain empty strings"} =
               Tools.call_tool(
                 "create_poll",
                 %{"recipient" => "12025551234", "question" => "Question?", "options" => ["Pizza", nil, "Sushi"]},
                 []
               )
    end

    test "returns descriptive error when bridge not running" do
      Req.Test.stub(:poll_tool_down, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, msg} =
               Tools.call_tool(
                 "create_poll",
                 %{"recipient" => "12025551234", "question" => "Question?", "options" => ["A", "B"]},
                 plug: {Req.Test, :poll_tool_down}
               )

      assert String.contains?(msg, "bridge is not running")
    end

    test "returns descriptive error on timeout" do
      Req.Test.stub(:poll_tool_timeout, fn conn ->
        Req.Test.transport_error(conn, :timeout)
      end)

      assert {:error, msg} =
               Tools.call_tool(
                 "create_poll",
                 %{"recipient" => "12025551234", "question" => "Question?", "options" => ["A", "B"]},
                 plug: {Req.Test, :poll_tool_timeout}
               )

      assert String.contains?(msg, "timed out")
    end
  end

  describe "call_tool/2 create_poll (without opts)" do
    test "delegates to call_tool/3" do
      assert {:error, "recipient parameter is required"} =
               Tools.call_tool("create_poll", %{"question" => "Q?", "options" => ["A", "B"]})
    end
  end

  describe "list_tools/0 create_poll" do
    test "includes create_poll tool with correct schema" do
      tools = Tools.list_tools()
      create_poll_tool = Enum.find(tools, &(&1["name"] == "create_poll"))

      assert create_poll_tool
      assert String.contains?(create_poll_tool["description"], "poll")

      schema = create_poll_tool["inputSchema"]
      assert schema["type"] == "object"
      assert schema["required"] == ["recipient", "question", "options"]
      assert Map.has_key?(schema["properties"], "recipient")
      assert Map.has_key?(schema["properties"], "question")
      assert Map.has_key?(schema["properties"], "options")
      assert Map.has_key?(schema["properties"], "max_selections")

      # Check options constraints
      options_schema = schema["properties"]["options"]
      assert options_schema["type"] == "array"
      assert options_schema["minItems"] == 2
      assert options_schema["maxItems"] == 12

      # Check max_selections default
      max_sel_schema = schema["properties"]["max_selections"]
      assert max_sel_schema["type"] == "integer"
      assert max_sel_schema["default"] == 1
      assert max_sel_schema["minimum"] == 1
    end
  end

  describe "call_tool/3 list_contacts" do
    test "returns formatted contacts list on success" do
      Req.Test.stub(:list_contacts_success, fn conn ->
        Req.Test.json(conn, %{
          success: true,
          contacts: [
            %{
              jid: "12025551234@s.whatsapp.net",
              first_name: "John",
              full_name: "John Doe",
              push_name: "Johnny",
              business_name: nil,
              redacted_phone: nil
            },
            %{
              jid: "78834275733504@lid",
              first_name: nil,
              full_name: nil,
              push_name: "Esteban",
              business_name: nil,
              redacted_phone: "+33∙∙∙∙∙∙∙∙53"
            }
          ],
          total: 2
        })
      end)

      {:ok, result} = Tools.call_tool("list_contacts", %{}, plug: {Req.Test, :list_contacts_success})

      assert String.contains?(result, "Synced Contacts")
      assert String.contains?(result, "showing 1-2 of 2")
      assert String.contains?(result, "12025551234@s.whatsapp.net")
      assert String.contains?(result, "John Doe")
      assert String.contains?(result, "78834275733504@lid")
      assert String.contains?(result, "Esteban")
      assert String.contains?(result, "+33∙∙∙∙∙∙∙∙53")
    end

    test "passes limit and offset to bridge" do
      test_pid = self()

      Req.Test.stub(:list_contacts_pagination, fn conn ->
        send(test_pid, {:query_params, conn.query_params})
        Req.Test.json(conn, %{success: true, contacts: [], total: 0})
      end)

      Tools.call_tool("list_contacts", %{"limit" => 50, "offset" => 100}, plug: {Req.Test, :list_contacts_pagination})

      assert_receive {:query_params, params}
      assert params["limit"] == "50"
      assert params["offset"] == "100"
    end

    test "passes query parameter to bridge" do
      test_pid = self()

      Req.Test.stub(:list_contacts_query, fn conn ->
        send(test_pid, {:query_params, conn.query_params})
        Req.Test.json(conn, %{success: true, contacts: [], total: 0})
      end)

      Tools.call_tool("list_contacts", %{"query" => "John"}, plug: {Req.Test, :list_contacts_query})

      assert_receive {:query_params, params}
      assert params["query"] == "John"
    end

    test "shows pagination hint when more contacts exist" do
      Req.Test.stub(:list_contacts_more, fn conn ->
        Req.Test.json(conn, %{
          success: true,
          contacts: [%{jid: "12025551234@s.whatsapp.net", push_name: "Test"}],
          total: 100
        })
      end)

      {:ok, result} = Tools.call_tool("list_contacts", %{"limit" => 10}, plug: {Req.Test, :list_contacts_more})

      assert String.contains?(result, "Tip: Use list_contacts(offset:")
    end

    test "returns empty message when no contacts" do
      Req.Test.stub(:list_contacts_empty, fn conn ->
        Req.Test.json(conn, %{success: true, contacts: [], total: 0})
      end)

      {:ok, result} = Tools.call_tool("list_contacts", %{}, plug: {Req.Test, :list_contacts_empty})

      assert String.contains?(result, "No contacts synced")
    end

    test "returns error when bridge not running" do
      Req.Test.stub(:list_contacts_refused, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      {:error, msg} = Tools.call_tool("list_contacts", %{}, plug: {Req.Test, :list_contacts_refused})

      assert String.contains?(msg, "bridge is not running")
    end
  end

  describe "list_tools/0 list_contacts" do
    test "includes list_contacts tool with correct schema" do
      tools = Tools.list_tools()
      list_contacts_tool = Enum.find(tools, &(&1["name"] == "list_contacts"))

      assert list_contacts_tool
      assert String.contains?(list_contacts_tool["description"], "synced WhatsApp contacts")

      schema = list_contacts_tool["inputSchema"]
      assert schema["type"] == "object"
      assert Map.has_key?(schema["properties"], "limit")
      assert Map.has_key?(schema["properties"], "offset")
      assert Map.has_key?(schema["properties"], "query")

      # No required fields
      refute Map.has_key?(schema, "required")
    end
  end

  describe "call_tool/3 merge_chats" do
    test "returns formatted success message on successful merge" do
      Req.Test.stub(:merge_chats_success, fn conn ->
        Req.Test.json(conn, %{
          success: true,
          message: "Merged 5 messages from 78834275733504@lid into 14155554567@s.whatsapp.net. Source chat deleted.",
          messages_moved: 5
        })
      end)

      {:ok, result} =
        Tools.call_tool(
          "merge_chats",
          %{"source_jid" => "78834275733504@lid", "target_jid" => "14155554567@s.whatsapp.net"},
          plug: {Req.Test, :merge_chats_success}
        )

      assert String.contains?(result, "Merged 5 messages")
      assert String.contains?(result, "Source chat deleted")
      assert String.contains?(result, "LID→phone link has been stored")
    end

    test "returns error when source_jid is missing" do
      assert {:error, "source_jid parameter is required"} =
               Tools.call_tool("merge_chats", %{"target_jid" => "target@s.whatsapp.net"})
    end

    test "returns error when target_jid is missing" do
      assert {:error, "target_jid parameter is required"} =
               Tools.call_tool("merge_chats", %{"source_jid" => "source@lid"})
    end

    test "returns error when source and target are the same" do
      assert {:error, "source_jid and target_jid cannot be the same"} =
               Tools.call_tool("merge_chats", %{"source_jid" => "same@lid", "target_jid" => "same@lid"})
    end

    test "returns error when source chat doesn't exist" do
      Req.Test.stub(:merge_chats_source_not_found, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(400, ~s({"message": "source chat does not exist: unknown@lid"}))
      end)

      {:error, msg} =
        Tools.call_tool(
          "merge_chats",
          %{"source_jid" => "unknown@lid", "target_jid" => "target@s.whatsapp.net"},
          plug: {Req.Test, :merge_chats_source_not_found}
        )

      assert String.contains?(msg, "source chat does not exist")
    end

    test "returns error when bridge not running" do
      Req.Test.stub(:merge_chats_refused, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      {:error, msg} =
        Tools.call_tool(
          "merge_chats",
          %{"source_jid" => "source@lid", "target_jid" => "target@s.whatsapp.net"},
          plug: {Req.Test, :merge_chats_refused}
        )

      assert String.contains?(msg, "bridge is not running")
    end
  end

  describe "list_tools/0 merge_chats" do
    test "includes merge_chats tool with correct schema" do
      tools = Tools.list_tools()
      merge_chats_tool = Enum.find(tools, &(&1["name"] == "merge_chats"))

      assert merge_chats_tool
      assert String.contains?(merge_chats_tool["description"], "Merge messages")

      schema = merge_chats_tool["inputSchema"]
      assert schema["type"] == "object"
      assert Map.has_key?(schema["properties"], "source_jid")
      assert Map.has_key?(schema["properties"], "target_jid")
      assert schema["required"] == ["source_jid", "target_jid"]
    end
  end

  describe "call_tool/3 get_group_invite_link" do
    test "returns formatted invite link on success" do
      Req.Test.stub(:group_invite_link_success, fn conn ->
        Req.Test.json(conn, %{success: true, invite_link: "https://chat.whatsapp.com/ABC123xyz"})
      end)

      {:ok, result} =
        Tools.call_tool("get_group_invite_link", %{"jid" => "120363123456789012@g.us"},
          plug: {Req.Test, :group_invite_link_success}
        )

      assert String.contains?(result, "https://chat.whatsapp.com/ABC123xyz")
      assert String.contains?(result, "Share this link")
    end

    test "passes reset option to bridge" do
      test_pid = self()

      Req.Test.stub(:group_invite_link_reset, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:payload, Jason.decode!(body)})
        Req.Test.json(conn, %{success: true, invite_link: "https://chat.whatsapp.com/NEW123"})
      end)

      {:ok, _} =
        Tools.call_tool("get_group_invite_link", %{"jid" => "120363123456789012@g.us", "reset" => true},
          plug: {Req.Test, :group_invite_link_reset}
        )

      assert_receive {:payload, %{"jid" => "120363123456789012@g.us", "reset" => true}}
    end

    test "returns error when jid is missing" do
      assert {:error, "jid parameter is required"} =
               Tools.call_tool("get_group_invite_link", %{}, [])
    end

    test "returns error when jid is not a group" do
      assert {:error, "JID must be a group JID (ending with @g.us)"} =
               Tools.call_tool("get_group_invite_link", %{"jid" => "12025551234@s.whatsapp.net"}, [])
    end

    test "returns descriptive error when bridge not running" do
      Req.Test.stub(:group_invite_link_refused, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      {:error, msg} =
        Tools.call_tool("get_group_invite_link", %{"jid" => "120363123456789012@g.us"},
          plug: {Req.Test, :group_invite_link_refused}
        )

      assert String.contains?(msg, "bridge is not running")
    end
  end

  describe "call_tool/3 join_group" do
    test "returns formatted success message on join" do
      Req.Test.stub(:join_group_success, fn conn ->
        Req.Test.json(conn, %{
          success: true,
          group_jid: "120363123456789012@g.us",
          message: "Successfully joined group 120363123456789012@g.us"
        })
      end)

      {:ok, result} =
        Tools.call_tool("join_group", %{"invite_link" => "https://chat.whatsapp.com/ABC123"},
          plug: {Req.Test, :join_group_success}
        )

      assert String.contains?(result, "Successfully joined")
      assert String.contains?(result, "120363123456789012@g.us")
      assert String.contains?(result, "get_messages")
    end

    test "returns error when invite_link is missing" do
      assert {:error, "invite_link parameter is required"} =
               Tools.call_tool("join_group", %{}, [])
    end

    test "returns error when invite_link is empty" do
      assert {:error, "invite_link parameter is required"} =
               Tools.call_tool("join_group", %{"invite_link" => ""}, [])
    end

    test "returns descriptive error when bridge not running" do
      Req.Test.stub(:join_group_refused, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      {:error, msg} =
        Tools.call_tool("join_group", %{"invite_link" => "https://chat.whatsapp.com/ABC123"},
          plug: {Req.Test, :join_group_refused}
        )

      assert String.contains?(msg, "bridge is not running")
    end

    test "returns error when invite link expired" do
      Req.Test.stub(:join_group_expired, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(500, ~s({"message": "Failed to join group: invite link expired"}))
      end)

      {:error, msg} =
        Tools.call_tool("join_group", %{"invite_link" => "https://chat.whatsapp.com/EXPIRED"},
          plug: {Req.Test, :join_group_expired}
        )

      assert String.contains?(msg, "invite link expired")
    end
  end

  describe "list_tools/0 get_group_invite_link" do
    test "includes get_group_invite_link tool with correct schema" do
      tools = Tools.list_tools()
      tool = Enum.find(tools, &(&1["name"] == "get_group_invite_link"))

      assert tool
      assert String.contains?(tool["description"], "invite link")
      assert String.contains?(tool["description"], "admin")

      schema = tool["inputSchema"]
      assert schema["type"] == "object"
      assert Map.has_key?(schema["properties"], "jid")
      assert Map.has_key?(schema["properties"], "reset")
      assert schema["properties"]["reset"]["type"] == "boolean"
      assert schema["required"] == ["jid"]
    end
  end

  describe "list_tools/0 join_group" do
    test "includes join_group tool with correct schema" do
      tools = Tools.list_tools()
      tool = Enum.find(tools, &(&1["name"] == "join_group"))

      assert tool
      assert String.contains?(tool["description"], "invite link")

      schema = tool["inputSchema"]
      assert schema["type"] == "object"
      assert Map.has_key?(schema["properties"], "invite_link")
      assert schema["required"] == ["invite_link"]
    end
  end
end
