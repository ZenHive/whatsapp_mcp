defmodule WhatsappMcp.Database.Messages do
  @moduledoc """
  Message-related database queries.

  Provides functions for retrieving and searching messages.
  """

  alias WhatsappMcp.Config
  alias WhatsappMcp.Database.Helpers

  # Public types

  @typedoc "A message with metadata"
  @type message :: %{
          id: String.t(),
          timestamp: String.t(),
          sender: String.t(),
          text: String.t() | nil,
          is_from_me: boolean(),
          media_type: String.t() | nil
        }

  @typedoc "Context surrounding a target message"
  @type message_context :: %{
          target: message(),
          before: [message()],
          after: [message()],
          chat_jid: String.t()
        }

  @default_message_limit 100
  @default_context_count 5

  @doc """
  Counts total messages in a chat.

  ## Options

    * `:chat_id` - Chat JID (required if no chat_name)
    * `:chat_name` - Partial name to match (alternative to chat_id)
    * `:before` - Only count messages before this ISO8601 timestamp
    * `:after` - Only count messages after this ISO8601 timestamp
    * `:db_path` - Override database path

  ## Returns

  Total count of messages that would be returned by `get_messages/1`.

  """
  @spec count_messages(keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  def count_messages(opts \\ []) do
    chat_id = Keyword.get(opts, :chat_id)
    chat_name = Keyword.get(opts, :chat_name)
    before = Keyword.get(opts, :before)
    after_ts = Keyword.get(opts, :after)
    db_path = Config.database_path(path: Keyword.get(opts, :db_path))

    cond do
      chat_id -> count_messages_by_jid(chat_id, before, after_ts, db_path)
      chat_name -> count_messages_by_name(chat_name, before, after_ts, db_path)
      true -> {:error, :chat_id_or_name_required}
    end
  end

  @doc """
  Counts search results across all chats or within a specific chat.

  ## Options

    * `:query` - Search term (required, unless has_media is true)
    * `:chat_id` - Limit search to specific chat JID
    * `:has_media` - If true, only count messages with attachments
    * `:db_path` - Override database path

  ## Returns

  Total count of messages matching the search query.

  """
  @spec count_search_results(keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  def count_search_results(opts \\ []) do
    search_query = Keyword.get(opts, :query)
    chat_id = Keyword.get(opts, :chat_id)
    has_media = Keyword.get(opts, :has_media, false)
    db_path = Config.database_path(path: Keyword.get(opts, :db_path))

    cond do
      search_query -> do_count_search_results(search_query, chat_id, has_media, db_path)
      has_media -> do_count_search_results(nil, chat_id, has_media, db_path)
      true -> {:error, :query_required}
    end
  end

  @doc """
  Gets messages from a specific chat.

  ## Options

    * `:chat_id` - Chat JID (required if no chat_name)
    * `:chat_name` - Partial name to match (alternative to chat_id)
    * `:limit` - Maximum number of messages (default: 100)
    * `:offset` - Number of messages to skip for pagination (default: 0)
    * `:before` - Only messages before this ISO8601 timestamp
    * `:after` - Only messages after this ISO8601 timestamp
    * `:db_path` - Override database path

  ## Timestamps

  **All timestamps are stored in UTC.**

  Timestamps should be in ISO8601 format. If no timezone is provided,
  UTC (+00:00) is assumed. Examples:
  - "2025-12-11T10:00:00" (assumes UTC)
  - "2025-12-11T10:00:00Z" (explicit UTC)
  - "2025-12-11T10:00:00+00:00" (explicit UTC)

  For users in other timezones, convert local time to UTC before filtering.

  ## Pagination

  Use `offset` and `limit` together for pagination:
  - Page 0: `offset: 0, limit: 100`
  - Page 1: `offset: 100, limit: 100`
  - Page N: `offset: N * limit, limit: 100`

  The `before` and `after` timestamps can be used to narrow date ranges.
  Returns an empty list when past the last page.

  """
  @spec get_messages(keyword()) :: {:ok, [map()]} | {:error, term()}
  def get_messages(opts \\ []) do
    chat_id = Keyword.get(opts, :chat_id)
    chat_name = Keyword.get(opts, :chat_name)
    limit = Keyword.get(opts, :limit, @default_message_limit)
    offset = Keyword.get(opts, :offset, 0)
    before = Keyword.get(opts, :before)
    after_ts = Keyword.get(opts, :after)
    db_path = Config.database_path(path: Keyword.get(opts, :db_path))

    cond do
      chat_id -> get_messages_by_jid(chat_id, limit, offset, before, after_ts, db_path)
      chat_name -> get_messages_by_name(chat_name, limit, offset, before, after_ts, db_path)
      true -> {:error, :chat_id_or_name_required}
    end
  end

  @doc """
  Searches messages across all chats or within a specific chat.

  ## Options

    * `:query` - Search term (required, unless has_media is true)
    * `:chat_id` - Limit search to specific chat JID
    * `:has_media` - If true, only return messages with attachments
    * `:limit` - Maximum results (default: 50)
    * `:offset` - Number of results to skip for pagination (default: 0)
    * `:db_path` - Override database path

  """
  @spec search_messages(keyword()) :: {:ok, [map()]} | {:error, term()}
  def search_messages(opts \\ []) do
    search_query = Keyword.get(opts, :query)
    chat_id = Keyword.get(opts, :chat_id)
    has_media = Keyword.get(opts, :has_media, false)
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)
    db_path = Config.database_path(path: Keyword.get(opts, :db_path))

    cond do
      search_query -> do_search(search_query, chat_id, has_media, limit, offset, db_path)
      has_media -> do_search(nil, chat_id, has_media, limit, offset, db_path)
      true -> {:error, :query_required}
    end
  end

  @doc """
  Gets messages surrounding a specific message for context.

  ## Options

    * `:message_id` - The target message ID (required)
    * `:before` - Number of messages before the target (default: 5)
    * `:after` - Number of messages after the target (default: 5)
    * `:db_path` - Override database path

  ## Returns

  A map with keys:
    * `:target` - The target message
    * `:before` - List of messages before the target
    * `:after` - List of messages after the target
    * `:chat_jid` - The chat JID containing the message

  Returns `{:error, :not_found}` if the message doesn't exist.

  """
  @spec get_message_context(keyword()) :: {:ok, message_context()} | {:error, term()}
  def get_message_context(opts \\ []) do
    message_id = Keyword.get(opts, :message_id)
    before_count = Keyword.get(opts, :before, @default_context_count)
    after_count = Keyword.get(opts, :after, @default_context_count)
    db_path = Config.database_path(path: Keyword.get(opts, :db_path))

    if message_id do
      do_get_message_context(message_id, before_count, after_count, db_path)
    else
      {:error, :message_id_required}
    end
  end

  # Private functions

  @spec get_messages_by_jid(String.t(), integer(), integer(), String.t() | nil, String.t() | nil, String.t()) ::
          {:ok, [map()]} | {:error, term()}
  defp get_messages_by_jid(chat_jid, limit, offset, before, after_ts, db_path) do
    # Find all linked JIDs (e.g., both @lid and @s.whatsapp.net for same contact)
    # This provides a unified view of messages regardless of which JID format was used
    alias WhatsappMcp.Database.Contacts

    linked_jids =
      case Contacts.find_linked_jids(jid: chat_jid, db_path: db_path) do
        {:ok, [_ | _] = jids} -> jids
        _ -> [chat_jid]
      end

    get_messages_by_jids(linked_jids, chat_jid, limit, offset, before, after_ts, db_path)
  end

  @spec get_messages_by_jids(
          [String.t()],
          String.t(),
          integer(),
          integer(),
          String.t() | nil,
          String.t() | nil,
          String.t()
        ) ::
          {:ok, [map()]} | {:error, term()}
  defp get_messages_by_jids(jids, primary_jid, limit, offset, before, after_ts, db_path) do
    {time_filter, time_params} = Helpers.build_time_filter(before, after_ts)

    # Build placeholders for IN clause
    placeholders = Enum.map_join(jids, ", ", fn _ -> "?" end)

    # Note: time_filter is interpolated into SQL but is SAFE because:
    # 1. It comes from Helpers.build_time_filter/1 which returns hardcoded strings
    # 2. The actual user-provided value (before) is parameterized via `?` placeholder
    query = """
    SELECT * FROM (
      SELECT
        m.timestamp,
        COALESCE(m.sender, CASE WHEN m.is_from_me = 1 THEN 'Me' ELSE 'Unknown' END) as sender,
        m.content as text,
        m.is_from_me,
        m.media_type,
        m.id,
        m.chat_jid as source_jid
      FROM messages m
      WHERE m.chat_jid IN (#{placeholders})
        AND m.content IS NOT NULL
        #{time_filter}
      ORDER BY m.timestamp DESC
      LIMIT ?
      OFFSET ?
    ) ORDER BY timestamp ASC
    """

    execute_message_query_with_source(query, jids ++ time_params ++ [limit, offset], primary_jid, db_path)
  end

  @spec get_messages_by_name(String.t(), integer(), integer(), String.t() | nil, String.t() | nil, String.t()) ::
          {:ok, [map()]} | {:error, term()}
  defp get_messages_by_name(chat_name, limit, offset, before, after_ts, db_path) do
    find_query = """
    SELECT jid FROM chats
    WHERE name LIKE ?
    ORDER BY last_message_time DESC
    LIMIT 1
    """

    escaped_name = Helpers.escape_like_pattern(chat_name)

    with {:ok, rows} <- Helpers.with_readonly_connection(db_path, find_query, ["%#{escaped_name}%"]) do
      case rows do
        [[chat_jid]] -> get_messages_by_jid(chat_jid, limit, offset, before, after_ts, db_path)
        [] -> {:error, {:chat_not_found, chat_name}}
      end
    end
  end

  @spec do_search(String.t() | nil, String.t() | nil, boolean(), integer(), integer(), String.t()) ::
          {:ok, [map()]} | {:error, term()}
  defp do_search(search_query, chat_id, has_media, limit, offset, db_path) do
    {chat_filter, chat_params} =
      if chat_id do
        {"AND m.chat_jid = ?", [chat_id]}
      else
        {"", []}
      end

    {media_filter, _} =
      if has_media do
        {"AND m.media_type IS NOT NULL AND m.media_type != ''", []}
      else
        {"", []}
      end

    {content_filter, content_params} =
      if search_query do
        escaped_query = Helpers.escape_like_pattern(search_query)
        {"AND m.content LIKE ?", ["%#{escaped_query}%"]}
      else
        {"", []}
      end

    query = """
    SELECT
      m.id,
      m.timestamp,
      COALESCE(c.name, m.chat_jid) as chat_name,
      COALESCE(m.sender, CASE WHEN m.is_from_me = 1 THEN 'Me' ELSE 'Unknown' END) as sender,
      m.content as text,
      m.chat_jid as chat_id,
      m.media_type
    FROM messages m
    LEFT JOIN chats c ON m.chat_jid = c.jid
    WHERE 1=1
      #{content_filter}
      #{chat_filter}
      #{media_filter}
    ORDER BY m.timestamp DESC
    LIMIT ?
    OFFSET ?
    """

    params = content_params ++ chat_params ++ [limit, offset]

    with {:ok, rows} <- Helpers.with_readonly_connection(db_path, query, params) do
      results =
        Enum.map(rows, fn [id, timestamp, chat_name, sender, text, chat_id, media_type] ->
          %{
            id: id,
            timestamp: timestamp,
            chat_name: chat_name,
            chat_id: chat_id,
            sender: sender,
            text: Helpers.clean_message(text),
            media_type: media_type
          }
        end)

      {:ok, results}
    end
  end

  @spec do_get_message_context(String.t(), integer(), integer(), String.t()) ::
          {:ok, map()} | {:error, term()}
  defp do_get_message_context(message_id, before_count, after_count, db_path) do
    # First, get the target message and its chat_jid/timestamp
    # Join with chats table to resolve sender JID to contact name
    target_query = """
    SELECT
      m.id,
      m.chat_jid,
      m.timestamp,
      COALESCE(sender_chat.name, m.sender, CASE WHEN m.is_from_me = 1 THEN 'Me' ELSE 'Unknown' END) as sender,
      m.content as text,
      m.is_from_me,
      m.media_type
    FROM messages m
    LEFT JOIN chats sender_chat ON m.sender = sender_chat.jid
    WHERE m.id = ?
    LIMIT 1
    """

    with {:ok, target_rows} <- Helpers.with_readonly_connection(db_path, target_query, [message_id]) do
      case target_rows do
        [] ->
          {:error, :not_found}

        [[id, chat_jid, timestamp, sender, text, is_from_me, media_type]] ->
          target_msg = build_message(id, timestamp, sender, text, is_from_me, media_type)
          fetch_context_window(target_msg, chat_jid, timestamp, before_count, after_count, db_path)
      end
    end
  end

  # Fetches the before/after message window around a target message and
  # assembles the context result. Extracted from do_get_message_context/4 to
  # keep the surrounding with/case nesting within the depth limit.
  @spec fetch_context_window(map(), String.t(), integer(), integer(), integer(), String.t()) ::
          {:ok, map()} | {:error, term()}
  defp fetch_context_window(target_msg, chat_jid, timestamp, before_count, after_count, db_path) do
    # Get messages before (older timestamps in the same chat)
    # Join with chats to resolve sender names
    before_query = """
    SELECT
      m.id,
      m.timestamp as timestamp_str,
      COALESCE(sender_chat.name, m.sender, CASE WHEN m.is_from_me = 1 THEN 'Me' ELSE 'Unknown' END) as sender,
      m.content as text,
      m.is_from_me,
      m.media_type
    FROM messages m
    LEFT JOIN chats sender_chat ON m.sender = sender_chat.jid
    WHERE m.chat_jid = ?
      AND m.timestamp < ?
      AND m.content IS NOT NULL
    ORDER BY m.timestamp DESC
    LIMIT ?
    """

    # Get messages after (newer timestamps in the same chat)
    after_query = """
    SELECT
      m.id,
      m.timestamp as timestamp_str,
      COALESCE(sender_chat.name, m.sender, CASE WHEN m.is_from_me = 1 THEN 'Me' ELSE 'Unknown' END) as sender,
      m.content as text,
      m.is_from_me,
      m.media_type
    FROM messages m
    LEFT JOIN chats sender_chat ON m.sender = sender_chat.jid
    WHERE m.chat_jid = ?
      AND m.timestamp > ?
      AND m.content IS NOT NULL
    ORDER BY m.timestamp ASC
    LIMIT ?
    """

    with {:ok, before_rows} <-
           Helpers.with_readonly_connection(db_path, before_query, [chat_jid, timestamp, before_count]),
         {:ok, after_rows} <-
           Helpers.with_readonly_connection(db_path, after_query, [chat_jid, timestamp, after_count]) do
      before_msgs =
        before_rows
        |> Enum.map(&row_to_message/1)
        |> Enum.reverse()

      after_msgs = Enum.map(after_rows, &row_to_message/1)

      {:ok, %{target: target_msg, before: before_msgs, after: after_msgs, chat_jid: chat_jid}}
    end
  end

  @spec row_to_message([term()]) :: map()
  defp row_to_message([id, timestamp_str, sender, text, is_from_me, media_type]) do
    build_message(id, timestamp_str, sender, text, is_from_me, media_type)
  end

  @spec build_message(String.t(), String.t(), String.t(), String.t() | nil, integer(), String.t() | nil) ::
          map()
  defp build_message(id, timestamp, sender, text, is_from_me, media_type) do
    %{
      id: id,
      timestamp: timestamp,
      sender: sender,
      text: Helpers.clean_message(text),
      is_from_me: is_from_me == 1,
      media_type: media_type
    }
  end

  # Execute message query with source_jid for merged message views
  # The primary_jid is the main chat JID - source_jid is only included if different
  @spec execute_message_query_with_source(String.t(), [term()], String.t(), String.t()) ::
          {:ok, [map()]} | {:error, term()}
  defp execute_message_query_with_source(query, params, primary_jid, db_path) do
    with {:ok, rows} <- Helpers.with_readonly_connection(db_path, query, params) do
      {:ok, Enum.map(rows, &build_source_message(&1, primary_jid))}
    end
  end

  # Builds a merged-view message map, including :source_jid only when it differs
  # from the primary chat JID. Extracted from execute_message_query_with_source/4
  # to keep the with/map/if nesting within the depth limit.
  @spec build_source_message([term()], String.t()) :: map()
  defp build_source_message([timestamp, sender, text, is_from_me, media_type, id, source_jid], primary_jid) do
    msg = %{
      id: id,
      timestamp: timestamp,
      sender: sender,
      text: Helpers.clean_message(text),
      is_from_me: is_from_me == 1,
      media_type: media_type
    }

    # Only include source_jid if it differs from the primary chat JID
    if source_jid == primary_jid, do: msg, else: Map.put(msg, :source_jid, source_jid)
  end

  @spec count_messages_by_jid(String.t(), String.t() | nil, String.t() | nil, String.t()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  defp count_messages_by_jid(chat_jid, before, after_ts, db_path) do
    # Find all linked JIDs to count messages across the unified view
    alias WhatsappMcp.Database.Contacts

    jids =
      case Contacts.find_linked_jids(jid: chat_jid, db_path: db_path) do
        {:ok, [_ | _] = linked} -> linked
        _ -> [chat_jid]
      end

    count_messages_by_jids(jids, before, after_ts, db_path)
  end

  @spec count_messages_by_jids([String.t()], String.t() | nil, String.t() | nil, String.t()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  defp count_messages_by_jids(jids, before, after_ts, db_path) do
    {time_filter, time_params} = Helpers.build_time_filter(before, after_ts)

    placeholders = Enum.map_join(jids, ", ", fn _ -> "?" end)

    query = """
    SELECT COUNT(*)
    FROM messages m
    WHERE m.chat_jid IN (#{placeholders})
      AND m.content IS NOT NULL
      #{time_filter}
    """

    with {:ok, [[count]]} <- Helpers.with_readonly_connection(db_path, query, jids ++ time_params) do
      {:ok, count}
    end
  end

  @spec count_messages_by_name(String.t(), String.t() | nil, String.t() | nil, String.t()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  defp count_messages_by_name(chat_name, before, after_ts, db_path) do
    find_query = """
    SELECT jid FROM chats
    WHERE name LIKE ?
    ORDER BY last_message_time DESC
    LIMIT 1
    """

    escaped_name = Helpers.escape_like_pattern(chat_name)

    with {:ok, rows} <- Helpers.with_readonly_connection(db_path, find_query, ["%#{escaped_name}%"]) do
      case rows do
        [[chat_jid]] -> count_messages_by_jid(chat_jid, before, after_ts, db_path)
        [] -> {:error, {:chat_not_found, chat_name}}
      end
    end
  end

  @spec do_count_search_results(String.t() | nil, String.t() | nil, boolean(), String.t()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  defp do_count_search_results(search_query, chat_id, has_media, db_path) do
    {chat_filter, chat_params} =
      if chat_id do
        {"AND m.chat_jid = ?", [chat_id]}
      else
        {"", []}
      end

    {media_filter, _} =
      if has_media do
        {"AND m.media_type IS NOT NULL AND m.media_type != ''", []}
      else
        {"", []}
      end

    {content_filter, content_params} =
      if search_query do
        escaped_query = Helpers.escape_like_pattern(search_query)
        {"AND m.content LIKE ?", ["%#{escaped_query}%"]}
      else
        {"", []}
      end

    query = """
    SELECT COUNT(*)
    FROM messages m
    WHERE 1=1
      #{content_filter}
      #{chat_filter}
      #{media_filter}
    """

    params = content_params ++ chat_params

    with {:ok, [[count]]} <- Helpers.with_readonly_connection(db_path, query, params) do
      {:ok, count}
    end
  end
end
