defmodule WhatsappMcp.Database.Chats do
  @moduledoc """
  Chat-related database queries.

  Provides functions for listing, retrieving, and searching chats.
  """

  alias WhatsappMcp.Config
  alias WhatsappMcp.Database.Helpers

  # Public types

  @typedoc "A chat with metadata"
  @type chat :: %{
          jid: String.t(),
          name: String.t(),
          last_message: String.t() | nil,
          last_message_date: String.t() | nil
        }

  @typedoc "A chat with message count (returned by get_chat/1)"
  @type chat_with_count :: %{
          jid: String.t(),
          name: String.t(),
          last_message: String.t() | nil,
          last_message_date: String.t() | nil,
          message_count: non_neg_integer()
        }

  @typedoc "A contact's chat entry (returned by get_contact_chats/1)"
  @type contact_chat :: %{
          jid: String.t(),
          name: String.t(),
          is_group: boolean(),
          last_message_date: String.t() | nil
        }

  @default_chat_limit 50

  @doc """
  Counts total chats with non-empty names.

  ## Options

    * `:db_path` - Override database path (useful for testing)

  ## Returns

  Total count of chats that would be returned by `list_chats/1`.

  """
  @spec count_chats(keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  def count_chats(opts \\ []) do
    db_path = Config.database_path(path: Keyword.get(opts, :db_path))

    query = """
    SELECT COUNT(*) FROM chats
    WHERE name IS NOT NULL AND name != ''
    """

    with {:ok, [[count]]} <- Helpers.with_readonly_connection(db_path, query, []) do
      {:ok, count}
    end
  end

  @doc """
  Counts all chats involving a specific contact.

  ## Options

    * `:contact_jid` - Contact JID (required)
    * `:db_path` - Override database path

  ## Returns

  Total count of chats (direct + groups) involving the contact.

  """
  @spec count_contact_chats(keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  def count_contact_chats(opts \\ []) do
    contact_jid = Keyword.get(opts, :contact_jid)
    db_path = Config.database_path(path: Keyword.get(opts, :db_path))

    if contact_jid do
      do_count_contact_chats(contact_jid, db_path)
    else
      {:error, :contact_jid_required}
    end
  end

  @doc """
  Lists all chats with their JIDs, names, and last message preview.

  ## Options

    * `:limit` - Maximum number of chats to return (default: 50)
    * `:offset` - Number of chats to skip for pagination (default: 0)
    * `:db_path` - Override database path (useful for testing)

  ## Returns

  A list of maps with keys:
    * `:jid` - Chat JID (use this for get_messages)
    * `:name` - Contact or group name
    * `:last_message` - Preview of last message
    * `:last_message_date` - ISO8601 timestamp of last message

  ## Pagination

  Use `offset` and `limit` together for pagination:
  - Page 0: `offset: 0, limit: 50`
  - Page 1: `offset: 50, limit: 50`
  - Page N: `offset: N * limit, limit: 50`

  Returns an empty list when past the last page.

  """
  @spec list_chats(keyword()) :: {:ok, [chat()]} | {:error, term()}
  def list_chats(opts \\ []) do
    limit = Keyword.get(opts, :limit, @default_chat_limit)
    offset = Keyword.get(opts, :offset, 0)
    db_path = Config.database_path(path: Keyword.get(opts, :db_path))

    # Get last message via subquery instead of exact timestamp join
    # (timestamps may not match exactly between chats and messages tables)
    # JOIN with contacts table to get enriched names for @lid contacts
    query = """
    SELECT
      c.jid,
      c.name,
      ct.name as contact_name,
      (SELECT m.content FROM messages m
       WHERE m.chat_jid = c.jid
       ORDER BY m.timestamp DESC LIMIT 1) as last_message,
      c.last_message_time as last_message_date
    FROM chats c
    LEFT JOIN contacts ct ON c.jid = ct.jid
    WHERE c.name IS NOT NULL AND c.name != ''
    ORDER BY c.last_message_time DESC
    LIMIT ?
    OFFSET ?
    """

    with {:ok, rows} <- Helpers.with_readonly_connection(db_path, query, [limit, offset]) do
      chats =
        Enum.map(rows, fn [jid, name, contact_name, last_message, last_message_date] ->
          # Prefer contact_name (from contacts cache) over chat name for better display
          # This is especially useful for @lid contacts where chat name might be numeric
          display_name = contact_name || name || jid

          %{
            jid: jid,
            name: display_name,
            last_message: Helpers.clean_message(last_message),
            last_message_date: last_message_date
          }
        end)

      {:ok, chats}
    end
  end

  @doc """
  Gets a single chat by JID.

  ## Options

    * `:jid` - Chat JID (required)
    * `:db_path` - Override database path

  ## Returns

  A map with keys:
    * `:jid` - Chat JID
    * `:name` - Contact or group name
    * `:last_message` - Preview of last message
    * `:last_message_date` - ISO8601 timestamp of last message

  Returns `{:error, :not_found}` if chat doesn't exist.

  """
  @spec get_chat(keyword()) :: {:ok, chat_with_count()} | {:error, term()}
  def get_chat(opts \\ []) do
    jid = Keyword.get(opts, :jid)
    db_path = Config.database_path(path: Keyword.get(opts, :db_path))

    if jid do
      do_get_chat(jid, db_path)
    else
      {:error, :jid_required}
    end
  end

  @doc """
  Gets a chat by phone number.

  Finds the individual (non-group) chat for the given phone number.

  ## Options

    * `:phone` - Phone number (required, e.g., "12025551234")
    * `:db_path` - Override database path

  ## Returns

  A map with keys:
    * `:jid` - Chat JID
    * `:name` - Contact name
    * `:last_message` - Preview of last message
    * `:last_message_date` - ISO8601 timestamp of last message

  Returns `{:error, :not_found}` if no chat exists for this phone.

  """
  @spec get_chat_by_phone(keyword()) :: {:ok, chat_with_count()} | {:error, term()}
  def get_chat_by_phone(opts \\ []) do
    phone = Keyword.get(opts, :phone)
    db_path = Config.database_path(path: Keyword.get(opts, :db_path))

    if phone do
      do_get_chat_by_phone(phone, db_path)
    else
      {:error, :phone_required}
    end
  end

  @doc """
  Gets a chat by partial name match.

  Searches for a chat where the name contains the given search term.
  Returns the most recently active match.

  ## Options

    * `:name` - Partial name to search for (required)
    * `:db_path` - Override database path

  ## Returns

  A map with keys:
    * `:jid` - Chat JID
    * `:name` - Contact or group name
    * `:last_message` - Preview of last message
    * `:last_message_date` - ISO8601 timestamp of last message

  Returns `{:error, :not_found}` if no matching chat exists.

  """
  @spec get_chat_by_name(keyword()) :: {:ok, chat()} | {:error, term()}
  def get_chat_by_name(opts \\ []) do
    name = Keyword.get(opts, :name)
    db_path = Config.database_path(path: Keyword.get(opts, :db_path))

    if name do
      do_get_chat_by_name(name, db_path)
    else
      {:error, :name_required}
    end
  end

  @doc """
  Lists all chats involving a specific contact, including groups.

  ## Options

    * `:contact_jid` - Contact JID (required)
    * `:limit` - Maximum number of chats to return (default: 50)
    * `:db_path` - Override database path

  ## Returns

  A list of maps with keys:
    * `:jid` - Chat JID
    * `:name` - Chat name
    * `:is_group` - Whether this is a group chat
    * `:last_message_date` - ISO8601 timestamp of last message

  For direct chats, returns the 1:1 chat with the contact.
  For groups, returns groups where the contact has sent messages.

  Returns an empty list if no chats found.

  """
  @spec get_contact_chats(keyword()) :: {:ok, [contact_chat()]} | {:error, term()}
  def get_contact_chats(opts \\ []) do
    contact_jid = Keyword.get(opts, :contact_jid)
    limit = Keyword.get(opts, :limit, @default_chat_limit)
    db_path = Config.database_path(path: Keyword.get(opts, :db_path))

    if contact_jid do
      do_get_contact_chats(contact_jid, limit, db_path)
    else
      {:error, :contact_jid_required}
    end
  end

  @doc """
  Gets the linked JID for a chat if one exists.

  For @lid format JIDs, returns the corresponding @s.whatsapp.net JID if known.
  For @s.whatsapp.net JIDs, returns the corresponding @lid JID if known.

  ## Options

    * `:jid` - The JID to find a link for (required)
    * `:db_path` - Override database path

  ## Returns

  `{:ok, linked_jid}` if a link exists, `{:ok, nil}` if no link found,
  or `{:error, reason}` on error.

  """
  @spec get_linked_jid(keyword()) :: {:ok, String.t() | nil} | {:error, term()}
  def get_linked_jid(opts \\ []) do
    jid = Keyword.get(opts, :jid)
    db_path = Config.database_path(path: Keyword.get(opts, :db_path))

    if jid do
      do_get_linked_jid(jid, db_path)
    else
      {:error, :jid_required}
    end
  end

  # Private functions

  @spec do_get_chat(String.t(), String.t()) :: {:ok, chat_with_count()} | {:error, term()}
  defp do_get_chat(jid, db_path) do
    # JOIN with contacts table to get enriched names for @lid contacts
    query = """
    SELECT
      c.jid,
      c.name,
      ct.name as contact_name,
      (SELECT m.content FROM messages m
       WHERE m.chat_jid = c.jid
       ORDER BY m.timestamp DESC LIMIT 1) as last_message,
      c.last_message_time as last_message_date,
      (SELECT COUNT(*) FROM messages m
       WHERE m.chat_jid = c.jid
       AND m.content IS NOT NULL) as message_count
    FROM chats c
    LEFT JOIN contacts ct ON c.jid = ct.jid
    WHERE c.jid = ?
    LIMIT 1
    """

    with {:ok, rows} <- Helpers.with_readonly_connection(db_path, query, [jid]) do
      case rows do
        [[jid, name, contact_name, last_message, last_message_date, message_count]] ->
          # Prefer contact_name (from contacts cache) over chat name
          display_name = contact_name || name || jid

          {:ok,
           %{
             jid: jid,
             name: display_name,
             last_message: Helpers.clean_message(last_message),
             last_message_date: last_message_date,
             message_count: message_count || 0
           }}

        [] ->
          {:error, :not_found}
      end
    end
  end

  @spec do_get_chat_by_phone(String.t(), String.t()) :: {:ok, chat_with_count()} | {:error, term()}
  defp do_get_chat_by_phone(phone, db_path) do
    # Build the JID from the phone number
    jid = "#{phone}@s.whatsapp.net"
    do_get_chat(jid, db_path)
  end

  @spec do_get_chat_by_name(String.t(), String.t()) :: {:ok, chat()} | {:error, term()}
  defp do_get_chat_by_name(name, db_path) do
    # Find chat by partial name match (searching both chat name and cached contact name)
    # Returns most recently active match
    escaped_name = Helpers.escape_like_pattern(name)
    search_pattern = "%#{escaped_name}%"

    # JOIN with contacts table to search cached names and get enriched display names
    query = """
    SELECT
      c.jid,
      c.name,
      ct.name as contact_name,
      (SELECT m.content FROM messages m
       WHERE m.chat_jid = c.jid
       ORDER BY m.timestamp DESC LIMIT 1) as last_message,
      c.last_message_time as last_message_date
    FROM chats c
    LEFT JOIN contacts ct ON c.jid = ct.jid
    WHERE c.name LIKE ? OR ct.name LIKE ?
    ORDER BY c.last_message_time DESC
    LIMIT 1
    """

    with {:ok, rows} <- Helpers.with_readonly_connection(db_path, query, [search_pattern, search_pattern]) do
      case rows do
        [[jid, chat_name, contact_name, last_message, last_message_date]] ->
          # Prefer contact_name (from contacts cache) over chat name
          display_name = contact_name || chat_name || jid

          {:ok,
           %{
             jid: jid,
             name: display_name,
             last_message: Helpers.clean_message(last_message),
             last_message_date: last_message_date
           }}

        [] ->
          {:error, :not_found}
      end
    end
  end

  @spec do_get_contact_chats(String.t(), integer(), String.t()) :: {:ok, [contact_chat()]} | {:error, term()}
  defp do_get_contact_chats(contact_jid, limit, db_path) do
    # Find all chats where:
    # 1. The chat_jid matches the contact (direct chat)
    # 2. The contact has sent messages in the chat (groups)
    # JOIN with contacts table to get enriched names for @lid contacts
    query = """
    SELECT DISTINCT
      c.jid,
      c.name,
      ct.name as contact_name,
      CASE WHEN c.jid LIKE '%@g.us' THEN 1 ELSE 0 END as is_group,
      c.last_message_time as last_message_date
    FROM chats c
    LEFT JOIN contacts ct ON c.jid = ct.jid
    LEFT JOIN messages m ON m.chat_jid = c.jid
    WHERE c.jid = ? OR m.sender = ?
    ORDER BY c.last_message_time DESC
    LIMIT ?
    """

    with {:ok, rows} <- Helpers.with_readonly_connection(db_path, query, [contact_jid, contact_jid, limit]) do
      chats =
        Enum.map(rows, fn [jid, name, contact_name, is_group, last_message_date] ->
          # Prefer contact_name (from contacts cache) over chat name
          display_name = contact_name || name || jid

          %{
            jid: jid,
            name: display_name,
            is_group: is_group == 1,
            last_message_date: last_message_date
          }
        end)

      {:ok, chats}
    end
  end

  @spec do_count_contact_chats(String.t(), String.t()) :: {:ok, non_neg_integer()} | {:error, term()}
  defp do_count_contact_chats(contact_jid, db_path) do
    query = """
    SELECT COUNT(DISTINCT c.jid)
    FROM chats c
    LEFT JOIN messages m ON m.chat_jid = c.jid
    WHERE c.jid = ? OR m.sender = ?
    """

    with {:ok, [[count]]} <- Helpers.with_readonly_connection(db_path, query, [contact_jid, contact_jid]) do
      {:ok, count}
    end
  end

  @spec do_get_linked_jid(String.t(), String.t()) :: {:ok, String.t() | nil} | {:error, term()}
  defp do_get_linked_jid(jid, db_path) do
    cond do
      String.ends_with?(jid, "@lid") -> get_phone_jid_for_lid(jid, db_path)
      String.ends_with?(jid, "@s.whatsapp.net") -> get_lid_for_phone_jid(jid, db_path)
      true -> {:ok, nil}
    end
  end

  # For @lid JIDs, look up the cached phone to construct @s.whatsapp.net JID
  @spec get_phone_jid_for_lid(String.t(), String.t()) :: {:ok, String.t() | nil} | {:error, term()}
  defp get_phone_jid_for_lid(jid, db_path) do
    query = "SELECT phone FROM contacts WHERE jid = ?"

    case Helpers.with_readonly_connection(db_path, query, [jid]) do
      {:ok, [[phone]]} when is_binary(phone) and phone != "" ->
        {:ok, "#{phone}@s.whatsapp.net"}

      {:ok, [[nil]]} ->
        {:ok, nil}

      {:ok, []} ->
        {:ok, nil}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # For @s.whatsapp.net JIDs, extract phone and look for @lid with same phone
  @spec get_lid_for_phone_jid(String.t(), String.t()) :: {:ok, String.t() | nil} | {:error, term()}
  defp get_lid_for_phone_jid(jid, db_path) do
    phone = String.replace(jid, "@s.whatsapp.net", "")
    query = "SELECT jid FROM contacts WHERE phone = ? AND jid LIKE '%@lid' LIMIT 1"

    case Helpers.with_readonly_connection(db_path, query, [phone]) do
      {:ok, [[lid_jid]]} -> {:ok, lid_jid}
      {:ok, []} -> {:ok, nil}
      {:error, reason} -> {:error, reason}
    end
  end
end
