defmodule WhatsappMcp.ConfigTest do
  use ExUnit.Case, async: true

  alias WhatsappMcp.Config

  describe "database_path/1" do
    test "returns default path when no options provided" do
      path = Config.database_path()

      assert String.ends_with?(path, "bridge/store/messages.db")
    end

    test "returns custom path when :path option provided" do
      custom_path = "/custom/path/to/messages.db"

      assert Config.database_path(path: custom_path) == custom_path
    end

    test "returns default path when empty options provided" do
      path = Config.database_path([])

      assert String.ends_with?(path, "bridge/store/messages.db")
    end
  end

  describe "database_exists?/1" do
    test "returns true when database file exists" do
      # Create a temporary file
      tmp_path = Path.join(System.tmp_dir!(), "test_messages_#{:rand.uniform(1_000_000)}.db")

      try do
        File.write!(tmp_path, "test content")

        assert Config.database_exists?(path: tmp_path) == true
      after
        File.rm(tmp_path)
      end
    end

    test "returns false when database file does not exist" do
      non_existent_path = "/non/existent/path/messages.db"

      assert Config.database_exists?(path: non_existent_path) == false
    end

    test "returns false when path is a directory" do
      # System.tmp_dir! returns a directory path
      dir_path = System.tmp_dir!()

      assert Config.database_exists?(path: dir_path) == false
    end

    test "uses default path when no options provided" do
      # This tests the integration with database_path/1
      # Result depends on whether the actual database exists
      result = Config.database_exists?()

      assert is_boolean(result)
    end
  end

  describe "bridge_source_path/0" do
    test "returns path ending with bridge" do
      path = Config.bridge_source_path()

      assert String.ends_with?(path, "bridge")
    end
  end

  describe "bridge_binary_path/0" do
    test "returns path ending with whatsapp-bridge" do
      path = Config.bridge_binary_path()

      assert String.ends_with?(path, "bridge/whatsapp-bridge")
    end
  end

  describe "bridge_store_path/0" do
    test "returns path ending with store" do
      path = Config.bridge_store_path()

      assert String.ends_with?(path, "bridge/store")
    end
  end
end
