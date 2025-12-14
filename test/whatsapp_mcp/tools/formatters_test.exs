defmodule WhatsappMcp.Tools.FormattersTest do
  use ExUnit.Case, async: true

  alias WhatsappMcp.Tools.Formatters

  describe "format_bridge_status/1" do
    test "formats connected status with full info" do
      http_status = {:ok, %{"connected" => true, "phone" => "12025551234", "name" => "Test User"}}

      {:ok, text} = Formatters.format_bridge_status(http_status)

      assert String.contains?(text, "Connected")
      assert String.contains?(text, "12025551234")
      assert String.contains?(text, "Test User")
    end

    test "formats connected status with phone only" do
      http_status = {:ok, %{"connected" => true, "phone" => "12025551234"}}

      {:ok, text} = Formatters.format_bridge_status(http_status)

      assert String.contains?(text, "Connected")
      assert String.contains?(text, "12025551234")
    end

    test "formats connected status without phone or name" do
      http_status = {:ok, %{"connected" => true}}

      {:ok, text} = Formatters.format_bridge_status(http_status)

      assert String.contains?(text, "Connected")
    end

    test "formats not connected status" do
      http_status = {:ok, %{"connected" => false}}

      {:ok, text} = Formatters.format_bridge_status(http_status)

      # Actual message includes "not connected to WhatsApp"
      assert String.contains?(text, "not connected")
    end

    test "formats bridge not running with startup instructions" do
      http_status = {:error, :bridge_not_running}

      {:ok, text} = Formatters.format_bridge_status(http_status)

      assert String.contains?(text, "Bridge Status: Not Running")
      assert String.contains?(text, "To start the WhatsApp bridge")
      assert String.contains?(text, "go run .")
      assert String.contains?(text, "brew install go")
    end
  end

  describe "format_chats/2" do
    test "formats empty chat list" do
      text = Formatters.format_chats([])

      assert text == "No chats found."
    end

    test "formats single chat" do
      chats = [
        %{
          jid: "12025551234@s.whatsapp.net",
          name: "Test User",
          last_message_date: "2025-12-11 10:00:00",
          last_message: "Hello there"
        }
      ]

      text = Formatters.format_chats(chats)

      assert String.contains?(text, "Found 1 chat")
      assert String.contains?(text, "Test User")
      assert String.contains?(text, "12025551234@s.whatsapp.net")
      assert String.contains?(text, "Hello there")
    end

    test "includes pagination info" do
      chats = [
        %{
          jid: "12025551234@s.whatsapp.net",
          name: "Test User",
          last_message_date: "2025-12-11 10:00:00",
          last_message: "Hello"
        }
      ]

      pagination = %{total: 5, returned: 1, offset: 2, limit: 2}
      text = Formatters.format_chats(chats, pagination)

      assert String.contains?(text, "showing")
      assert String.contains?(text, "of 5 total")
    end

    test "includes hint about get_messages" do
      chats = [
        %{
          jid: "12025551234@s.whatsapp.net",
          name: "Test User",
          last_message_date: "2025-12-11 10:00:00",
          last_message: "Hello"
        }
      ]

      text = Formatters.format_chats(chats)

      assert String.contains?(text, "Tip: Use get_messages")
    end
  end

  describe "format_messages_with_summary/3" do
    test "formats empty message list" do
      text = Formatters.format_messages_with_summary([], %{chat_jid: "test@s.whatsapp.net"})

      assert text == "No messages found."
    end

    test "formats messages with sender info" do
      messages = [
        %{
          id: "msg1",
          sender: "12025551234@s.whatsapp.net",
          text: "Hello!",
          timestamp: "2025-12-11 10:00:00",
          is_from_me: false,
          media_type: nil
        }
      ]

      chat_info = %{
        jid: "12025551234@s.whatsapp.net",
        name: "Test User"
      }

      text = Formatters.format_messages_with_summary(messages, chat_info)

      assert String.contains?(text, "Hello!")
      assert String.contains?(text, "12025551234")
    end

    test "formats messages from me" do
      messages = [
        %{
          id: "msg1",
          sender: "me",
          text: "My message",
          timestamp: "2025-12-11 10:00:00",
          is_from_me: true,
          media_type: nil
        }
      ]

      chat_info = %{
        jid: "12025551234@s.whatsapp.net",
        name: "Test User"
      }

      text = Formatters.format_messages_with_summary(messages, chat_info)

      assert String.contains?(text, "you")
      assert String.contains?(text, "My message")
    end

    test "formats message with image media" do
      messages = [
        %{
          id: "msg1",
          sender: "12025551234@s.whatsapp.net",
          text: "Photo caption",
          timestamp: "2025-12-11 10:00:00",
          is_from_me: false,
          media_type: "image"
        }
      ]

      chat_info = %{
        jid: "12025551234@s.whatsapp.net",
        name: "Test User"
      }

      text = Formatters.format_messages_with_summary(messages, chat_info)

      assert String.contains?(text, "[📷 image]")
    end

    test "formats message with video media" do
      messages = [
        %{
          id: "msg1",
          sender: "12025551234@s.whatsapp.net",
          text: "",
          timestamp: "2025-12-11 10:00:00",
          is_from_me: false,
          media_type: "video"
        }
      ]

      chat_info = %{
        jid: "12025551234@s.whatsapp.net",
        name: "Test User"
      }

      text = Formatters.format_messages_with_summary(messages, chat_info)

      assert String.contains?(text, "[🎬 video]")
    end

    test "formats message with audio media" do
      messages = [
        %{
          id: "msg1",
          sender: "12025551234@s.whatsapp.net",
          text: "",
          timestamp: "2025-12-11 10:00:00",
          is_from_me: false,
          media_type: "audio"
        }
      ]

      chat_info = %{
        jid: "12025551234@s.whatsapp.net",
        name: "Test User"
      }

      text = Formatters.format_messages_with_summary(messages, chat_info)

      assert String.contains?(text, "[🎵 audio]")
    end

    test "formats message with document media" do
      messages = [
        %{
          id: "msg1",
          sender: "12025551234@s.whatsapp.net",
          text: "",
          timestamp: "2025-12-11 10:00:00",
          is_from_me: false,
          media_type: "document"
        }
      ]

      chat_info = %{
        jid: "12025551234@s.whatsapp.net",
        name: "Test User"
      }

      text = Formatters.format_messages_with_summary(messages, chat_info)

      assert String.contains?(text, "[📄 document]")
    end
  end

  describe "format_search_results/2" do
    test "formats empty search results" do
      text = Formatters.format_search_results([])

      assert text == "No messages found matching your search."
    end

    test "formats search results with message IDs" do
      results = [
        %{
          id: "msg123",
          chat_id: "12025551234@s.whatsapp.net",
          chat_name: "Test Chat",
          sender: "12025551234@s.whatsapp.net",
          text: "Found this message",
          timestamp: "2025-12-11 10:00:00",
          is_from_me: false,
          media_type: nil
        }
      ]

      text = Formatters.format_search_results(results)

      assert String.contains?(text, "Found 1 matching message")
      assert String.contains?(text, "[MsgID:msg123]")
      assert String.contains?(text, "Test Chat")
    end

    test "includes hint about get_message_context" do
      results = [
        %{
          id: "msg123",
          chat_id: "12025551234@s.whatsapp.net",
          chat_name: "Test Chat",
          sender: "12025551234@s.whatsapp.net",
          text: "Found this message",
          timestamp: "2025-12-11 10:00:00",
          is_from_me: false,
          media_type: nil
        }
      ]

      text = Formatters.format_search_results(results)

      assert String.contains?(text, "Tip: Use get_message_context")
    end

    test "includes pagination info" do
      results = [
        %{
          id: "msg123",
          chat_id: "12025551234@s.whatsapp.net",
          chat_name: "Test Chat",
          sender: "12025551234@s.whatsapp.net",
          text: "Found this message",
          timestamp: "2025-12-11 10:00:00",
          is_from_me: false,
          media_type: nil
        }
      ]

      pagination = %{total: 10, returned: 1, offset: 0, limit: 5}
      text = Formatters.format_search_results(results, pagination)

      assert String.contains?(text, "showing 1-1 of 10 total")
    end
  end

  describe "format_contacts/2" do
    test "formats empty contact list" do
      text = Formatters.format_contacts([])

      assert text == "No contacts found matching your search."
    end

    test "formats contact with name and phone" do
      contacts = [
        %{
          jid: "12025551234@s.whatsapp.net",
          name: "John Doe",
          phone: "12025551234"
        }
      ]

      text = Formatters.format_contacts(contacts)

      assert String.contains?(text, "Found 1 contact")
      assert String.contains?(text, "John Doe")
      assert String.contains?(text, "12025551234")
    end

    test "includes hint about send_message" do
      contacts = [
        %{
          jid: "12025551234@s.whatsapp.net",
          name: "John Doe",
          phone: "12025551234"
        }
      ]

      text = Formatters.format_contacts(contacts)

      assert String.contains?(text, "Tip: Use send_message")
    end
  end

  describe "format_chat/1" do
    test "formats chat metadata" do
      chat = %{
        jid: "12025551234@s.whatsapp.net",
        name: "Test User",
        last_message_date: "2025-12-11 10:00:00",
        last_message: "Hello"
      }

      text = Formatters.format_chat(chat)

      assert String.contains?(text, "Test User")
      assert String.contains?(text, "12025551234@s.whatsapp.net")
      assert String.contains?(text, "Hello")
    end

    test "handles nil last_message" do
      chat = %{
        jid: "12025551234@s.whatsapp.net",
        name: "Test User",
        last_message_date: "2025-12-11 10:00:00",
        last_message: nil
      }

      text = Formatters.format_chat(chat)

      assert String.contains?(text, "Test User")
      assert String.contains?(text, "(no message)")
    end
  end

  describe "format_message_context/1" do
    test "formats context with before and after messages" do
      context = %{
        target: %{
          id: "msg2",
          sender: "12025551234@s.whatsapp.net",
          text: "Target message",
          timestamp: "2025-12-11 10:00:00",
          is_from_me: false,
          media_type: nil
        },
        before: [
          %{
            id: "msg1",
            sender: "me@s.whatsapp.net",
            text: "Before message",
            timestamp: "2025-12-11 09:59:00",
            is_from_me: true,
            media_type: nil
          }
        ],
        after: [
          %{
            id: "msg3",
            sender: "12025551234@s.whatsapp.net",
            text: "After message",
            timestamp: "2025-12-11 10:01:00",
            is_from_me: false,
            media_type: nil
          }
        ],
        chat_jid: "12025551234@s.whatsapp.net"
      }

      text = Formatters.format_message_context(context)

      assert String.contains?(text, "--- Before ---")
      assert String.contains?(text, "Before message")
      assert String.contains?(text, "--- Target Message ---")
      assert String.contains?(text, "Target message")
      assert String.contains?(text, "--- After ---")
      assert String.contains?(text, "After message")
    end

    test "handles empty before section" do
      context = %{
        target: %{
          id: "msg1",
          sender: "12025551234@s.whatsapp.net",
          text: "First message",
          timestamp: "2025-12-11 10:00:00",
          is_from_me: false,
          media_type: nil
        },
        before: [],
        after: [
          %{
            id: "msg2",
            sender: "me@s.whatsapp.net",
            text: "After message",
            timestamp: "2025-12-11 10:01:00",
            is_from_me: true,
            media_type: nil
          }
        ],
        chat_jid: "12025551234@s.whatsapp.net"
      }

      text = Formatters.format_message_context(context)

      refute String.contains?(text, "--- Before ---")
      assert String.contains?(text, "--- Target Message ---")
      assert String.contains?(text, "--- After ---")
    end

    test "handles empty after section" do
      context = %{
        target: %{
          id: "msg2",
          sender: "12025551234@s.whatsapp.net",
          text: "Last message",
          timestamp: "2025-12-11 10:00:00",
          is_from_me: false,
          media_type: nil
        },
        before: [
          %{
            id: "msg1",
            sender: "me@s.whatsapp.net",
            text: "Before message",
            timestamp: "2025-12-11 09:59:00",
            is_from_me: true,
            media_type: nil
          }
        ],
        after: [],
        chat_jid: "12025551234@s.whatsapp.net"
      }

      text = Formatters.format_message_context(context)

      assert String.contains?(text, "--- Before ---")
      assert String.contains?(text, "--- Target Message ---")
      refute String.contains?(text, "--- After ---")
    end
  end

  describe "format_last_interaction/3" do
    test "formats last interaction" do
      message = %{
        id: "msg1",
        chat_jid: "12025551234@s.whatsapp.net",
        chat_name: "Test Chat",
        sender: "12025551234@s.whatsapp.net",
        text: "Latest message",
        timestamp: "2025-12-11 10:00:00",
        is_from_me: false,
        media_type: nil
      }

      # Note: contact_name is looked up from database, so we just verify the JID appears
      text = Formatters.format_last_interaction(message, "test@s.whatsapp.net")

      assert String.contains?(text, "Last interaction with")
      assert String.contains?(text, "Latest message")
    end
  end

  describe "format_contact_chats/2" do
    test "formats empty contact chats" do
      text = Formatters.format_contact_chats([])

      assert text == "No chats found for this contact."
    end

    test "formats contact chats with direct and group chats" do
      chats = [
        %{
          jid: "12025551234@s.whatsapp.net",
          name: "Direct Chat",
          last_message_date: "2025-12-11 10:00:00",
          is_group: false
        },
        %{
          jid: "123456@g.us",
          name: "Group Chat",
          last_message_date: "2025-12-11 09:00:00",
          is_group: true
        }
      ]

      text = Formatters.format_contact_chats(chats)

      assert String.contains?(text, "Found 2 chats")
      assert String.contains?(text, "[Direct]")
      assert String.contains?(text, "[Group]")
    end
  end

  describe "format_download_result/1" do
    test "formats successful download" do
      result = {:ok, %{path: "/tmp/image.jpg", filename: "image.jpg", media_type: "image"}}

      {:ok, text} = Formatters.format_download_result(result)

      assert String.contains?(text, "Downloaded image")
      assert String.contains?(text, "image.jpg")
      assert String.contains?(text, "/tmp/image.jpg")
    end

    test "formats download error - not a media message" do
      result = {:error, "not a media message"}

      {:error, text} = Formatters.format_download_result(result)

      assert text == "not a media message"
    end

    test "formats download error - bridge not running" do
      result = {:error, :bridge_not_running}

      {:error, text} = Formatters.format_download_result(result)

      assert String.contains?(text, "bridge is not running")
    end

    test "formats download error - timeout" do
      result = {:error, :timeout}

      {:error, text} = Formatters.format_download_result(result)

      assert String.contains?(text, "timed out")
    end
  end

  describe "format_bridge_result/1" do
    test "passes through ok result" do
      result = {:ok, "Message sent"}

      {:ok, text} = Formatters.format_bridge_result(result)

      assert text == "Message sent"
    end

    test "formats bridge not running error" do
      result = {:error, :bridge_not_running}

      {:error, text} = Formatters.format_bridge_result(result)

      assert String.contains?(text, "bridge is not running")
    end

    test "formats timeout error" do
      result = {:error, :timeout}

      {:error, text} = Formatters.format_bridge_result(result)

      assert String.contains?(text, "timed out")
    end

    test "formats file not found error" do
      result = {:error, :file_not_found}

      {:error, text} = Formatters.format_bridge_result(result)

      assert String.contains?(text, "File not found")
    end

    test "formats invalid path error" do
      result = {:error, :invalid_path}

      {:error, text} = Formatters.format_bridge_result(result)

      assert String.contains?(text, "Invalid file path")
    end

    test "passes through string error" do
      result = {:error, "Custom error message"}

      {:error, text} = Formatters.format_bridge_result(result)

      assert text == "Custom error message"
    end

    test "formats atom error by inspection" do
      result = {:error, :some_unknown_error}

      {:error, text} = Formatters.format_bridge_result(result)

      assert text == ":some_unknown_error"
    end
  end

  describe "help_text/0" do
    test "returns help text with all sections" do
      text = Formatters.help_text()

      assert String.contains?(text, "WhatsApp MCP Tools")
      assert String.contains?(text, "Phone Number Format")
      assert String.contains?(text, "JID Types")
      assert String.contains?(text, "RECOMMENDED WORKFLOW")
      assert String.contains?(text, "list_chats")
      assert String.contains?(text, "search_contacts")
    end
  end

  describe "format_download_result/1 edge cases" do
    test "formats non-string error by inspection" do
      result = {:error, {:complex_error, %{reason: "test"}}}

      {:error, text} = Formatters.format_download_result(result)

      assert text == ~s({:complex_error, %{reason: "test"}})
    end
  end
end
