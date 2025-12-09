defmodule WhatsappMcp.TestSupport.DatabaseFixtures do
  @moduledoc """
  Shared test fixtures and helpers for database tests.

  Provides functions to create test databases with consistent schema
  and insert test data for WhatsApp MCP database tests.
  """

  @doc """
  Creates the database schema (chats, messages, and contacts tables).
  """
  @spec create_schema(Exqlite.Sqlite3.db()) :: :ok
  def create_schema(conn) do
    Exqlite.Sqlite3.execute(conn, """
    CREATE TABLE chats (
      jid TEXT PRIMARY KEY,
      name TEXT,
      last_message_time INTEGER
    )
    """)

    Exqlite.Sqlite3.execute(conn, """
    CREATE TABLE messages (
      id TEXT PRIMARY KEY,
      chat_jid TEXT,
      sender TEXT,
      content TEXT,
      timestamp INTEGER,
      is_from_me INTEGER,
      media_type TEXT,
      filename TEXT
    )
    """)

    Exqlite.Sqlite3.execute(conn, """
    CREATE TABLE contacts (
      jid TEXT PRIMARY KEY,
      phone TEXT,
      name TEXT,
      updated_at TEXT
    )
    """)

    :ok
  end

  @doc """
  Inserts a chat record into the database.
  Converts Unix timestamp to ISO8601 format to match production database.
  """
  @spec insert_chat(Exqlite.Sqlite3.db(), String.t(), String.t() | nil, integer()) :: :ok
  def insert_chat(conn, jid, name, last_message_time) do
    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, "INSERT INTO chats VALUES (?, ?, ?)")
    iso_timestamp = unix_to_iso8601(last_message_time)
    :ok = Exqlite.Sqlite3.bind(stmt, [jid, name, iso_timestamp])
    :done = Exqlite.Sqlite3.step(conn, stmt)
    :ok = Exqlite.Sqlite3.release(conn, stmt)
    :ok
  end

  # Convert Unix timestamp to ISO8601 string (UTC timezone)
  defp unix_to_iso8601(unix_timestamp) when is_integer(unix_timestamp) do
    unix_timestamp
    |> DateTime.from_unix!()
    |> DateTime.to_iso8601()
  end

  @doc """
  Inserts a contact record into the contacts cache table.
  Used for testing LID→phone resolution.
  """
  @spec insert_contact(Exqlite.Sqlite3.db(), String.t(), String.t() | nil, String.t() | nil) :: :ok
  def insert_contact(conn, jid, phone, name) do
    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, "INSERT INTO contacts VALUES (?, ?, ?, ?)")
    updated_at = DateTime.to_iso8601(DateTime.utc_now())
    :ok = Exqlite.Sqlite3.bind(stmt, [jid, phone, name, updated_at])
    :done = Exqlite.Sqlite3.step(conn, stmt)
    :ok = Exqlite.Sqlite3.release(conn, stmt)
    :ok
  end

  @doc """
  Inserts a message record into the database.
  Converts Unix timestamp to ISO8601 format to match production database.
  """
  @spec insert_message(
          Exqlite.Sqlite3.db(),
          String.t(),
          String.t(),
          String.t() | nil,
          String.t() | nil,
          integer(),
          integer(),
          String.t() | nil
        ) :: :ok
  def insert_message(conn, id, chat_jid, sender, content, timestamp, is_from_me, media_type) do
    {:ok, stmt} =
      Exqlite.Sqlite3.prepare(conn, "INSERT INTO messages VALUES (?, ?, ?, ?, ?, ?, ?, NULL)")

    # Convert Unix timestamp to ISO8601 string (production format)
    iso_timestamp = unix_to_iso8601(timestamp)

    :ok = Exqlite.Sqlite3.bind(stmt, [id, chat_jid, sender, content, iso_timestamp, is_from_me, media_type])
    :done = Exqlite.Sqlite3.step(conn, stmt)
    :ok = Exqlite.Sqlite3.release(conn, stmt)
    :ok
  end

  @doc """
  Creates an empty database with schema only.
  """
  @spec create_empty_database(String.t()) :: :ok
  def create_empty_database(path) do
    File.rm(path)
    {:ok, conn} = Exqlite.Sqlite3.open(path)
    create_schema(conn)
    Exqlite.Sqlite3.close(conn)
    :ok
  end

  @doc """
  Creates a database with a group chat for testing group exclusion.
  """
  @spec create_database_with_group(String.t()) :: :ok
  def create_database_with_group(path) do
    File.rm(path)
    {:ok, conn} = Exqlite.Sqlite3.open(path)
    create_schema(conn)

    # Insert individual chat
    insert_chat(conn, "test@s.whatsapp.net", "Test Contact", 1_705_752_000)
    # Insert group chat
    insert_chat(conn, "123456789@g.us", "Test Group", 1_705_752_000)

    Exqlite.Sqlite3.close(conn)
    :ok
  end

  @doc """
  Creates a database with a chat that has nil name.
  """
  @spec create_database_with_nil_name(String.t()) :: :ok
  def create_database_with_nil_name(path) do
    File.rm(path)
    {:ok, conn} = Exqlite.Sqlite3.open(path)
    create_schema(conn)

    # Insert chat with nil name
    insert_chat(conn, "12025551234@s.whatsapp.net", nil, 1_705_752_000)

    Exqlite.Sqlite3.close(conn)
    :ok
  end

  @doc """
  Creates the standard test database with sample chats and messages.

  Contains:
  - 3 chats (Recent, Middle, Old) ordered by last_message_time
  - Messages with various properties (from_me, media_type, etc.)
  """
  @spec create_standard_test_database(String.t()) :: :ok
  def create_standard_test_database(path) do
    File.rm(path)
    {:ok, conn} = Exqlite.Sqlite3.open(path)
    create_schema(conn)

    # Insert test chats
    # Recent: 2024-01-20 12:00:00 UTC = 1705752000
    # Middle: 2024-01-15 12:00:00 UTC = 1705320000
    # Old: 2024-01-10 12:00:00 UTC = 1704888000
    insert_chat(conn, "recent@s.whatsapp.net", "Recent Chat", 1_705_752_000)
    insert_chat(conn, "middle@s.whatsapp.net", "Middle Chat", 1_705_320_000)
    insert_chat(conn, "old@s.whatsapp.net", "Old Chat", 1_704_888_000)

    # Insert test messages
    # Recent chat: 2 messages
    insert_message(conn, "msg1", "recent@s.whatsapp.net", "John", "First message", 1_705_665_600, 0, nil)
    insert_message(conn, "msg2", "recent@s.whatsapp.net", nil, "Latest message", 1_705_752_000, 1, nil)

    # Middle chat: 1 message with media
    insert_message(conn, "msg3", "middle@s.whatsapp.net", "Jane", "Check this photo", 1_705_320_000, 0, "image")

    # Old chat: no messages with content (nil content simulates system message)

    Exqlite.Sqlite3.close(conn)
    :ok
  end

  @doc """
  Creates a database with sequential messages for context testing.

  Contains 11 messages with timestamps 10 seconds apart for testing
  get_message_context functionality.
  """
  @spec create_context_test_database(String.t()) :: :ok
  def create_context_test_database(path) do
    File.rm(path)
    {:ok, conn} = Exqlite.Sqlite3.open(path)
    create_schema(conn)

    # Insert chat
    insert_chat(conn, "context@s.whatsapp.net", "Context Chat", 1_705_752_000)

    # Insert 11 messages with sequential timestamps (10 second intervals)
    for i <- 0..10 do
      insert_message(
        conn,
        "ctx_msg_#{i}",
        "context@s.whatsapp.net",
        if(rem(i, 2) == 0, do: "Alice"),
        "Message #{i}",
        1_705_700_000 + i * 10,
        rem(i, 2),
        nil
      )
    end

    Exqlite.Sqlite3.close(conn)
    :ok
  end

  @doc """
  Creates a database with contacts for search testing.
  """
  @spec create_contacts_test_database(String.t()) :: :ok
  def create_contacts_test_database(path) do
    File.rm(path)
    {:ok, conn} = Exqlite.Sqlite3.open(path)
    create_schema(conn)

    # Insert test contacts
    insert_chat(conn, "12025551234@s.whatsapp.net", "John Doe", 1_705_752_000)
    insert_chat(conn, "12025555678@s.whatsapp.net", "Jane Smith", 1_705_320_000)

    Exqlite.Sqlite3.close(conn)
    :ok
  end

  @doc """
  Creates a database with a chat and message for get_chat testing.
  """
  @spec create_chat_test_database(String.t()) :: :ok
  def create_chat_test_database(path) do
    File.rm(path)
    {:ok, conn} = Exqlite.Sqlite3.open(path)
    create_schema(conn)

    insert_chat(conn, "12025551234@s.whatsapp.net", "John Doe", 1_705_752_000)
    insert_message(conn, "msg1", "12025551234@s.whatsapp.net", nil, "Hello there", 1_705_752_000, 1, nil)

    Exqlite.Sqlite3.close(conn)
    :ok
  end

  @doc """
  Creates a smaller context test database with 5 messages for tools testing.
  """
  @spec create_small_context_test_database(String.t()) :: :ok
  def create_small_context_test_database(path) do
    File.rm(path)
    {:ok, conn} = Exqlite.Sqlite3.open(path)
    create_schema(conn)

    insert_chat(conn, "context@s.whatsapp.net", "Context Test", 1_705_752_000)

    # Insert 5 messages
    for i <- 0..4 do
      insert_message(
        conn,
        "ctx_msg_#{i}",
        "context@s.whatsapp.net",
        if(rem(i, 2) == 0, do: "Alice"),
        "Message #{i}",
        1_705_700_000 + i * 10,
        rem(i, 2),
        nil
      )
    end

    Exqlite.Sqlite3.close(conn)
    :ok
  end

  @doc """
  Creates a database for testing get_last_interaction.
  Contains a direct chat with messages from Alice.
  """
  @spec create_interaction_test_database(String.t()) :: :ok
  def create_interaction_test_database(path) do
    File.rm(path)
    {:ok, conn} = Exqlite.Sqlite3.open(path)
    create_schema(conn)

    # Direct chat with Alice
    insert_chat(conn, "alice@s.whatsapp.net", "Alice", 1_705_752_000)

    # Messages with Alice (older to newer)
    insert_message(
      conn,
      "msg_alice_1",
      "alice@s.whatsapp.net",
      "alice@s.whatsapp.net",
      "First from Alice",
      1_705_700_000,
      0,
      nil
    )

    insert_message(conn, "msg_me_1", "alice@s.whatsapp.net", nil, "My reply", 1_705_700_100, 1, nil)

    insert_message(
      conn,
      "msg_alice_2",
      "alice@s.whatsapp.net",
      "alice@s.whatsapp.net",
      "Latest from Alice",
      1_705_752_000,
      0,
      nil
    )

    Exqlite.Sqlite3.close(conn)
    :ok
  end

  @doc """
  Creates a database for testing get_contact_chats.
  Contains direct chats and a group where contacts have sent messages.
  """
  @spec create_contact_chats_test_database(String.t()) :: :ok
  def create_contact_chats_test_database(path) do
    File.rm(path)
    {:ok, conn} = Exqlite.Sqlite3.open(path)
    create_schema(conn)

    # Direct chat with Bob
    insert_chat(conn, "bob@s.whatsapp.net", "Bob", 1_705_752_000)
    insert_message(conn, "msg_bob_1", "bob@s.whatsapp.net", "bob@s.whatsapp.net", "Hello from Bob", 1_705_752_000, 0, nil)

    # Group chat where Bob has sent messages
    insert_chat(conn, "group123@g.us", "Test Group", 1_705_700_000)
    insert_message(conn, "msg_group_bob", "group123@g.us", "bob@s.whatsapp.net", "Bob in group", 1_705_700_000, 0, nil)

    # Another direct chat (not involving Bob)
    insert_chat(conn, "carol@s.whatsapp.net", "Carol", 1_705_600_000)

    insert_message(
      conn,
      "msg_carol_1",
      "carol@s.whatsapp.net",
      "carol@s.whatsapp.net",
      "From Carol",
      1_705_600_000,
      0,
      nil
    )

    Exqlite.Sqlite3.close(conn)
    :ok
  end

  @doc """
  Creates a database for testing get_last_interaction when the most recent
  message is in a group chat (not a direct chat with the contact).
  """
  @spec create_group_interaction_test_database(String.t()) :: :ok
  def create_group_interaction_test_database(path) do
    File.rm(path)
    {:ok, conn} = Exqlite.Sqlite3.open(path)
    create_schema(conn)

    # Direct chat with Bob (older message)
    insert_chat(conn, "bob@s.whatsapp.net", "Bob", 1_705_700_000)

    insert_message(
      conn,
      "msg_bob_direct",
      "bob@s.whatsapp.net",
      "bob@s.whatsapp.net",
      "Old direct message",
      1_705_700_000,
      0,
      nil
    )

    # Group chat where Bob's most recent message is (newer)
    insert_chat(conn, "workgroup@g.us", "Work Group", 1_705_752_000)

    insert_message(
      conn,
      "msg_bob_group",
      "workgroup@g.us",
      "bob@s.whatsapp.net",
      "Recent group message",
      1_705_752_000,
      0,
      nil
    )

    Exqlite.Sqlite3.close(conn)
    :ok
  end

  @doc """
  Creates a database where a contact only appears in group chats (no direct chat).
  Used to test fallback to JID when no direct chat exists.
  """
  @spec create_group_only_test_database(String.t()) :: :ok
  def create_group_only_test_database(path) do
    File.rm(path)
    {:ok, conn} = Exqlite.Sqlite3.open(path)
    create_schema(conn)

    # Group chat where Charlie has sent messages (no direct chat with Charlie)
    insert_chat(conn, "randomgroup@g.us", "Random Group", 1_705_752_000)

    insert_message(
      conn,
      "msg_charlie_group",
      "randomgroup@g.us",
      "charlie@s.whatsapp.net",
      "Charlie in group",
      1_705_752_000,
      0,
      nil
    )

    Exqlite.Sqlite3.close(conn)
    :ok
  end

  @doc """
  Creates a database with @lid format contacts to test contact name enrichment.
  Contains:
  - An @lid chat with numeric ID as name (before enrichment)
  - A cached contact entry with the real name
  - A regular @s.whatsapp.net chat for comparison
  """
  @spec create_lid_enrichment_test_database(String.t()) :: :ok
  def create_lid_enrichment_test_database(path) do
    File.rm(path)
    {:ok, conn} = Exqlite.Sqlite3.open(path)
    create_schema(conn)

    # @lid chat with numeric ID as name (before enrichment)
    insert_chat(conn, "144555781402794@lid", "144555781402794", 1_705_752_000)

    insert_message(
      conn,
      "msg_lid_1",
      "144555781402794@lid",
      "144555781402794@lid",
      "Hello from LID",
      1_705_752_000,
      0,
      nil
    )

    # Cached contact entry with the real name (from enrichment)
    insert_contact(conn, "144555781402794@lid", "14155552345", "John Doe")

    # Regular @s.whatsapp.net chat for comparison
    insert_chat(conn, "12025551234@s.whatsapp.net", "Jane Smith", 1_705_700_000)
    insert_message(conn, "msg_jane_1", "12025551234@s.whatsapp.net", nil, "Hello from Jane", 1_705_700_000, 1, nil)

    # Another @lid chat without cached contact (should show numeric ID)
    insert_chat(conn, "999888777666555@lid", "999888777666555", 1_705_600_000)

    insert_message(
      conn,
      "msg_lid_2",
      "999888777666555@lid",
      "999888777666555@lid",
      "From unknown LID",
      1_705_600_000,
      0,
      nil
    )

    Exqlite.Sqlite3.close(conn)
    :ok
  end
end
