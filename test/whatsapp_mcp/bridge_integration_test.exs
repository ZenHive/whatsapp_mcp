defmodule WhatsappMcp.BridgeIntegrationTest do
  @moduledoc """
  Integration tests for the Bridge module against the real Go bridge.

  Run with: mix test --include integration
  Send tests: mix test --include sends_message (sends real WhatsApp messages!)

  ## Test Configuration

  The `@test_recipient` is a real phone number used for send tests.
  Update this to your own test number before running `:sends_message` tests.
  """
  use ExUnit.Case, async: false

  alias WhatsappMcp.Bridge
  alias WhatsappMcp.Tools

  @moduletag :integration

  # Set WHATSAPP_TEST_RECIPIENT environment variable before running :sends_message tests
  # Example: export WHATSAPP_TEST_RECIPIENT="12025551234"
  @test_recipient System.get_env("WHATSAPP_TEST_RECIPIENT", "12025551234")

  setup do
    case Bridge.health_check() do
      {:ok, %{"connected" => true}} -> :ok
      {:ok, %{"connected" => false}} -> {:skip, "Bridge running but not connected to WhatsApp"}
      {:error, :bridge_not_running} -> {:skip, "Bridge not running at localhost:8080"}
    end
  end

  describe "read-only operations" do
    test "health_check returns connected" do
      assert {:ok, %{"connected" => true}} = Bridge.health_check()
    end

    test "send_message with invalid JID returns error" do
      assert {:error, msg} = Bridge.send_message("invalid-recipient", "Test")
      assert is_binary(msg) or is_atom(msg)
    end

    test "send_file with non-existent file returns error" do
      assert {:error, :file_not_found} = Bridge.send_file(@test_recipient, "/no/file.jpg")
    end

    test "download_media with invalid message ID returns error" do
      assert {:error, msg} = Bridge.download_media("INVALID_ID", "#{@test_recipient}@s.whatsapp.net")
      assert is_binary(msg) or is_atom(msg)
    end
  end

  describe "database read operations" do
    alias WhatsappMcp.Database

    test "get_message_context with real message ID" do
      # First, get some messages to find a real message ID
      case Database.list_chats(limit: 1) do
        {:ok, [chat | _]} ->
          case Database.get_messages(chat_id: chat.jid, limit: 5) do
            {:ok, [msg | _]} ->
              # Now test get_message_context with real message
              result = Database.get_message_context(message_id: msg.id)

              case result do
                {:ok, context} ->
                  assert context.target.id == msg.id
                  assert is_list(context.before)
                  assert is_list(context.after)
                  assert is_binary(context.chat_jid)

                {:error, reason} ->
                  # Some messages might not have context
                  assert reason in [:not_found, :message_id_required]
              end

            {:ok, []} ->
              # No messages in chat - skip
              :ok
          end

        {:ok, []} ->
          # No chats - skip
          :ok
      end
    end

    test "Tools.get_message_context with real data" do
      # Use the Tools interface to test end-to-end
      case Database.search_messages(query: "a", limit: 1) do
        {:ok, [result | _]} ->
          # Get a message with content
          case Database.get_messages(chat_id: result.chat_id, limit: 5) do
            {:ok, messages} when length(messages) >= 3 ->
              # Pick a middle message for context
              middle_msg = Enum.at(messages, div(length(messages), 2))

              case Tools.call_tool("get_message_context", %{"message_id" => middle_msg.id}) do
                {:ok, text} ->
                  assert is_binary(text)
                  assert String.contains?(text, "Context for message")

                {:error, reason} ->
                  # Message might not exist or have context
                  assert is_binary(reason)
              end

            _ ->
              :ok
          end

        {:ok, []} ->
          :ok
      end
    end
  end

  describe "contact and user operations" do
    test "check_whatsapp_registration with test recipient" do
      # Check if the test recipient is on WhatsApp
      assert {:ok, results} = Bridge.check_whatsapp_registration([@test_recipient])
      assert is_list(results)
      assert length(results) == 1

      result = hd(results)
      assert result.phone == @test_recipient
      assert is_boolean(result.is_on_whatsapp)

      if result.is_on_whatsapp do
        assert is_binary(result.jid)
        assert String.contains?(result.jid, "@")
      end
    end

    test "check_whatsapp_registration with multiple numbers" do
      # Test batch checking
      phones = [@test_recipient, "999999999999"]
      assert {:ok, results} = Bridge.check_whatsapp_registration(phones)
      assert length(results) == 2

      # Each result should have the expected structure
      Enum.each(results, fn result ->
        assert is_binary(result.phone)
        assert is_boolean(result.is_on_whatsapp)
      end)
    end

    test "get_profile_picture with valid JID" do
      # First, get a valid JID from test recipient
      case Bridge.check_whatsapp_registration([@test_recipient]) do
        {:ok, [%{is_on_whatsapp: true, jid: jid}]} when is_binary(jid) ->
          result = Bridge.get_profile_picture(jid)

          case result do
            {:ok, %{url: url, id: id}} ->
              # Has profile picture
              assert is_binary(url)
              assert String.starts_with?(url, "http")
              assert is_binary(id)

            {:error, msg} ->
              # No profile picture or privacy settings - acceptable
              assert is_binary(msg)
              assert String.contains?(msg, "profile picture") or String.contains?(msg, "privacy")
          end

        {:ok, [%{is_on_whatsapp: false}]} ->
          # Test recipient not on WhatsApp - skip
          :ok

        {:error, _reason} ->
          # Bridge error - skip
          :ok
      end
    end

    test "get_blocklist returns list" do
      assert {:ok, blocklist} = Bridge.get_blocklist()
      assert is_list(blocklist)

      # Each entry should be a JID string
      Enum.each(blocklist, fn jid ->
        assert is_binary(jid)
        assert String.contains?(jid, "@")
      end)
    end

    test "Tools.call_tool is_on_whatsapp" do
      result = Tools.call_tool("is_on_whatsapp", %{"phones" => [@test_recipient]})

      case result do
        {:ok, text} ->
          assert is_binary(text)
          assert String.contains?(text, "WhatsApp Registration Status")
          assert String.contains?(text, @test_recipient)

        {:error, reason} ->
          # Unexpected error
          flunk("Expected success, got error: #{inspect(reason)}")
      end
    end

    test "Tools.call_tool get_blocklist" do
      assert {:ok, text} = Tools.call_tool("get_blocklist", %{})
      assert is_binary(text)
      # Either has blocked contacts or is empty
      assert String.contains?(text, "Blocked Contacts") or String.contains?(text, "blocklist is empty")
    end
  end

  describe "group admin operations (read-only tests)" do
    test "update_group_name with invalid JID returns error" do
      assert {:error, msg} = Bridge.update_group_name("invalid-jid", "Test Name")
      assert is_binary(msg) or is_atom(msg)
    end

    test "update_group_name with non-group JID returns error" do
      # Individual chat JID, not a group
      assert {:error, msg} = Bridge.update_group_name("12025551234@s.whatsapp.net", "Test Name")
      assert is_binary(msg)
      assert String.contains?(msg, "group") or String.contains?(msg, "@g.us")
    end

    test "update_group_description with invalid JID returns error" do
      assert {:error, msg} = Bridge.update_group_description("invalid-jid", "Test description")
      assert is_binary(msg) or is_atom(msg)
    end

    test "update_group_settings with invalid JID returns error" do
      assert {:error, msg} = Bridge.update_group_settings("invalid-jid", locked: true)
      assert is_binary(msg) or is_atom(msg)
    end

    test "update_group_participants with invalid JID returns error" do
      assert {:error, msg} = Bridge.update_group_participants("invalid-jid", ["12025551234@s.whatsapp.net"], "add")
      assert is_binary(msg) or is_atom(msg)
    end

    test "update_group_participants with invalid action returns error" do
      assert {:error, msg} =
               Bridge.update_group_participants(
                 "120363123456789012@g.us",
                 ["12025551234@s.whatsapp.net"],
                 "invalid_action"
               )

      assert is_binary(msg)
    end

    test "Tools.call_tool update_group_name validates group JID" do
      result =
        Tools.call_tool("update_group_name", %{
          "jid" => "12025551234@s.whatsapp.net",
          "name" => "Test"
        })

      assert {:error, msg} = result
      assert String.contains?(msg, "group") or String.contains?(msg, "@g.us")
    end

    test "Tools.call_tool manage_group_members validates action" do
      result =
        Tools.call_tool("manage_group_members", %{
          "jid" => "120363123456789012@g.us",
          "participants" => ["12025551234@s.whatsapp.net"],
          "action" => "invalid"
        })

      assert {:error, msg} = result
      assert String.contains?(msg, "add") or String.contains?(msg, "remove")
    end

    test "Tools.call_tool update_group_settings requires at least one setting" do
      result =
        Tools.call_tool("update_group_settings", %{
          "jid" => "120363123456789012@g.us"
        })

      assert {:error, msg} = result
      assert String.contains?(msg, "locked") or String.contains?(msg, "announce")
    end
  end

  describe "send operations (sends real messages!)" do
    @describetag :sends_message

    @tag timeout: 30_000
    test "send_message and send_file to test recipient" do
      # Send text message
      msg = "MCP test #{DateTime.utc_now()}"
      assert {:ok, resp} = Bridge.send_message(@test_recipient, msg)
      assert String.contains?(resp, @test_recipient)

      # Send file
      tmp = Path.join(System.tmp_dir!(), "mcp_test.txt")
      File.write!(tmp, "Test file content")
      assert {:ok, resp} = Bridge.send_file(@test_recipient, tmp, "Test caption")
      File.rm!(tmp)
      assert String.contains?(resp, @test_recipient)
    end

    @tag timeout: 30_000
    test "Tools.call_tool send_message to test recipient" do
      msg = "MCP tool test #{DateTime.utc_now()}"

      assert {:ok, resp} =
               Tools.call_tool("send_message", %{"recipient" => @test_recipient, "message" => msg})

      assert String.contains?(resp, @test_recipient)
    end

    @tag timeout: 30_000
    test "Tools.call_tool send_audio_message to test recipient" do
      # Create a minimal valid OGG file for testing
      # Note: This won't play as actual audio but tests the API path
      tmp = Path.join(System.tmp_dir!(), "mcp_test_voice.ogg")
      File.write!(tmp, "OggS test audio content")

      result =
        Tools.call_tool("send_audio_message", %{
          "recipient" => @test_recipient,
          "file_path" => tmp
        })

      File.rm!(tmp)

      # May succeed or fail with format error depending on bridge validation
      case result do
        {:ok, resp} ->
          assert String.contains?(resp, @test_recipient)

        {:error, reason} ->
          # Bridge may reject invalid OGG format - that's acceptable
          assert is_binary(reason)
          assert String.contains?(reason, "Ogg") or String.contains?(reason, "audio")
      end
    end
  end
end
