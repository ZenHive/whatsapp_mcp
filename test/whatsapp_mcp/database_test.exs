defmodule WhatsappMcp.DatabaseTest do
  @moduledoc """
  Tests for WhatsappMcp.Database module.

  Uses a temporary SQLite database with test fixtures to verify query behavior.
  """
  use ExUnit.Case, async: true

  alias WhatsappMcp.Database
  alias WhatsappMcp.TestSupport.DatabaseFixtures

  @test_db_dir "test/fixtures"
  @test_db_path "test/fixtures/test_messages.db"

  setup_all do
    # Ensure fixtures directory exists
    File.mkdir_p!(@test_db_dir)

    # Create test database with schema and test data
    DatabaseFixtures.create_standard_test_database(@test_db_path)

    on_exit(fn ->
      File.rm(@test_db_path)
    end)

    :ok
  end

  describe "list_chats/1" do
    test "returns chats ordered by last_message_time descending" do
      assert {:ok, chats} = Database.list_chats(db_path: @test_db_path)

      assert length(chats) == 3

      # Should be ordered by most recent first
      [first, second, third] = chats
      assert first.name == "Recent Chat"
      assert second.name == "Middle Chat"
      assert third.name == "Old Chat"
    end

    test "includes last message preview" do
      assert {:ok, [first | _]} = Database.list_chats(db_path: @test_db_path)

      assert first.last_message == "Latest message"
      assert first.jid == "recent@s.whatsapp.net"
    end

    test "respects limit option" do
      assert {:ok, chats} = Database.list_chats(limit: 2, db_path: @test_db_path)

      assert length(chats) == 2
    end

    test "returns empty list for empty database" do
      empty_db = "test/fixtures/empty.db"
      DatabaseFixtures.create_empty_database(empty_db)

      assert {:ok, []} = Database.list_chats(db_path: empty_db)

      File.rm(empty_db)
    end

    test "returns error when database does not exist" do
      assert {:error, _reason} = Database.list_chats(db_path: "/nonexistent/path.db")
    end

    test "supports pagination with offset" do
      # Get first page (first 2)
      assert {:ok, first_page} = Database.list_chats(limit: 2, offset: 0, db_path: @test_db_path)
      assert length(first_page) == 2
      assert hd(first_page).name == "Recent Chat"

      # Get second page (skip first 2)
      assert {:ok, second_page} = Database.list_chats(limit: 2, offset: 2, db_path: @test_db_path)
      assert length(second_page) == 1
      assert hd(second_page).name == "Old Chat"

      # Get page beyond data
      assert {:ok, empty_page} = Database.list_chats(limit: 2, offset: 10, db_path: @test_db_path)
      assert empty_page == []
    end
  end

  describe "get_messages/1" do
    test "returns messages by chat_id" do
      assert {:ok, messages} = Database.get_messages(chat_id: "recent@s.whatsapp.net", db_path: @test_db_path)

      assert length(messages) == 2
      # Should be ordered by timestamp ascending
      [first, second] = messages
      assert first.text == "First message"
      assert second.text == "Latest message"
    end

    test "returns messages by chat_name partial match" do
      assert {:ok, messages} = Database.get_messages(chat_name: "Recent", db_path: @test_db_path)

      assert length(messages) == 2
    end

    test "returns error when chat name not found" do
      assert {:error, {:chat_not_found, "NonExistent"}} =
               Database.get_messages(chat_name: "NonExistent", db_path: @test_db_path)
    end

    test "returns error when neither chat_id nor chat_name provided" do
      assert {:error, :chat_id_or_name_required} = Database.get_messages(db_path: @test_db_path)
    end

    test "respects limit option" do
      assert {:ok, messages} =
               Database.get_messages(chat_id: "recent@s.whatsapp.net", limit: 1, db_path: @test_db_path)

      assert length(messages) == 1
    end

    test "filters by before timestamp" do
      # Timestamp 1705752000 is 2024-01-20 12:00:00 UTC (Latest message)
      # Timestamp 1705665600 is 2024-01-19 12:00:00 UTC (First message)
      # We want messages before 2024-01-20, so use a timestamp between them
      assert {:ok, messages} =
               Database.get_messages(
                 chat_id: "recent@s.whatsapp.net",
                 before: "2024-01-20 00:00:00",
                 db_path: @test_db_path
               )

      # Only message before 2024-01-20 00:00:00 (the First message from 2024-01-19)
      assert length(messages) == 1
      assert hd(messages).text == "First message"
    end

    test "includes is_from_me flag correctly" do
      assert {:ok, messages} = Database.get_messages(chat_id: "recent@s.whatsapp.net", db_path: @test_db_path)

      from_me = Enum.find(messages, & &1.is_from_me)
      not_from_me = Enum.find(messages, &(!&1.is_from_me))

      assert from_me.sender == "Me"
      assert not_from_me.sender == "John"
    end

    test "includes media_type when present" do
      assert {:ok, messages} = Database.get_messages(chat_id: "middle@s.whatsapp.net", db_path: @test_db_path)

      media_message = Enum.find(messages, &(&1.media_type == "image"))
      assert media_message
    end

    test "supports pagination with offset (most recent first)" do
      pagination_db = "test/fixtures/pagination_messages.db"
      DatabaseFixtures.create_context_test_database(pagination_db)

      # Database has messages 0-10 (oldest to newest by timestamp)
      # Pagination returns most recent first, then re-sorts chronologically for display

      # First page: most recent 5 messages (6-10), displayed chronologically
      assert {:ok, first_page} =
               Database.get_messages(chat_id: "context@s.whatsapp.net", limit: 5, offset: 0, db_path: pagination_db)

      assert length(first_page) == 5
      # Messages are returned in chronological order (ASC) for display
      assert hd(first_page).text == "Message 6"
      assert List.last(first_page).text == "Message 10"

      # Second page: next 5 most recent (1-5), displayed chronologically
      assert {:ok, second_page} =
               Database.get_messages(chat_id: "context@s.whatsapp.net", limit: 5, offset: 5, db_path: pagination_db)

      assert length(second_page) == 5
      assert hd(second_page).text == "Message 1"
      assert List.last(second_page).text == "Message 5"

      # Third page: remaining oldest message (0)
      assert {:ok, third_page} =
               Database.get_messages(chat_id: "context@s.whatsapp.net", limit: 5, offset: 10, db_path: pagination_db)

      assert length(third_page) == 1
      assert hd(third_page).text == "Message 0"

      # Page beyond data
      assert {:ok, empty_page} =
               Database.get_messages(chat_id: "context@s.whatsapp.net", limit: 5, offset: 20, db_path: pagination_db)

      assert empty_page == []

      File.rm(pagination_db)
    end

    test "pagination works with chat_name (most recent first)" do
      pagination_db = "test/fixtures/pagination_by_name.db"
      DatabaseFixtures.create_context_test_database(pagination_db)

      # Database has 11 messages (0-10), offset 2 skips 2 most recent (9, 10)
      # Returns next 3 most recent (6, 7, 8), displayed chronologically
      assert {:ok, messages} =
               Database.get_messages(chat_name: "Context", limit: 3, offset: 2, db_path: pagination_db)

      assert length(messages) == 3
      assert hd(messages).text == "Message 6"
      assert List.last(messages).text == "Message 8"

      File.rm(pagination_db)
    end
  end

  describe "search_messages/1" do
    test "searches across all chats" do
      assert {:ok, results} = Database.search_messages(query: "message", db_path: @test_db_path)

      # Should find messages from multiple chats
      assert length(results) >= 2
    end

    test "returns results with chat context" do
      assert {:ok, [result | _]} = Database.search_messages(query: "Latest", db_path: @test_db_path)

      assert result.chat_name == "Recent Chat"
      assert result.chat_id == "recent@s.whatsapp.net"
      assert result.text == "Latest message"
      # Task 15: Now includes message ID and media type
      assert result.id == "msg2"
      assert result.media_type == nil
    end

    test "returns results with media type" do
      assert {:ok, [result | _]} = Database.search_messages(query: "photo", db_path: @test_db_path)

      assert result.chat_name == "Middle Chat"
      assert result.id == "msg3"
      assert result.media_type == "image"
    end

    test "filters by chat_id when provided" do
      assert {:ok, results} =
               Database.search_messages(
                 query: "message",
                 chat_id: "recent@s.whatsapp.net",
                 db_path: @test_db_path
               )

      # All results should be from the specified chat
      assert Enum.all?(results, &(&1.chat_id == "recent@s.whatsapp.net"))
    end

    test "respects limit option" do
      assert {:ok, results} = Database.search_messages(query: "message", limit: 1, db_path: @test_db_path)

      assert length(results) == 1
    end

    test "returns error when query not provided" do
      assert {:error, :query_required} = Database.search_messages(db_path: @test_db_path)
    end

    test "returns empty list when no matches" do
      assert {:ok, []} = Database.search_messages(query: "zzznomatchzzz", db_path: @test_db_path)
    end
  end

  describe "clean_message handling" do
    test "handles nil messages gracefully" do
      assert {:ok, chats} = Database.list_chats(db_path: @test_db_path)

      # Old chat has nil last_message
      old_chat = Enum.find(chats, &(&1.name == "Old Chat"))
      assert old_chat.last_message == nil
    end
  end

  describe "LIKE pattern escaping" do
    test "search_messages escapes percent signs in query" do
      # A query containing % should be treated literally, not as a wildcard
      assert {:ok, []} = Database.search_messages(query: "100%", db_path: @test_db_path)
    end

    test "search_messages escapes underscores in query" do
      # A query containing _ should be treated literally, not as a single-char wildcard
      assert {:ok, []} = Database.search_messages(query: "test_value", db_path: @test_db_path)
    end

    test "search_contacts escapes special characters in query" do
      # Should not match anything when searching for literal %
      assert {:ok, []} = Database.search_contacts(query: "50%", db_path: @test_db_path)
    end

    test "get_messages by name escapes special characters" do
      # Should not find chat when % is in the search
      assert {:error, {:chat_not_found, "Test%Chat"}} =
               Database.get_messages(chat_name: "Test%Chat", db_path: @test_db_path)
    end
  end

  describe "search_contacts/1" do
    test "returns contacts matching name" do
      assert {:ok, contacts} = Database.search_contacts(query: "Recent", db_path: @test_db_path)

      assert length(contacts) == 1
      [contact] = contacts
      assert contact.name == "Recent Chat"
      assert contact.jid == "recent@s.whatsapp.net"
      assert contact.phone == "recent"
    end

    test "returns contacts matching phone number in JID" do
      assert {:ok, contacts} = Database.search_contacts(query: "middle", db_path: @test_db_path)

      assert length(contacts) == 1
      [contact] = contacts
      assert contact.jid == "middle@s.whatsapp.net"
    end

    test "excludes group chats" do
      group_db = "test/fixtures/group_test.db"
      DatabaseFixtures.create_database_with_group(group_db)

      # Search for something that would match both individual and group
      assert {:ok, contacts} = Database.search_contacts(query: "Test", db_path: group_db)

      # Should only find the individual chat, not the group
      assert length(contacts) == 1
      assert hd(contacts).jid == "test@s.whatsapp.net"

      File.rm(group_db)
    end

    test "respects limit option" do
      assert {:ok, contacts} = Database.search_contacts(query: "Chat", limit: 1, db_path: @test_db_path)

      assert length(contacts) == 1
    end

    test "returns empty list when no matches" do
      assert {:ok, []} = Database.search_contacts(query: "zzznomatchzzz", db_path: @test_db_path)
    end

    test "returns error when query not provided" do
      assert {:error, :query_required} = Database.search_contacts(db_path: @test_db_path)
    end

    test "extracts phone from JID correctly" do
      assert {:ok, contacts} = Database.search_contacts(query: "recent", db_path: @test_db_path)

      [contact] = contacts
      assert contact.phone == "recent"
    end

    test "uses phone as name when name is nil" do
      nil_name_db = "test/fixtures/nil_name.db"
      DatabaseFixtures.create_database_with_nil_name(nil_name_db)

      assert {:ok, contacts} = Database.search_contacts(query: "12025551234", db_path: nil_name_db)

      [contact] = contacts
      assert contact.name == "12025551234"
      assert contact.phone == "12025551234"

      File.rm(nil_name_db)
    end
  end

  describe "get_chat/1" do
    test "returns chat by JID" do
      assert {:ok, chat} = Database.get_chat(jid: "recent@s.whatsapp.net", db_path: @test_db_path)

      assert chat.jid == "recent@s.whatsapp.net"
      assert chat.name == "Recent Chat"
      assert chat.last_message == "Latest message"
      assert chat.last_message_date
    end

    test "returns error when chat not found" do
      assert {:error, :not_found} = Database.get_chat(jid: "nonexistent@s.whatsapp.net", db_path: @test_db_path)
    end

    test "returns error when JID not provided" do
      assert {:error, :jid_required} = Database.get_chat(db_path: @test_db_path)
    end

    test "handles chat with nil name" do
      nil_name_db = "test/fixtures/get_chat_nil_name.db"
      DatabaseFixtures.create_database_with_nil_name(nil_name_db)

      assert {:ok, chat} = Database.get_chat(jid: "12025551234@s.whatsapp.net", db_path: nil_name_db)

      # Should fallback to JID as name
      assert chat.name == "12025551234@s.whatsapp.net"

      File.rm(nil_name_db)
    end

    test "handles group chat JID" do
      group_db = "test/fixtures/get_chat_group.db"
      DatabaseFixtures.create_database_with_group(group_db)

      assert {:ok, chat} = Database.get_chat(jid: "123456789@g.us", db_path: group_db)

      assert chat.jid == "123456789@g.us"
      assert chat.name == "Test Group"

      File.rm(group_db)
    end
  end

  describe "get_chat_by_name/1" do
    test "returns chat by partial name match" do
      assert {:ok, chat} = Database.get_chat_by_name(name: "Recent", db_path: @test_db_path)

      assert chat.jid == "recent@s.whatsapp.net"
      assert chat.name == "Recent Chat"
      assert chat.last_message == "Latest message"
      assert chat.last_message_date
    end

    test "returns most recently active match when multiple chats match" do
      # Both "Recent Chat" and "Middle Chat" contain "Chat"
      # Should return "Recent Chat" as it's most recently active
      assert {:ok, chat} = Database.get_chat_by_name(name: "Chat", db_path: @test_db_path)

      assert chat.name == "Recent Chat"
    end

    test "returns error when no chat matches name" do
      assert {:error, :not_found} = Database.get_chat_by_name(name: "NonExistent", db_path: @test_db_path)
    end

    test "returns error when name not provided" do
      assert {:error, :name_required} = Database.get_chat_by_name(db_path: @test_db_path)
    end

    test "handles case-sensitive matching" do
      # SQLite LIKE is case-insensitive by default
      assert {:ok, chat} = Database.get_chat_by_name(name: "recent", db_path: @test_db_path)
      assert chat.name == "Recent Chat"
    end

    test "escapes special LIKE characters in name" do
      # Should not match anything when searching for literal %
      assert {:error, :not_found} = Database.get_chat_by_name(name: "100%", db_path: @test_db_path)
    end
  end

  describe "get_chat_by_phone/1" do
    test "returns chat by phone number" do
      phone_db = "test/fixtures/get_chat_phone.db"
      DatabaseFixtures.create_chat_test_database(phone_db)

      assert {:ok, chat} = Database.get_chat_by_phone(phone: "12025551234", db_path: phone_db)

      assert chat.jid == "12025551234@s.whatsapp.net"
      assert chat.name == "John Doe"
      assert chat.last_message == "Hello there"

      File.rm(phone_db)
    end

    test "returns error when no chat for phone" do
      assert {:error, :not_found} = Database.get_chat_by_phone(phone: "99999999999", db_path: @test_db_path)
    end

    test "returns error when phone not provided" do
      assert {:error, :phone_required} = Database.get_chat_by_phone(db_path: @test_db_path)
    end
  end

  describe "get_message_context/1" do
    setup do
      context_db = "test/fixtures/context_test.db"
      DatabaseFixtures.create_context_test_database(context_db)

      on_exit(fn -> File.rm(context_db) end)

      {:ok, context_db: context_db}
    end

    test "returns target message with before and after context", %{context_db: context_db} do
      # Get context for message #5 (middle message)
      assert {:ok, context} = Database.get_message_context(message_id: "ctx_msg_5", db_path: context_db)

      assert context.target.id == "ctx_msg_5"
      assert context.target.text == "Message 5"
      assert context.chat_jid == "context@s.whatsapp.net"

      # Default: 5 messages before and 5 after
      assert length(context.before) == 5
      assert length(context.after) == 5

      # Verify chronological order of before messages
      before_ids = Enum.map(context.before, & &1.id)
      assert before_ids == ["ctx_msg_0", "ctx_msg_1", "ctx_msg_2", "ctx_msg_3", "ctx_msg_4"]

      # Verify chronological order of after messages
      after_ids = Enum.map(context.after, & &1.id)
      assert after_ids == ["ctx_msg_6", "ctx_msg_7", "ctx_msg_8", "ctx_msg_9", "ctx_msg_10"]
    end

    test "respects custom before count", %{context_db: context_db} do
      assert {:ok, context} =
               Database.get_message_context(message_id: "ctx_msg_5", before: 2, db_path: context_db)

      assert length(context.before) == 2
      before_ids = Enum.map(context.before, & &1.id)
      assert before_ids == ["ctx_msg_3", "ctx_msg_4"]
    end

    test "respects custom after count", %{context_db: context_db} do
      assert {:ok, context} =
               Database.get_message_context(message_id: "ctx_msg_5", after: 3, db_path: context_db)

      assert length(context.after) == 3
      after_ids = Enum.map(context.after, & &1.id)
      assert after_ids == ["ctx_msg_6", "ctx_msg_7", "ctx_msg_8"]
    end

    test "handles first message (no before messages)", %{context_db: context_db} do
      assert {:ok, context} = Database.get_message_context(message_id: "ctx_msg_0", db_path: context_db)

      assert context.target.id == "ctx_msg_0"
      assert context.before == []
      assert length(context.after) == 5
    end

    test "handles last message (no after messages)", %{context_db: context_db} do
      assert {:ok, context} = Database.get_message_context(message_id: "ctx_msg_10", db_path: context_db)

      assert context.target.id == "ctx_msg_10"
      assert length(context.before) == 5
      assert context.after == []
    end

    test "returns error when message not found", %{context_db: context_db} do
      assert {:error, :not_found} =
               Database.get_message_context(message_id: "nonexistent_msg", db_path: context_db)
    end

    test "returns error when message_id not provided" do
      assert {:error, :message_id_required} = Database.get_message_context(db_path: @test_db_path)
    end

    test "includes is_from_me flag correctly", %{context_db: context_db} do
      assert {:ok, context} = Database.get_message_context(message_id: "ctx_msg_5", db_path: context_db)

      # Message 5 is from me (odd index, is_from_me = rem(5, 2) = 1)
      assert context.target.is_from_me == true
      assert context.target.sender == "Me"

      # Message 4 is not from me (even index)
      msg_4 = Enum.find(context.before, &(&1.id == "ctx_msg_4"))
      assert msg_4.is_from_me == false
      assert msg_4.sender == "Alice"
    end

    test "handles message with media_type", %{context_db: context_db} do
      # Add a message with media
      {:ok, conn} = Exqlite.Sqlite3.open(context_db)

      DatabaseFixtures.insert_message(
        conn,
        "media_msg",
        "context@s.whatsapp.net",
        "Bob",
        "Photo",
        1_705_700_055,
        0,
        "image"
      )

      Exqlite.Sqlite3.close(conn)

      assert {:ok, context} = Database.get_message_context(message_id: "media_msg", db_path: context_db)

      assert context.target.media_type == "image"
    end
  end

  describe "get_last_interaction/1" do
    setup do
      interaction_db = "test/fixtures/interaction_test.db"
      DatabaseFixtures.create_interaction_test_database(interaction_db)
      on_exit(fn -> File.rm(interaction_db) end)
      {:ok, interaction_db: interaction_db}
    end

    test "returns most recent message with contact", %{interaction_db: interaction_db} do
      assert {:ok, message} =
               Database.get_last_interaction(contact_jid: "alice@s.whatsapp.net", db_path: interaction_db)

      assert message.id == "msg_alice_2"
      assert message.text == "Latest from Alice"
      assert message.chat_jid == "alice@s.whatsapp.net"
      assert message.chat_name == "Alice"
    end

    test "returns error when contact_jid not provided" do
      assert {:error, :contact_jid_required} = Database.get_last_interaction(db_path: @test_db_path)
    end

    test "returns error when no messages found", %{interaction_db: interaction_db} do
      assert {:error, :not_found} =
               Database.get_last_interaction(contact_jid: "nonexistent@s.whatsapp.net", db_path: interaction_db)
    end

    test "includes is_from_me flag correctly", %{interaction_db: interaction_db} do
      assert {:ok, message} =
               Database.get_last_interaction(contact_jid: "alice@s.whatsapp.net", db_path: interaction_db)

      # The latest message is from Alice (not from me)
      assert message.is_from_me == false
      assert message.sender == "alice@s.whatsapp.net"
    end
  end

  describe "get_contact_chats/1" do
    setup do
      contact_chats_db = "test/fixtures/contact_chats_test.db"
      DatabaseFixtures.create_contact_chats_test_database(contact_chats_db)
      on_exit(fn -> File.rm(contact_chats_db) end)
      {:ok, contact_chats_db: contact_chats_db}
    end

    test "returns direct chat and groups for contact", %{contact_chats_db: contact_chats_db} do
      assert {:ok, chats} =
               Database.get_contact_chats(contact_jid: "bob@s.whatsapp.net", db_path: contact_chats_db)

      # Bob appears in direct chat and group
      assert length(chats) == 2

      direct = Enum.find(chats, &(!&1.is_group))
      group = Enum.find(chats, & &1.is_group)

      assert direct.jid == "bob@s.whatsapp.net"
      assert direct.name == "Bob"
      assert group.jid == "group123@g.us"
      assert group.name == "Test Group"
    end

    test "returns error when contact_jid not provided" do
      assert {:error, :contact_jid_required} = Database.get_contact_chats(db_path: @test_db_path)
    end

    test "returns empty list when contact has no chats", %{contact_chats_db: contact_chats_db} do
      assert {:ok, []} =
               Database.get_contact_chats(contact_jid: "nonexistent@s.whatsapp.net", db_path: contact_chats_db)
    end

    test "respects limit option", %{contact_chats_db: contact_chats_db} do
      assert {:ok, chats} =
               Database.get_contact_chats(contact_jid: "bob@s.whatsapp.net", limit: 1, db_path: contact_chats_db)

      assert length(chats) == 1
    end

    test "correctly identifies group chats", %{contact_chats_db: contact_chats_db} do
      assert {:ok, chats} =
               Database.get_contact_chats(contact_jid: "bob@s.whatsapp.net", db_path: contact_chats_db)

      group = Enum.find(chats, & &1.is_group)
      direct = Enum.find(chats, &(!&1.is_group))

      assert group
      assert group.is_group == true

      assert direct
      assert direct.is_group == false
    end
  end

  describe "get_cached_contact/1" do
    setup do
      cache_db = "test/fixtures/contact_cache_test.db"
      File.rm(cache_db)
      {:ok, conn} = Exqlite.Sqlite3.open(cache_db)
      DatabaseFixtures.create_schema(conn)

      # Insert a cached contact
      DatabaseFixtures.insert_contact(conn, "144555781402794@lid", "14155552345", "John Doe")

      Exqlite.Sqlite3.close(conn)
      on_exit(fn -> File.rm(cache_db) end)
      {:ok, cache_db: cache_db}
    end

    test "returns cached contact by JID", %{cache_db: cache_db} do
      assert {:ok, contact} =
               Database.get_cached_contact(jid: "144555781402794@lid", db_path: cache_db)

      assert contact.jid == "144555781402794@lid"
      assert contact.phone == "14155552345"
      assert contact.name == "John Doe"
      assert contact.updated_at
    end

    test "returns error when JID not found", %{cache_db: cache_db} do
      assert {:error, :not_found} =
               Database.get_cached_contact(jid: "nonexistent@lid", db_path: cache_db)
    end

    test "returns error when JID not provided" do
      assert {:error, :jid_required} = Database.get_cached_contact(db_path: @test_db_path)
    end
  end

  describe "find_contact_by_phone/1" do
    setup do
      phone_db = "test/fixtures/contact_phone_test.db"
      File.rm(phone_db)
      {:ok, conn} = Exqlite.Sqlite3.open(phone_db)
      DatabaseFixtures.create_schema(conn)

      # Insert cached contacts with different phones
      DatabaseFixtures.insert_contact(conn, "123456@lid", "14155552345", "John Doe")
      DatabaseFixtures.insert_contact(conn, "789012@lid", "12025551234", "Jane Smith")

      Exqlite.Sqlite3.close(conn)
      on_exit(fn -> File.rm(phone_db) end)
      {:ok, phone_db: phone_db}
    end

    test "finds contact by exact phone match", %{phone_db: phone_db} do
      assert {:ok, contact} =
               Database.find_contact_by_phone(phone: "14155552345", db_path: phone_db)

      assert contact.jid == "123456@lid"
      assert contact.phone == "14155552345"
      assert contact.name == "John Doe"
    end

    test "finds contact by partial phone match", %{phone_db: phone_db} do
      assert {:ok, contact} =
               Database.find_contact_by_phone(phone: "5552345", db_path: phone_db)

      assert contact.phone == "14155552345"
    end

    test "returns error when phone not found", %{phone_db: phone_db} do
      assert {:error, :not_found} =
               Database.find_contact_by_phone(phone: "9999999999", db_path: phone_db)
    end

    test "returns error when phone not provided" do
      assert {:error, :phone_required} = Database.find_contact_by_phone(db_path: @test_db_path)
    end
  end

  describe "search_contacts with LID cache" do
    setup do
      lid_search_db = "test/fixtures/lid_search_test.db"
      File.rm(lid_search_db)
      {:ok, conn} = Exqlite.Sqlite3.open(lid_search_db)
      DatabaseFixtures.create_schema(conn)

      # Insert a chat with LID format (no phone in JID)
      DatabaseFixtures.insert_chat(conn, "144555781402794@lid", "Unknown Contact", 1_705_752_000)

      # Insert cached contact with phone number for that LID
      DatabaseFixtures.insert_contact(conn, "144555781402794@lid", "14155552345", "John Doe")

      # Insert a regular chat (phone number in JID)
      DatabaseFixtures.insert_chat(conn, "12025551234@s.whatsapp.net", "Jane Smith", 1_705_320_000)

      Exqlite.Sqlite3.close(conn)
      on_exit(fn -> File.rm(lid_search_db) end)
      {:ok, lid_search_db: lid_search_db}
    end

    test "finds LID contact by cached phone number", %{lid_search_db: lid_search_db} do
      assert {:ok, contacts} =
               Database.search_contacts(query: "14155552345", db_path: lid_search_db)

      assert length(contacts) == 1
      contact = hd(contacts)
      assert contact.jid == "144555781402794@lid"
      assert contact.phone == "14155552345"
      assert contact.name == "John Doe"
    end

    test "finds LID contact by cached name", %{lid_search_db: lid_search_db} do
      assert {:ok, contacts} =
               Database.search_contacts(query: "John Doe", db_path: lid_search_db)

      assert length(contacts) == 1
      contact = hd(contacts)
      assert contact.jid == "144555781402794@lid"
      assert contact.name == "John Doe"
    end

    test "prefers cached name over chat name", %{lid_search_db: lid_search_db} do
      # The chat has name "Unknown Contact" but cache has "John Doe"
      assert {:ok, contacts} =
               Database.search_contacts(query: "144555781402794", db_path: lid_search_db)

      assert length(contacts) == 1
      contact = hd(contacts)
      assert contact.name == "John Doe"
    end

    test "finds regular contacts by JID phone", %{lid_search_db: lid_search_db} do
      assert {:ok, contacts} =
               Database.search_contacts(query: "12025551234", db_path: lid_search_db)

      assert length(contacts) == 1
      contact = hd(contacts)
      assert contact.jid == "12025551234@s.whatsapp.net"
      assert contact.phone == "12025551234"
    end
  end

  describe "contact name enrichment for @lid chats" do
    setup do
      lid_db = "test/fixtures/lid_enrichment_test.db"
      DatabaseFixtures.create_lid_enrichment_test_database(lid_db)
      on_exit(fn -> File.rm(lid_db) end)
      {:ok, lid_db: lid_db}
    end

    test "list_chats shows enriched name for @lid contact with cached name", %{lid_db: lid_db} do
      assert {:ok, chats} = Database.list_chats(db_path: lid_db)

      # Find the LID chat with cached contact
      lid_chat = Enum.find(chats, &(&1.jid == "144555781402794@lid"))
      assert lid_chat
      # Should show "John Doe" from contacts cache, not "144555781402794" from chat name
      assert lid_chat.name == "John Doe"
    end

    test "list_chats shows numeric ID for @lid contact without cached name", %{lid_db: lid_db} do
      assert {:ok, chats} = Database.list_chats(db_path: lid_db)

      # Find the LID chat without cached contact
      uncached_lid = Enum.find(chats, &(&1.jid == "999888777666555@lid"))
      assert uncached_lid
      # Should fall back to chat name (numeric ID)
      assert uncached_lid.name == "999888777666555"
    end

    test "get_chat shows enriched name for @lid contact", %{lid_db: lid_db} do
      assert {:ok, chat} = Database.get_chat(jid: "144555781402794@lid", db_path: lid_db)

      # Should show "John Doe" from contacts cache
      assert chat.name == "John Doe"
      assert chat.jid == "144555781402794@lid"
    end

    test "get_chat_by_name finds @lid contact by cached name", %{lid_db: lid_db} do
      assert {:ok, chat} = Database.get_chat_by_name(name: "John Doe", db_path: lid_db)

      assert chat.jid == "144555781402794@lid"
      assert chat.name == "John Doe"
    end

    test "get_chat_by_name searches both chat name and contact name", %{lid_db: lid_db} do
      # Should find Jane Smith by her chat name
      assert {:ok, jane} = Database.get_chat_by_name(name: "Jane", db_path: lid_db)
      assert jane.jid == "12025551234@s.whatsapp.net"
      assert jane.name == "Jane Smith"

      # Should find John Doe by his cached contact name (not chat name "144555781402794")
      assert {:ok, john} = Database.get_chat_by_name(name: "John", db_path: lid_db)
      assert john.jid == "144555781402794@lid"
      assert john.name == "John Doe"
    end
  end

  # Task 19: Tests for count functions (AI-friendliness pagination support)

  describe "count_chats/1" do
    test "returns total count of chats" do
      assert {:ok, count} = Database.count_chats(db_path: @test_db_path)

      # Standard test database has 3 chats
      assert count == 3
    end

    test "returns 0 for empty database" do
      empty_db = "test/fixtures/count_empty.db"
      DatabaseFixtures.create_empty_database(empty_db)

      assert {:ok, 0} = Database.count_chats(db_path: empty_db)

      File.rm(empty_db)
    end

    test "returns error when database does not exist" do
      assert {:error, _reason} = Database.count_chats(db_path: "/nonexistent/path.db")
    end
  end

  describe "count_contact_chats/1" do
    setup do
      contact_chats_db = "test/fixtures/count_contact_chats_test.db"
      DatabaseFixtures.create_contact_chats_test_database(contact_chats_db)
      on_exit(fn -> File.rm(contact_chats_db) end)
      {:ok, contact_chats_db: contact_chats_db}
    end

    test "returns count of chats for contact", %{contact_chats_db: contact_chats_db} do
      # Bob appears in direct chat and one group
      assert {:ok, count} =
               Database.count_contact_chats(contact_jid: "bob@s.whatsapp.net", db_path: contact_chats_db)

      assert count == 2
    end

    test "returns 0 when contact has no chats", %{contact_chats_db: contact_chats_db} do
      assert {:ok, 0} =
               Database.count_contact_chats(contact_jid: "nonexistent@s.whatsapp.net", db_path: contact_chats_db)
    end

    test "returns error when contact_jid not provided" do
      assert {:error, :contact_jid_required} = Database.count_contact_chats(db_path: @test_db_path)
    end
  end

  describe "count_messages/1" do
    test "returns count of messages by chat_id" do
      assert {:ok, count} =
               Database.count_messages(chat_id: "recent@s.whatsapp.net", db_path: @test_db_path)

      # recent@s.whatsapp.net has 2 messages in standard test database
      assert count == 2
    end

    test "returns count of messages by chat_name" do
      assert {:ok, count} =
               Database.count_messages(chat_name: "Recent", db_path: @test_db_path)

      assert count == 2
    end

    test "respects before timestamp filter" do
      # Only messages before 2024-01-20 00:00:00
      assert {:ok, count} =
               Database.count_messages(
                 chat_id: "recent@s.whatsapp.net",
                 before: "2024-01-20 00:00:00",
                 db_path: @test_db_path
               )

      # Only "First message" from 2024-01-19
      assert count == 1
    end

    test "respects after timestamp filter" do
      # Only messages after 2024-01-19 00:00:00
      assert {:ok, count} =
               Database.count_messages(
                 chat_id: "recent@s.whatsapp.net",
                 after: "2024-01-19 00:00:00",
                 db_path: @test_db_path
               )

      # Both messages are after 2024-01-19 00:00:00
      assert count == 2
    end

    test "returns 0 when chat has no messages" do
      assert {:ok, count} =
               Database.count_messages(chat_id: "old@s.whatsapp.net", db_path: @test_db_path)

      # old@s.whatsapp.net has no messages in standard test database
      assert count == 0
    end

    test "returns error when neither chat_id nor chat_name provided" do
      assert {:error, :chat_id_or_name_required} = Database.count_messages(db_path: @test_db_path)
    end

    test "returns error when chat_name not found" do
      assert {:error, {:chat_not_found, "NonExistent"}} =
               Database.count_messages(chat_name: "NonExistent", db_path: @test_db_path)
    end
  end

  describe "count_search_results/1" do
    test "returns count of matching messages" do
      assert {:ok, count} = Database.count_search_results(query: "message", db_path: @test_db_path)

      # Multiple messages contain "message"
      assert count >= 2
    end

    test "filters by chat_id when provided" do
      assert {:ok, count} =
               Database.count_search_results(
                 query: "message",
                 chat_id: "recent@s.whatsapp.net",
                 db_path: @test_db_path
               )

      # Only messages from recent@s.whatsapp.net
      assert count == 2
    end

    test "filters by has_media when true" do
      assert {:ok, count} =
               Database.count_search_results(has_media: true, db_path: @test_db_path)

      # Standard test database has 1 message with media (photo in middle chat)
      assert count == 1
    end

    test "combines query and has_media filters" do
      assert {:ok, count} =
               Database.count_search_results(query: "photo", has_media: true, db_path: @test_db_path)

      # Only the photo message matches both criteria
      assert count == 1
    end

    test "returns 0 when no matches" do
      assert {:ok, 0} = Database.count_search_results(query: "zzznomatchzzz", db_path: @test_db_path)
    end

    test "returns error when query not provided and has_media is false" do
      assert {:error, :query_required} = Database.count_search_results(db_path: @test_db_path)
    end
  end

  describe "count_contacts/1" do
    test "returns count of matching contacts" do
      assert {:ok, count} = Database.count_contacts(query: "Chat", db_path: @test_db_path)

      # Standard test database has 3 contacts with "Chat" in name
      # But excludes group chats, so actual count may vary
      assert count >= 1
    end

    test "excludes group chats" do
      group_db = "test/fixtures/count_group_test.db"
      DatabaseFixtures.create_database_with_group(group_db)

      # Search for something that would match both individual and group
      assert {:ok, count} = Database.count_contacts(query: "Test", db_path: group_db)

      # Should only count the individual chat, not the group
      assert count == 1

      File.rm(group_db)
    end

    test "returns 0 when no matches" do
      assert {:ok, 0} = Database.count_contacts(query: "zzznomatchzzz", db_path: @test_db_path)
    end

    test "returns error when query not provided" do
      assert {:error, :query_required} = Database.count_contacts(db_path: @test_db_path)
    end
  end

  # Task 5: Tests for LID linking functionality

  describe "find_linked_jids/1" do
    setup do
      linked_db = "test/fixtures/linked_jids_test.db"
      File.rm(linked_db)
      {:ok, conn} = Exqlite.Sqlite3.open(linked_db)
      DatabaseFixtures.create_schema(conn)

      # Create a contact with both @lid and @s.whatsapp.net representation
      # @lid chat: 144555781402794@lid
      # @s.whatsapp.net chat: 14155552345@s.whatsapp.net
      # Both represent the same person (John Doe, phone: 14155552345)
      DatabaseFixtures.insert_chat(conn, "144555781402794@lid", "John Doe", 1_705_752_000)
      DatabaseFixtures.insert_chat(conn, "14155552345@s.whatsapp.net", "John Doe", 1_705_700_000)
      DatabaseFixtures.insert_contact(conn, "144555781402794@lid", "14155552345", "John Doe")

      # Create a contact with only @lid (no @s.whatsapp.net chat exists, but phone is cached)
      DatabaseFixtures.insert_chat(conn, "999888777666555@lid", "Jane Smith", 1_705_600_000)
      DatabaseFixtures.insert_contact(conn, "999888777666555@lid", "12025551234", "Jane Smith")

      # Create a contact with only @s.whatsapp.net (no @lid exists)
      DatabaseFixtures.insert_chat(conn, "44123456789@s.whatsapp.net", "Bob Wilson", 1_705_500_000)

      # Create a group chat (should not have linked JIDs)
      DatabaseFixtures.insert_chat(conn, "group123@g.us", "Test Group", 1_705_400_000)

      Exqlite.Sqlite3.close(conn)
      on_exit(fn -> File.rm(linked_db) end)
      {:ok, linked_db: linked_db}
    end

    test "returns input JID when no linked JIDs found", %{linked_db: linked_db} do
      # Bob has no @lid contact cached
      assert {:ok, jids} =
               Database.find_linked_jids(jid: "44123456789@s.whatsapp.net", db_path: linked_db)

      assert jids == ["44123456789@s.whatsapp.net"]
    end

    test "returns linked @lid JID when starting from @s.whatsapp.net", %{linked_db: linked_db} do
      # John Doe has both @s.whatsapp.net and @lid
      assert {:ok, jids} =
               Database.find_linked_jids(jid: "14155552345@s.whatsapp.net", db_path: linked_db)

      assert length(jids) == 2
      assert "14155552345@s.whatsapp.net" in jids
      assert "144555781402794@lid" in jids
    end

    test "returns linked @s.whatsapp.net JID when starting from @lid", %{linked_db: linked_db} do
      # John Doe has both @lid and @s.whatsapp.net
      assert {:ok, jids} =
               Database.find_linked_jids(jid: "144555781402794@lid", db_path: linked_db)

      assert length(jids) == 2
      assert "144555781402794@lid" in jids
      assert "14155552345@s.whatsapp.net" in jids
    end

    test "returns @s.whatsapp.net JID even when chat doesn't exist (phone is known)", %{linked_db: linked_db} do
      # Jane Smith has @lid chat and cached phone, but no @s.whatsapp.net chat
      assert {:ok, jids} =
               Database.find_linked_jids(jid: "999888777666555@lid", db_path: linked_db)

      # Should include both the input @lid and the constructed @s.whatsapp.net JID
      # The @s.whatsapp.net JID is included because the phone mapping is known (from cache)
      # This enables sending messages to the correct JID even if no chat exists yet
      assert length(jids) == 2
      assert "999888777666555@lid" in jids
      assert "12025551234@s.whatsapp.net" in jids
    end

    test "returns only input JID for group chats", %{linked_db: linked_db} do
      assert {:ok, jids} =
               Database.find_linked_jids(jid: "group123@g.us", db_path: linked_db)

      assert jids == ["group123@g.us"]
    end

    test "returns error when JID not provided" do
      assert {:error, :jid_required} = Database.find_linked_jids(db_path: @test_db_path)
    end
  end

  describe "get_linked_jid/1" do
    setup do
      linked_jid_db = "test/fixtures/get_linked_jid_test.db"
      File.rm(linked_jid_db)
      {:ok, conn} = Exqlite.Sqlite3.open(linked_jid_db)
      DatabaseFixtures.create_schema(conn)

      # Create a contact with both @lid and @s.whatsapp.net
      DatabaseFixtures.insert_chat(conn, "144555781402794@lid", "John Doe", 1_705_752_000)
      DatabaseFixtures.insert_chat(conn, "14155552345@s.whatsapp.net", "John Doe", 1_705_700_000)
      DatabaseFixtures.insert_contact(conn, "144555781402794@lid", "14155552345", "John Doe")

      # Create a contact with only @s.whatsapp.net (no cached @lid)
      DatabaseFixtures.insert_chat(conn, "44123456789@s.whatsapp.net", "Bob Wilson", 1_705_500_000)

      # Create a contact with only @lid (no @s.whatsapp.net)
      DatabaseFixtures.insert_chat(conn, "999888777666555@lid", "Jane Smith", 1_705_600_000)
      DatabaseFixtures.insert_contact(conn, "999888777666555@lid", "12025551234", "Jane Smith")

      Exqlite.Sqlite3.close(conn)
      on_exit(fn -> File.rm(linked_jid_db) end)
      {:ok, linked_jid_db: linked_jid_db}
    end

    test "returns @s.whatsapp.net JID when starting from @lid", %{linked_jid_db: linked_jid_db} do
      assert {:ok, linked_jid} =
               Database.get_linked_jid(jid: "144555781402794@lid", db_path: linked_jid_db)

      assert linked_jid == "14155552345@s.whatsapp.net"
    end

    test "returns @lid JID when starting from @s.whatsapp.net", %{linked_jid_db: linked_jid_db} do
      assert {:ok, linked_jid} =
               Database.get_linked_jid(jid: "14155552345@s.whatsapp.net", db_path: linked_jid_db)

      assert linked_jid == "144555781402794@lid"
    end

    test "returns nil when no linked @lid exists for @s.whatsapp.net", %{linked_jid_db: linked_jid_db} do
      assert {:ok, nil} =
               Database.get_linked_jid(jid: "44123456789@s.whatsapp.net", db_path: linked_jid_db)
    end

    test "returns @s.whatsapp.net JID for @lid with cached phone", %{linked_jid_db: linked_jid_db} do
      assert {:ok, linked_jid} =
               Database.get_linked_jid(jid: "999888777666555@lid", db_path: linked_jid_db)

      # Jane has cached phone 12025551234, so should return that as @s.whatsapp.net
      assert linked_jid == "12025551234@s.whatsapp.net"
    end

    test "returns nil for group JIDs", %{linked_jid_db: linked_jid_db} do
      # Add a group chat for testing
      {:ok, conn} = Exqlite.Sqlite3.open(linked_jid_db)
      DatabaseFixtures.insert_chat(conn, "group123@g.us", "Test Group", 1_705_400_000)
      Exqlite.Sqlite3.close(conn)

      assert {:ok, nil} =
               Database.get_linked_jid(jid: "group123@g.us", db_path: linked_jid_db)
    end

    test "returns error when JID not provided" do
      assert {:error, :jid_required} = Database.get_linked_jid(db_path: @test_db_path)
    end
  end

  describe "get_messages/1 unified message view (LID linking)" do
    setup do
      unified_db = "test/fixtures/unified_messages_test.db"
      File.rm(unified_db)
      {:ok, conn} = Exqlite.Sqlite3.open(unified_db)
      DatabaseFixtures.create_schema(conn)

      # Create chats for both JID formats (same person)
      DatabaseFixtures.insert_chat(conn, "144555781402794@lid", "John Doe", 1_705_752_000)
      DatabaseFixtures.insert_chat(conn, "14155552345@s.whatsapp.net", "John Doe", 1_705_700_000)

      # Cache the contact to establish the link
      DatabaseFixtures.insert_contact(conn, "144555781402794@lid", "14155552345", "John Doe")

      # Insert messages to BOTH JIDs (simulating the duplicate thread problem)
      # Messages to @s.whatsapp.net (older conversation)
      DatabaseFixtures.insert_message(
        conn,
        "msg_phone_1",
        "14155552345@s.whatsapp.net",
        nil,
        "Hello from phone JID",
        1_705_600_000,
        1,
        nil
      )

      DatabaseFixtures.insert_message(
        conn,
        "msg_phone_2",
        "14155552345@s.whatsapp.net",
        "14155552345@s.whatsapp.net",
        "Reply from phone JID",
        1_705_650_000,
        0,
        nil
      )

      # Messages to @lid (newer conversation - this is the fragmentation!)
      DatabaseFixtures.insert_message(
        conn,
        "msg_lid_1",
        "144555781402794@lid",
        "144555781402794@lid",
        "Hello from LID",
        1_705_700_000,
        0,
        nil
      )

      DatabaseFixtures.insert_message(
        conn,
        "msg_lid_2",
        "144555781402794@lid",
        nil,
        "Reply from me to LID",
        1_705_750_000,
        1,
        nil
      )

      Exqlite.Sqlite3.close(conn)
      on_exit(fn -> File.rm(unified_db) end)
      {:ok, unified_db: unified_db}
    end

    test "merges messages from linked JIDs when querying by @s.whatsapp.net", %{unified_db: unified_db} do
      assert {:ok, messages} =
               Database.get_messages(chat_id: "14155552345@s.whatsapp.net", db_path: unified_db)

      # Should get all 4 messages from both JIDs merged
      assert length(messages) == 4

      # Messages should be in chronological order
      texts = Enum.map(messages, & &1.text)
      assert texts == ["Hello from phone JID", "Reply from phone JID", "Hello from LID", "Reply from me to LID"]
    end

    test "merges messages from linked JIDs when querying by @lid", %{unified_db: unified_db} do
      assert {:ok, messages} =
               Database.get_messages(chat_id: "144555781402794@lid", db_path: unified_db)

      # Should get all 4 messages from both JIDs merged
      assert length(messages) == 4

      # Messages should be in chronological order
      texts = Enum.map(messages, & &1.text)
      assert texts == ["Hello from phone JID", "Reply from phone JID", "Hello from LID", "Reply from me to LID"]
    end

    test "includes source_jid field only for messages from linked (non-primary) JID", %{unified_db: unified_db} do
      assert {:ok, messages} =
               Database.get_messages(chat_id: "14155552345@s.whatsapp.net", db_path: unified_db)

      # Messages from the primary JID (@s.whatsapp.net) should NOT have source_jid
      # (to avoid redundancy - the chat_id already tells us it's from that JID)
      phone_msgs = Enum.filter(messages, &(not Map.has_key?(&1, :source_jid)))
      assert length(phone_msgs) == 2

      # Messages from linked JID (@lid) should have source_jid showing their origin
      lid_msgs = Enum.filter(messages, &(Map.get(&1, :source_jid) == "144555781402794@lid"))
      assert length(lid_msgs) == 2
    end

    test "respects limit when merging messages", %{unified_db: unified_db} do
      assert {:ok, messages} =
               Database.get_messages(chat_id: "14155552345@s.whatsapp.net", limit: 2, db_path: unified_db)

      # Should get only 2 most recent messages (from the merged set)
      assert length(messages) == 2

      # Most recent should be the LID messages (based on limit+offset logic returning most recent first)
      texts = Enum.map(messages, & &1.text)
      assert texts == ["Hello from LID", "Reply from me to LID"]
    end

    test "count_messages returns total from all linked JIDs", %{unified_db: unified_db} do
      assert {:ok, count} =
               Database.count_messages(chat_id: "14155552345@s.whatsapp.net", db_path: unified_db)

      # Should count messages from both linked JIDs
      assert count == 4
    end
  end
end
