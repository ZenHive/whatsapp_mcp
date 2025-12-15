defmodule WhatsappMcp.Database.JidResolverTest do
  @moduledoc """
  Tests for WhatsappMcp.Database.JidResolver module.

  Tests both pure functions (jid_type, extract_phone_from_jid, phone_to_jid)
  and database-dependent functions (phone_jid_for_lid, lid_for_phone_jid, find_all_linked_jids).
  """
  use ExUnit.Case, async: true

  alias WhatsappMcp.Database.JidResolver
  alias WhatsappMcp.TestSupport.DatabaseFixtures

  describe "jid_type/1" do
    test "returns :phone_jid for @s.whatsapp.net format" do
      assert JidResolver.jid_type("12025551234@s.whatsapp.net") == :phone_jid
      assert JidResolver.jid_type("44123456789@s.whatsapp.net") == :phone_jid
    end

    test "returns :lid_jid for @lid format" do
      assert JidResolver.jid_type("144555781402794@lid") == :lid_jid
      assert JidResolver.jid_type("999888777666555@lid") == :lid_jid
    end

    test "returns :group_jid for @g.us format" do
      assert JidResolver.jid_type("120363123456789012@g.us") == :group_jid
      assert JidResolver.jid_type("123456789@g.us") == :group_jid
    end

    test "returns :unknown for unrecognized formats" do
      assert JidResolver.jid_type("invalid") == :unknown
      assert JidResolver.jid_type("user@example.com") == :unknown
      assert JidResolver.jid_type("") == :unknown
    end
  end

  describe "extract_phone_from_jid/1" do
    test "extracts phone number from @s.whatsapp.net JID" do
      assert JidResolver.extract_phone_from_jid("12025551234@s.whatsapp.net") == "12025551234"
      assert JidResolver.extract_phone_from_jid("44123456789@s.whatsapp.net") == "44123456789"
    end

    test "returns nil for @lid JID" do
      assert JidResolver.extract_phone_from_jid("144555781402794@lid") == nil
    end

    test "returns nil for @g.us JID" do
      assert JidResolver.extract_phone_from_jid("123456789@g.us") == nil
    end

    test "returns nil for unrecognized format" do
      assert JidResolver.extract_phone_from_jid("invalid") == nil
    end
  end

  describe "phone_to_jid/1" do
    test "converts phone number to @s.whatsapp.net JID" do
      assert JidResolver.phone_to_jid("12025551234") == "12025551234@s.whatsapp.net"
      assert JidResolver.phone_to_jid("44123456789") == "44123456789@s.whatsapp.net"
    end
  end

  describe "phone_jid_for_lid/2" do
    setup do
      db_path = "test/fixtures/jid_resolver_phone_test.db"
      File.rm(db_path)
      {:ok, conn} = Exqlite.Sqlite3.open(db_path)
      DatabaseFixtures.create_schema(conn)

      # Contact with cached phone
      DatabaseFixtures.insert_contact(conn, "144555781402794@lid", "14155552345", "John Doe")

      # Contact without phone (nil)
      DatabaseFixtures.insert_contact(conn, "999888777666555@lid", nil, "No Phone Contact")

      Exqlite.Sqlite3.close(conn)
      on_exit(fn -> File.rm(db_path) end)
      {:ok, db_path: db_path}
    end

    test "returns phone JID when LID has cached phone", %{db_path: db_path} do
      assert {:ok, "14155552345@s.whatsapp.net"} =
               JidResolver.phone_jid_for_lid("144555781402794@lid", db_path)
    end

    test "returns nil when LID has nil phone", %{db_path: db_path} do
      assert {:ok, nil} = JidResolver.phone_jid_for_lid("999888777666555@lid", db_path)
    end

    test "returns nil when LID not found in contacts", %{db_path: db_path} do
      assert {:ok, nil} = JidResolver.phone_jid_for_lid("nonexistent@lid", db_path)
    end

    test "returns error when database doesn't exist" do
      assert {:error, _reason} = JidResolver.phone_jid_for_lid("144555781402794@lid", "/nonexistent/path.db")
    end
  end

  describe "lid_for_phone_jid/2" do
    setup do
      db_path = "test/fixtures/jid_resolver_lid_test.db"
      File.rm(db_path)
      {:ok, conn} = Exqlite.Sqlite3.open(db_path)
      DatabaseFixtures.create_schema(conn)

      # Contact with @lid JID and phone
      DatabaseFixtures.insert_contact(conn, "144555781402794@lid", "14155552345", "John Doe")

      # Another contact with different phone
      DatabaseFixtures.insert_contact(conn, "888777666555444@lid", "12025559999", "Jane Smith")

      Exqlite.Sqlite3.close(conn)
      on_exit(fn -> File.rm(db_path) end)
      {:ok, db_path: db_path}
    end

    test "returns LID JID when phone JID has cached mapping", %{db_path: db_path} do
      assert {:ok, "144555781402794@lid"} =
               JidResolver.lid_for_phone_jid("14155552345@s.whatsapp.net", db_path)
    end

    test "returns nil when no LID exists for phone", %{db_path: db_path} do
      assert {:ok, nil} = JidResolver.lid_for_phone_jid("99999999999@s.whatsapp.net", db_path)
    end

    test "returns error when database doesn't exist" do
      assert {:error, _reason} = JidResolver.lid_for_phone_jid("14155552345@s.whatsapp.net", "/nonexistent/path.db")
    end
  end

  describe "find_all_linked_jids/2" do
    setup do
      db_path = "test/fixtures/jid_resolver_linked_test.db"
      File.rm(db_path)
      {:ok, conn} = Exqlite.Sqlite3.open(db_path)
      DatabaseFixtures.create_schema(conn)

      # Contact with both @lid and @s.whatsapp.net linked
      DatabaseFixtures.insert_contact(conn, "144555781402794@lid", "14155552345", "John Doe")

      # Contact with only @lid (phone cached)
      DatabaseFixtures.insert_contact(conn, "999888777666555@lid", "12025551234", "Jane Smith")

      # Contact with no cached phone (orphan @lid)
      DatabaseFixtures.insert_contact(conn, "111222333444555@lid", nil, "Unknown")

      Exqlite.Sqlite3.close(conn)
      on_exit(fn -> File.rm(db_path) end)
      {:ok, db_path: db_path}
    end

    test "returns both JIDs when starting from @s.whatsapp.net", %{db_path: db_path} do
      assert {:ok, jids} = JidResolver.find_all_linked_jids("14155552345@s.whatsapp.net", db_path)

      assert length(jids) == 2
      assert "14155552345@s.whatsapp.net" in jids
      assert "144555781402794@lid" in jids
    end

    test "returns both JIDs when starting from @lid", %{db_path: db_path} do
      assert {:ok, jids} = JidResolver.find_all_linked_jids("144555781402794@lid", db_path)

      assert length(jids) == 2
      assert "144555781402794@lid" in jids
      assert "14155552345@s.whatsapp.net" in jids
    end

    test "returns @s.whatsapp.net JID for @lid with cached phone", %{db_path: db_path} do
      assert {:ok, jids} = JidResolver.find_all_linked_jids("999888777666555@lid", db_path)

      assert length(jids) == 2
      assert "999888777666555@lid" in jids
      assert "12025551234@s.whatsapp.net" in jids
    end

    test "returns only input JID when @lid has no cached phone", %{db_path: db_path} do
      assert {:ok, jids} = JidResolver.find_all_linked_jids("111222333444555@lid", db_path)

      assert jids == ["111222333444555@lid"]
    end

    test "returns only input JID for @s.whatsapp.net with no linked @lid", %{db_path: db_path} do
      assert {:ok, jids} = JidResolver.find_all_linked_jids("99999999999@s.whatsapp.net", db_path)

      assert jids == ["99999999999@s.whatsapp.net"]
    end

    test "returns only input JID for group JIDs", %{db_path: db_path} do
      assert {:ok, jids} = JidResolver.find_all_linked_jids("group123@g.us", db_path)

      assert jids == ["group123@g.us"]
    end

    test "returns only input JID for unknown JID format", %{db_path: db_path} do
      assert {:ok, jids} = JidResolver.find_all_linked_jids("invalid-jid", db_path)

      assert jids == ["invalid-jid"]
    end

    test "gracefully returns input JID when database doesn't exist" do
      # Function is designed to be resilient - returns input JID on DB errors
      assert {:ok, jids} = JidResolver.find_all_linked_jids("144555781402794@lid", "/nonexistent/path.db")
      assert jids == ["144555781402794@lid"]
    end
  end
end
