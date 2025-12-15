defmodule WhatsappMcp.Database.Contacts do
  @moduledoc """
  Contact-related database queries.

  Provides functions for searching contacts and finding interactions.
  """

  alias WhatsappMcp.Config
  alias WhatsappMcp.Database.Helpers
  alias WhatsappMcp.Database.JidResolver

  # Public types

  @typedoc "A contact with phone info"
  @type contact :: %{
          jid: String.t(),
          name: String.t(),
          phone: String.t()
        }

  @typedoc "A message representing the last interaction with a contact"
  @type interaction :: %{
          id: String.t(),
          timestamp: String.t(),
          sender: String.t(),
          text: String.t() | nil,
          is_from_me: boolean(),
          media_type: String.t() | nil,
          chat_jid: String.t(),
          chat_name: String.t()
        }

  @typedoc "A cached contact from the contacts table with LID→phone mapping"
  @type cached_contact :: %{
          jid: String.t(),
          phone: String.t() | nil,
          name: String.t() | nil,
          updated_at: String.t() | nil
        }

  @doc """
  Counts contacts matching a search query.

  ## Options

    * `:query` - Search term to match against names or JIDs (required)
    * `:db_path` - Override database path

  ## Returns

  Total count of contacts matching the search query.

  """
  @spec count_contacts(keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  def count_contacts(opts \\ []) do
    search_query = Keyword.get(opts, :query)
    db_path = Config.database_path(path: Keyword.get(opts, :db_path))

    if search_query do
      do_count_contacts(search_query, db_path)
    else
      {:error, :query_required}
    end
  end

  @doc """
  Searches for contacts (non-group chats) by name or phone number.

  ## Options

    * `:query` - Search term to match against names or JIDs (required)
    * `:limit` - Maximum results (default: 50)
    * `:db_path` - Override database path

  ## Returns

  A list of maps with keys:
    * `:jid` - Contact JID (use this for send_message)
    * `:name` - Contact name
    * `:phone` - Phone number extracted from JID

  """
  @spec search_contacts(keyword()) :: {:ok, [contact()]} | {:error, term()}
  def search_contacts(opts \\ []) do
    search_query = Keyword.get(opts, :query)
    limit = Keyword.get(opts, :limit, 50)
    db_path = Config.database_path(path: Keyword.get(opts, :db_path))

    if search_query do
      do_search_contacts(search_query, limit, db_path)
    else
      {:error, :query_required}
    end
  end

  @doc """
  Gets the most recent message with a contact.

  ## Options

    * `:contact_jid` - Contact JID (required)
    * `:db_path` - Override database path

  ## Returns

  A map with keys:
    * `:id` - Message ID
    * `:timestamp` - ISO8601 timestamp
    * `:sender` - Message sender
    * `:text` - Message content
    * `:is_from_me` - Whether the message was sent by the user
    * `:media_type` - Type of media if present
    * `:chat_jid` - The chat JID (same as contact_jid for direct chats)
    * `:chat_name` - Name of the chat/contact

  Returns `{:error, :not_found}` if no messages exist with this contact.

  """
  @spec get_last_interaction(keyword()) :: {:ok, interaction()} | {:error, term()}
  def get_last_interaction(opts \\ []) do
    contact_jid = Keyword.get(opts, :contact_jid)
    db_path = Config.database_path(path: Keyword.get(opts, :db_path))

    if contact_jid do
      do_get_last_interaction(contact_jid, db_path)
    else
      {:error, :contact_jid_required}
    end
  end

  @doc """
  Gets a cached contact by JID from the contacts table.

  This is used to look up LID→phone mappings that were previously resolved.

  ## Options

    * `:jid` - The JID to look up (required)
    * `:db_path` - Override database path

  ## Returns

  A cached contact map or `{:error, :not_found}` if not cached.

  """
  @spec get_cached_contact(keyword()) :: {:ok, cached_contact()} | {:error, term()}
  def get_cached_contact(opts \\ []) do
    jid = Keyword.get(opts, :jid)
    db_path = Config.database_path(path: Keyword.get(opts, :db_path))

    if jid do
      do_get_cached_contact(jid, db_path)
    else
      {:error, :jid_required}
    end
  end

  @doc """
  Finds a cached contact by phone number from the contacts table.

  This is used to find LID contacts when searching by phone number.

  ## Options

    * `:phone` - The phone number to search for (required)
    * `:db_path` - Override database path

  ## Returns

  A cached contact map or `{:error, :not_found}` if not found.

  """
  @spec find_contact_by_phone(keyword()) :: {:ok, cached_contact()} | {:error, term()}
  def find_contact_by_phone(opts \\ []) do
    phone = Keyword.get(opts, :phone)
    db_path = Config.database_path(path: Keyword.get(opts, :db_path))

    if phone do
      do_find_contact_by_phone(phone, db_path)
    else
      {:error, :phone_required}
    end
  end

  @doc """
  Finds all JIDs linked to a contact (both @lid and @s.whatsapp.net versions).

  WhatsApp contacts may have messages under multiple JID formats:
  - `{phone}@s.whatsapp.net` - Traditional phone-based JID
  - `{numeric_id}@lid` - Linked ID format (privacy feature since 2025)

  This function finds all known JIDs for the same contact by:
  1. If input is @s.whatsapp.net: extract phone, look for @lid with same phone in cache
  2. If input is @lid: look up cached phone, find @s.whatsapp.net version
  3. Also check for existing chats matching the phone number

  ## Options

    * `:jid` - The JID to find links for (required)
    * `:db_path` - Override database path

  ## Returns

  A list of all known JIDs for this contact (always includes the input JID).
  Returns `{:error, :jid_required}` if no JID provided.

  """
  @spec find_linked_jids(keyword()) :: {:ok, [String.t()]} | {:error, term()}
  def find_linked_jids(opts \\ []) do
    jid = Keyword.get(opts, :jid)
    db_path = Config.database_path(path: Keyword.get(opts, :db_path))

    if jid do
      do_find_linked_jids(jid, db_path)
    else
      {:error, :jid_required}
    end
  end

  # Private functions

  @spec do_search_contacts(String.t(), integer(), String.t()) ::
          {:ok, [contact()]} | {:error, term()}
  defp do_search_contacts(search_query, limit, db_path) do
    # Search contacts (non-group chats) by name or phone number in JID
    # Groups have JIDs ending in @g.us, individual chats end in @s.whatsapp.net
    # Also search the contacts cache for LID→phone mappings
    query = """
    SELECT
      c.jid,
      c.name,
      ct.phone as cached_phone,
      ct.name as cached_name
    FROM chats c
    LEFT JOIN contacts ct ON c.jid = ct.jid
    WHERE c.jid NOT LIKE '%@g.us'
      AND (c.name LIKE ? OR c.jid LIKE ? OR ct.phone LIKE ? OR ct.name LIKE ?)
    ORDER BY c.last_message_time DESC
    LIMIT ?
    """

    escaped_query = Helpers.escape_like_pattern(search_query)
    search_pattern = "%#{escaped_query}%"
    params = [search_pattern, search_pattern, search_pattern, search_pattern, limit]

    with {:ok, rows} <- Helpers.with_readonly_connection(db_path, query, params) do
      contacts =
        Enum.map(rows, fn [jid, name, cached_phone, cached_name] ->
          # Prefer cached phone/name over JID-extracted values
          phone = cached_phone || Helpers.extract_phone(jid)
          display_name = cached_name || name || Helpers.extract_phone(jid)

          %{
            jid: jid,
            name: display_name,
            phone: phone
          }
        end)

      {:ok, contacts}
    end
  end

  @spec do_get_last_interaction(String.t(), String.t()) :: {:ok, interaction()} | {:error, term()}
  defp do_get_last_interaction(contact_jid, db_path) do
    # Get the most recent message in the direct chat with this contact
    # OR the most recent message sent by this contact in any chat (including groups)
    query = """
    SELECT
      m.id,
      m.timestamp,
      COALESCE(m.sender, CASE WHEN m.is_from_me = 1 THEN 'Me' ELSE 'Unknown' END) as sender,
      m.content as text,
      m.is_from_me,
      m.media_type,
      m.chat_jid,
      COALESCE(c.name, m.chat_jid) as chat_name
    FROM messages m
    LEFT JOIN chats c ON m.chat_jid = c.jid
    WHERE m.chat_jid = ? OR m.sender = ?
    ORDER BY m.timestamp DESC
    LIMIT 1
    """

    with {:ok, rows} <- Helpers.with_readonly_connection(db_path, query, [contact_jid, contact_jid]) do
      case rows do
        [[id, timestamp, sender, text, is_from_me, media_type, chat_jid, chat_name]] ->
          {:ok,
           %{
             id: id,
             timestamp: timestamp,
             sender: sender,
             text: Helpers.clean_message(text),
             is_from_me: is_from_me == 1,
             media_type: media_type,
             chat_jid: chat_jid,
             chat_name: chat_name
           }}

        [] ->
          {:error, :not_found}
      end
    end
  end

  @spec do_count_contacts(String.t(), String.t()) :: {:ok, non_neg_integer()} | {:error, term()}
  defp do_count_contacts(search_query, db_path) do
    # Match the same query structure as do_search_contacts
    query = """
    SELECT COUNT(*)
    FROM chats c
    LEFT JOIN contacts ct ON c.jid = ct.jid
    WHERE c.jid NOT LIKE '%@g.us'
      AND (c.name LIKE ? OR c.jid LIKE ? OR ct.phone LIKE ? OR ct.name LIKE ?)
    """

    escaped_query = Helpers.escape_like_pattern(search_query)
    search_pattern = "%#{escaped_query}%"
    params = [search_pattern, search_pattern, search_pattern, search_pattern]

    with {:ok, [[count]]} <- Helpers.with_readonly_connection(db_path, query, params) do
      {:ok, count}
    end
  end

  @spec do_get_cached_contact(String.t(), String.t()) :: {:ok, cached_contact()} | {:error, term()}
  defp do_get_cached_contact(jid, db_path) do
    query = """
    SELECT jid, phone, name, updated_at
    FROM contacts
    WHERE jid = ?
    """

    with {:ok, rows} <- Helpers.with_readonly_connection(db_path, query, [jid]) do
      case rows do
        [[jid, phone, name, updated_at]] ->
          {:ok, %{jid: jid, phone: phone, name: name, updated_at: updated_at}}

        [] ->
          {:error, :not_found}
      end
    end
  end

  @spec do_find_contact_by_phone(String.t(), String.t()) :: {:ok, cached_contact()} | {:error, term()}
  defp do_find_contact_by_phone(phone, db_path) do
    # Search for contacts where the phone column matches
    # Use LIKE to handle partial matches (e.g., with/without country code)
    query = """
    SELECT jid, phone, name, updated_at
    FROM contacts
    WHERE phone LIKE ?
    ORDER BY updated_at DESC
    LIMIT 1
    """

    escaped_phone = Helpers.escape_like_pattern(phone)
    search_pattern = "%#{escaped_phone}%"

    with {:ok, rows} <- Helpers.with_readonly_connection(db_path, query, [search_pattern]) do
      case rows do
        [[jid, phone, name, updated_at]] ->
          {:ok, %{jid: jid, phone: phone, name: name, updated_at: updated_at}}

        [] ->
          {:error, :not_found}
      end
    end
  end

  @spec do_find_linked_jids(String.t(), String.t()) :: {:ok, [String.t()]} | {:error, term()}
  defp do_find_linked_jids(jid, db_path) do
    JidResolver.find_all_linked_jids(jid, db_path)
  end
end
