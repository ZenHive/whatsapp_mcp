defmodule WhatsappMcp.Tools.Formatters do
  @moduledoc """
  Output formatters for MCP tool results.

  Formats database query results and bridge responses into
  human-readable text for display to users.
  """

  alias WhatsappMcp.Database

  # Shared helper for common bridge error formatting.
  # Handles :bridge_not_running, :timeout, string errors, and fallback inspection.
  @spec format_bridge_error({:error, term()}) :: {:error, String.t()}
  defp format_bridge_error({:error, :bridge_not_running}) do
    {:error, "WhatsApp bridge is not running. Start the bridge with: cd bridge && go run ."}
  end

  defp format_bridge_error({:error, :timeout}) do
    {:error, "Request to WhatsApp bridge timed out"}
  end

  defp format_bridge_error({:error, reason}) when is_binary(reason), do: {:error, reason}
  defp format_bridge_error({:error, reason}), do: {:error, inspect(reason)}

  # Bridge result formatters

  @doc """
  Formats a bridge API result into a user-friendly response.
  """
  @spec format_bridge_result({:ok, String.t()} | {:error, term()}) :: {:ok, String.t()} | {:error, String.t()}
  def format_bridge_result({:ok, response}), do: {:ok, response}

  def format_bridge_result({:error, :file_not_found}) do
    {:error, "File not found. Please provide a valid absolute path to an existing file."}
  end

  def format_bridge_result({:error, :invalid_path}) do
    {:error, "Invalid file path. Path must be absolute and cannot contain '..' traversal patterns."}
  end

  def format_bridge_result(error), do: format_bridge_error(error)

  @doc """
  Formats a media download result.
  """
  @spec format_download_result({:ok, map()} | {:error, term()}) :: {:ok, String.t()} | {:error, String.t()}
  def format_download_result({:ok, %{path: path, filename: filename, media_type: media_type}}) do
    {:ok, "Downloaded #{media_type}: #{filename}\nSaved to: #{path}"}
  end

  def format_download_result(error), do: format_bridge_error(error)

  @doc """
  Formats bridge health check status.
  """
  @spec format_bridge_status({:ok, map()} | {:error, term()}) :: {:ok, String.t()} | {:error, String.t()}
  def format_bridge_status({:ok, %{"connected" => true, "phone" => phone, "name" => name}}) do
    {:ok, "Bridge Status: Connected\nPhone: #{phone}\nAccount: #{name}"}
  end

  def format_bridge_status({:ok, %{"connected" => true, "phone" => phone}}) do
    {:ok, "Bridge Status: Connected\nPhone: #{phone}"}
  end

  def format_bridge_status({:ok, %{"connected" => true}}) do
    {:ok, "Bridge Status: Connected (no account info available)"}
  end

  def format_bridge_status({:ok, %{"connected" => false}}) do
    {:ok,
     """
     Bridge Status: Running but not connected to WhatsApp

     The bridge is running but needs to be linked to your WhatsApp account.
     Check the terminal where the bridge is running - a QR code should be displayed.

     To link your account:
     1. Open WhatsApp on your phone
     2. Go to Settings > Linked Devices
     3. Tap "Link a Device"
     4. Scan the QR code shown in the bridge terminal

     Use get_help for more guidance on phone formats and workflows.
     """}
  end

  def format_bridge_status({:error, :bridge_not_running}) do
    bridge_path = WhatsappMcp.Config.bridge_source_path()

    {:ok,
     """
     Bridge Status: Not Running

     To start the WhatsApp bridge:
     1. Open a terminal
     2. Run: cd #{bridge_path} && go run .
     3. Scan the QR code shown in the terminal with WhatsApp mobile app
     4. Keep the terminal open while using WhatsApp MCP

     The bridge must stay running in the terminal for WhatsApp access to work.

     First time setup? You'll need Go installed:
     - macOS: brew install go
     - Linux: apt install golang (or dnf install golang)
     - Windows: Download from https://go.dev/dl/

     Use get_help for more guidance on phone formats and workflows.
     """}
  end

  # Chat/Message formatters

  @doc """
  Formats a list of chats for display.

  ## Parameters

    * `chats` - List of chat maps
    * `pagination` - Optional pagination info map with keys: `:offset`, `:limit`, `:total`, `:count`

  """
  @spec format_chats([map()], map() | nil) :: String.t()
  def format_chats(chats, pagination \\ nil)
  def format_chats([], _pagination), do: "No chats found."

  def format_chats(chats, pagination) do
    header = format_list_header("chats", chats, pagination)

    rows =
      Enum.map_join(chats, "\n", fn chat ->
        last_msg =
          if chat.last_message do
            truncate(chat.last_message, 50)
          else
            "(no message)"
          end

        date = format_timestamp(chat.last_message_date)
        linked = format_linked_jid(Map.get(chat, :linked_jid))
        "JID: #{chat.jid} | #{chat.name}#{linked}\n  Last: #{last_msg}\n  Date: #{date}"
      end)

    footer = "\n\n(Timestamps are in UTC. Convert to your local timezone as needed.)"

    hint = "\n\nTip: Use get_messages(chat_id: \"<JID>\") to read messages from a chat."

    header <> rows <> footer <> hint
  end

  @doc """
  Formats messages with a summary header.

  ## Parameters

    * `messages` - List of message maps
    * `chat_info` - Optional chat metadata
    * `pagination` - Optional pagination info map with keys: `:offset`, `:limit`, `:total`, `:count`

  """
  @spec format_messages_with_summary([map()], map() | nil, map() | nil) :: String.t()
  def format_messages_with_summary(messages, chat_info, pagination \\ nil)
  def format_messages_with_summary([], _chat_info, _pagination), do: "No messages found."

  def format_messages_with_summary(messages, chat_info, pagination) do
    summary = build_chat_summary(messages, chat_info, pagination)

    rows =
      Enum.map_join(messages, "\n\n", fn msg ->
        from_me = if msg.is_from_me, do: " (you)", else: ""
        media = format_media_indicator(msg.media_type)
        msg_id = if msg.id, do: " [ID:#{msg.id}]", else: ""
        source = format_source_jid(Map.get(msg, :source_jid), chat_info)
        content = format_message_content(msg.text, msg.media_type)

        "[#{msg.timestamp}]#{msg_id}#{source} #{msg.sender}#{from_me}#{media}:\n#{content}"
      end)

    hint = build_messages_hint(chat_info)

    summary <> rows <> hint
  end

  @doc """
  Formats search results.

  ## Parameters

    * `results` - List of search result maps
    * `pagination` - Optional pagination info map with keys: `:limit`, `:total`, `:count`

  """
  @spec format_search_results([map()], map() | nil) :: String.t()
  def format_search_results(results, pagination \\ nil)
  def format_search_results([], _pagination), do: "No messages found matching your search."

  def format_search_results(results, pagination) do
    header = format_list_header("matching messages", results, pagination)

    rows =
      Enum.map_join(results, "\n\n", fn result ->
        media = format_media_indicator(result.media_type)

        "[#{result.timestamp}] [MsgID:#{result.id}] Chat: #{result.chat_name} (JID: #{result.chat_id})#{media}\nFrom: #{result.sender}\n#{result.text}"
      end)

    hint = "\n\nTip: Use get_message_context(message_id: \"<MsgID>\") to see surrounding conversation."

    header <> rows <> hint
  end

  @doc """
  Formats contact search results.

  ## Parameters

    * `contacts` - List of contact maps
    * `pagination` - Optional pagination info map with keys: `:limit`, `:total`, `:count`

  """
  @spec format_contacts([map()], map() | nil) :: String.t()
  def format_contacts(contacts, pagination \\ nil)
  def format_contacts([], _pagination), do: "No contacts found matching your search."

  def format_contacts(contacts, pagination) do
    header = format_list_header("contacts", contacts, pagination)

    rows =
      Enum.map_join(contacts, "\n", fn contact ->
        "#{contact.name} | Phone: #{contact.phone} | JID: #{contact.jid}"
      end)

    hint = ~s{\n\nTip: Use send_message(recipient: "<JID>", message: "...") to message a contact.}

    header <> rows <> hint
  end

  @doc """
  Formats a single chat's metadata.
  """
  @spec format_chat(map()) :: String.t()
  def format_chat(chat) do
    last_msg =
      if chat.last_message do
        truncate(chat.last_message, 100)
      else
        "(no message)"
      end

    date = format_timestamp(chat.last_message_date)
    msg_count = Map.get(chat, :message_count, 0)

    String.trim("""
    JID: #{chat.jid}
    Name: #{chat.name}
    Messages: #{msg_count} total
    Last message: #{last_msg}
    Date: #{date}

    (Timestamps are in UTC. Convert to your local timezone as needed.)

    Tip: Use get_messages(chat_id: "#{chat.jid}") to read messages from this chat.
    """)
  end

  @doc """
  Formats message context (before/target/after).
  """
  @spec format_message_context(map()) :: String.t()
  def format_message_context(%{target: target, before: before, after: after_msgs, chat_jid: chat_jid}) do
    total = length(before) + 1 + length(after_msgs)

    header = "Context for message in chat #{chat_jid} (#{total} messages):\n\n"

    before_section =
      if before == [] do
        ""
      else
        format_context_messages(before, "--- Before ---\n\n")
      end

    target_section = format_context_messages([target], "--- Target Message ---\n\n")

    after_section =
      if after_msgs == [] do
        ""
      else
        format_context_messages(after_msgs, "--- After ---\n\n")
      end

    header <> before_section <> target_section <> after_section
  end

  @doc """
  Formats the last interaction with a contact.

  The header shows the contact name we searched for (not the chat name where
  the message was found, which could be a group).
  """
  @spec format_last_interaction(map(), String.t(), keyword()) :: String.t()
  def format_last_interaction(message, contact_jid, opts \\ []) do
    from_me = if message.is_from_me, do: " (you)", else: ""
    media = if message.media_type, do: " [#{message.media_type}]", else: ""

    # Look up contact name from their JID
    contact_name = get_contact_name(contact_jid, opts)

    String.trim("""
    Last interaction with #{contact_name}:

    [#{message.timestamp}] #{message.sender}#{from_me}#{media}:
    #{message.text || "(no text)"}

    Chat: #{message.chat_jid}
    Message ID: #{message.id}

    Tip: Use get_messages(chat_id: "#{message.chat_jid}") to see full conversation history.
    """)
  end

  # Looks up contact name from JID, falls back to JID if not found or on error
  defp get_contact_name(contact_jid, opts) do
    db_opts = maybe_add([], :db_path, opts[:db_path])

    case Database.get_chat(Keyword.put(db_opts, :jid, contact_jid)) do
      {:ok, chat} -> chat.name
      {:error, :not_found} -> contact_jid
      {:error, _reason} -> contact_jid
    end
  end

  @doc """
  Formats a list of chats involving a contact.

  ## Parameters

    * `chats` - List of chat maps
    * `pagination` - Optional pagination info map with keys: `:limit`, `:total`, `:count`

  """
  @spec format_contact_chats([map()], map() | nil) :: String.t()
  def format_contact_chats(chats, pagination \\ nil)
  def format_contact_chats([], _pagination), do: "No chats found for this contact."

  def format_contact_chats(chats, pagination) do
    header = format_list_header("chats involving this contact", chats, pagination)

    rows =
      Enum.map_join(chats, "\n", fn chat ->
        type = if chat.is_group, do: "[Group]", else: "[Direct]"
        date = format_timestamp(chat.last_message_date)
        "#{type} #{chat.name} | JID: #{chat.jid} | Last: #{date}"
      end)

    footer = "\n\n(Timestamps are in UTC. Convert to your local timezone as needed.)"

    hint = "\n\nTip: Use get_messages(chat_id: \"<JID>\") to read messages from any of these chats."

    header <> rows <> footer <> hint
  end

  @doc """
  Returns the help text for the get_help tool.
  """
  @spec help_text() :: String.t()
  def help_text do
    bridge_path = WhatsappMcp.Config.bridge_source_path()

    """
    # WhatsApp MCP Tools - Usage Guide

    ## Getting Started

    The WhatsApp MCP server requires a Go bridge process to be running in a terminal.

    **First time setup:**
    1. Install Go if not already installed:
       - macOS: brew install go
       - Linux: apt install golang (or dnf install golang)
       - Windows: Download from https://go.dev/dl/

    2. Open a terminal and start the bridge:
       cd #{bridge_path} && go run .

    3. On first run, a QR code will appear in the terminal
       - Open WhatsApp on your phone
       - Go to Settings > Linked Devices
       - Tap "Link a Device"
       - Scan the QR code

    4. Keep the terminal open while using WhatsApp MCP

    **Checking connection status:**
    Use get_bridge_status to check if the bridge is running and connected.

    ## Phone Number Format

    WhatsApp uses JIDs (Jabber IDs) internally. Phone numbers must be:
    - Digits only, NO spaces, dashes, parentheses, or plus signs
    - Include country code WITHOUT the + prefix
    - Format: {country_code}{number}@s.whatsapp.net

    Examples:
    - "+60 18-252 3837" → "14155555678" (Malaysia)
    - "+1 (202) 555-1234" → "12025551234" (USA)
    - "+44 20 7946 0958" → "442079460958" (UK)

    ## Finding Contacts

    RECOMMENDED WORKFLOW:
    1. Use search_contacts with part of the name: search_contacts(query: "Gabriel")
    2. Or use search_contacts with digits from the phone: search_contacts(query: "18252")
    3. Get the JID from results, then use it for other operations

    ALTERNATIVE - Search by chat name:
    - get_messages(chat_name: "Gabriel") - partial match on contact name
    - Works well for unique names

    ## IMPORTANT: Contact Name Limitations

    Contact names from your phone's address book are NOT available.
    Only names stored on WhatsApp's servers are searchable:
    - "Push names" (names users set in WhatsApp Settings > Profile > Name)
    - WhatsApp Business profile names
    - Group chat names

    If a contact hasn't set a push name, they'll only appear as their phone number.

    If you can't find a contact by name, ASK THE USER for the phone number.
    Example: "I couldn't find 'John' - they may not have set a WhatsApp display
    name. Could you provide their phone number? (Include country code, e.g., 12025551234)"

    ## JID Types

    - Individual chats: {phone}@s.whatsapp.net (e.g., "14155555678@s.whatsapp.net")
    - Linked ID chats: {id}@lid (e.g., "24537215303857@lid") - newer WhatsApp format
    - Group chats: {id}@g.us (e.g., "120363123456789@g.us")

    NOTE: Some contacts appear as @lid instead of @s.whatsapp.net. This is normal.
    Use the JID exactly as returned by search results.

    ## LID Contact Resolution

    WhatsApp's newer Linked ID (@lid) format stores contacts as numeric IDs instead of
    phone numbers. The bridge automatically resolves these to display names:

    - Contact names are cached when messages are received or during history sync
    - search_contacts searches both phone numbers AND cached contact names
    - list_chats shows contact names (not numeric IDs) for @lid contacts
    - If a contact shows as a numeric ID, they haven't been resolved yet

    To manually resolve an @lid contact: The bridge resolves contacts automatically
    when you interact with them. For unresolved contacts, search by name instead of
    phone number.

    ## Common Patterns

    Find and message someone:
    1. search_contacts(query: "Gabriel") → get JID
    2. send_message(recipient: "14155555678", message: "Hello!")

    Find recent conversation:
    1. search_contacts(query: "Gabriel") → get JID
    2. get_last_interaction(contact_jid: "14155555678@s.whatsapp.net")

    Search then get context:
    1. search_messages(query: "meeting") → find message
    2. get_message_context(message_id: "ABC123") → see surrounding messages

    ## Timestamp Filtering

    Use `before` and `after` parameters in get_messages to filter by date:
    - get_messages(chat_id: "...", after: "2025-12-10T00:00:00Z", before: "2025-12-11T23:59:59Z")

    **IMPORTANT: All timestamps are stored in UTC.**

    Timestamp format: ISO8601 (e.g., "2025-12-11T10:00:00Z" or "2025-12-11T10:00:00+00:00")
    If no timezone specified, UTC (+00:00) is assumed.

    **For timezone conversion:**
    - Ask the user for their local timezone first
    - Convert their local time to UTC before filtering
    - Example: User in UTC+8 asking for "10 AM today" → use "02:00:00Z" (10:00 - 8 hours)

    ## Tips

    - Contact names are case-insensitive partial matches
    - Phone searches work on any part of the number
    - Use list_chats first to see available chats if unsure
    - Groups have "@g.us" suffix, individuals have "@s.whatsapp.net" or "@lid"
    - If search_contacts doesn't find someone, try search_messages with their name
    - Always use the exact JID returned by search results (don't modify it)
    - @lid contacts automatically show their real names once resolved
    """
  end

  # Helper functions

  @doc """
  Gets chat info for the message summary header.
  """
  @spec get_chat_info_for_messages(map(), keyword()) :: map() | nil
  def get_chat_info_for_messages(args, opts) do
    db_opts = maybe_add([], :db_path, opts[:db_path])

    cond do
      args["chat_id"] ->
        case Database.get_chat(Keyword.put(db_opts, :jid, args["chat_id"])) do
          {:ok, chat} -> chat
          _ -> nil
        end

      args["chat_name"] ->
        # Look up chat by name to get the resolved JID
        case Database.get_chat_by_name(Keyword.put(db_opts, :name, args["chat_name"])) do
          {:ok, chat} -> chat
          _ -> nil
        end

      true ->
        nil
    end
  end

  @doc """
  Conditionally adds a key-value pair to an options list.
  """
  @spec maybe_add(keyword(), atom(), term()) :: keyword()
  def maybe_add(opts, _key, nil), do: opts
  def maybe_add(opts, key, value), do: Keyword.put(opts, key, value)

  @doc """
  Truncates text to a maximum length, adding "..." if truncated.

  Uses `String.length/1` (character count) rather than `byte_size/1` to
  properly handle UTF-8 characters like emojis and non-ASCII names.
  """
  @spec truncate(String.t(), non_neg_integer()) :: String.t()
  def truncate(text, max_length) when is_binary(text) do
    if String.length(text) <= max_length do
      text
    else
      String.slice(text, 0, max_length) <> "..."
    end
  end

  # Private helper functions

  # Formats a header line for paginated lists
  # Output example: "Found 5 chats (showing 1-5 of 127 total, offset: 0):\n\n"
  defp format_list_header(item_type, items, pagination)

  defp format_list_header(item_type, items, nil) do
    "Found #{length(items)} #{item_type}:\n\n"
  end

  defp format_list_header(item_type, items, %{total: total} = pagination) do
    count = length(items)
    offset = Map.get(pagination, :offset, 0)

    if count == 0 do
      "Found 0 #{item_type} (0 total):\n\n"
    else
      start_idx = offset + 1
      end_idx = offset + count
      "Found #{count} #{item_type} (showing #{start_idx}-#{end_idx} of #{total} total, offset: #{offset}):\n\n"
    end
  end

  defp build_chat_summary(messages, chat_info, pagination) do
    displayed = length(messages)
    from_me = Enum.count(messages, & &1.is_from_me)
    from_them = displayed - from_me

    chat_line = format_chat_line(chat_info)
    date_line = format_date_line(messages)
    count_line = format_count_line(displayed, from_me, from_them, pagination)
    media_line = format_media_line(messages)

    chat_line <> date_line <> count_line <> media_line <> "\n---\n\n"
  end

  defp format_chat_line(nil), do: ""
  defp format_chat_line(chat_info), do: "Chat: #{chat_info.name} (#{chat_info.jid})\n"

  defp format_date_line(messages) do
    timestamps = Enum.map(messages, & &1.timestamp)
    first_date = List.first(timestamps)
    last_date = List.last(timestamps)

    cond do
      first_date && last_date && first_date != last_date ->
        "Period: #{format_date(first_date)} to #{format_date(last_date)}\n"

      first_date ->
        "Date: #{format_date(first_date)}\n"

      true ->
        ""
    end
  end

  defp format_count_line(displayed, from_me, from_them, %{total: total, offset: offset}) do
    start_idx = offset + 1
    end_idx = offset + displayed
    "Messages: showing #{start_idx}-#{end_idx} of #{total} total (#{from_me} from you, #{from_them} from them)\n"
  end

  defp format_count_line(displayed, from_me, from_them, _pagination) do
    "Messages: #{displayed} total (#{from_me} from you, #{from_them} from them)\n"
  end

  defp format_media_line(messages) do
    media_counts =
      messages
      |> Enum.filter(&(&1.media_type && &1.media_type != ""))
      |> Enum.group_by(& &1.media_type)
      |> Enum.map(fn {type, items} -> {type, length(items)} end)
      |> Enum.sort_by(fn {_type, count} -> -count end)

    if media_counts == [] do
      ""
    else
      media_str =
        Enum.map_join(media_counts, ", ", fn {type, count} ->
          "#{count} #{type}"
        end)

      "Attachments: #{media_str}\n"
    end
  end

  # Extracts just the date portion from a timestamp string.
  # Handles both "YYYY-MM-DD HH:MM:SS" and "YYYY-MM-DDTHH:MM:SS" formats.
  # Returns empty string for nil/empty/malformed input.
  @spec format_date(String.t() | nil) :: String.t()
  defp format_date(nil), do: ""
  defp format_date(""), do: ""

  defp format_date(timestamp) when is_binary(timestamp) do
    # Normalize T separator to space, then extract date portion
    normalized = String.replace(timestamp, "T", " ")

    case String.split(normalized, " ", parts: 2) do
      [date | _] when byte_size(date) >= 10 ->
        # Validate it looks like a date (YYYY-MM-DD)
        if Regex.match?(~r/^\d{4}-\d{2}-\d{2}/, date) do
          String.slice(date, 0, 10)
        else
          ""
        end

      _ ->
        ""
    end
  end

  # Format timestamp for display, handling various input formats
  # Input formats supported:
  #   - ISO8601: "2025-12-11T16:43:10Z", "2025-12-11T16:43:10+08:00"
  #   - SQL-style: "2025-12-11 16:43:10", "2025-12-11 16:43:10+08:00"
  # Output: "2025-12-11 16:43" or "(unknown)"
  defp format_timestamp(nil), do: "(unknown)"
  defp format_timestamp(""), do: "(unknown)"

  defp format_timestamp(timestamp) when is_binary(timestamp) do
    # Normalize T separator to space for consistent parsing
    normalized = String.replace(timestamp, "T", " ")

    # Try DateTime parsing for ISO8601-like formats
    case parse_datetime(normalized) do
      {:ok, datetime} ->
        # Format as "YYYY-MM-DD HH:MM" (no seconds, no timezone)
        Calendar.strftime(datetime, "%Y-%m-%d %H:%M")

      :error ->
        # Fallback: use regex for edge cases
        format_timestamp_fallback(timestamp)
    end
  end

  defp format_timestamp(_), do: "(unknown)"

  # Attempts to parse datetime from various formats
  @spec parse_datetime(String.t()) :: {:ok, DateTime.t() | NaiveDateTime.t()} | :error
  defp parse_datetime(timestamp) do
    # Try parsing with timezone info first
    case DateTime.from_iso8601(String.replace(timestamp, " ", "T")) do
      {:ok, dt, _offset} ->
        {:ok, dt}

      {:error, _} ->
        # Try NaiveDateTime for timestamps without timezone
        case NaiveDateTime.from_iso8601(String.replace(timestamp, " ", "T")) do
          {:ok, ndt} -> {:ok, ndt}
          {:error, _} -> try_naive_datetime_parse(timestamp)
        end
    end
  end

  # Handle SQL-style timestamps like "2025-12-11 16:43:10+08:00"
  @spec try_naive_datetime_parse(String.t()) :: {:ok, NaiveDateTime.t()} | :error
  defp try_naive_datetime_parse(timestamp) do
    # Strip timezone offset if present, then parse as NaiveDateTime
    cleaned = Regex.replace(~r/[+-]\d{2}:\d{2}$/, timestamp, "")

    case NaiveDateTime.from_iso8601(String.replace(cleaned, " ", "T")) do
      {:ok, ndt} -> {:ok, ndt}
      {:error, _} -> :error
    end
  end

  # Fallback using regex when DateTime parsing fails
  @spec format_timestamp_fallback(String.t()) :: String.t()
  defp format_timestamp_fallback(timestamp) do
    timestamp
    |> String.replace(~r/[+-]\d{2}:\d{2}$/, "")
    |> String.replace(~r/:\d{2}$/, "")
  end

  defp format_media_indicator(nil), do: ""
  defp format_media_indicator(""), do: ""
  defp format_media_indicator("image"), do: " [📷 image]"
  defp format_media_indicator("video"), do: " [🎬 video]"
  defp format_media_indicator("audio"), do: " [🎵 audio]"
  defp format_media_indicator("ptt"), do: " [🎤 voice]"
  defp format_media_indicator("document"), do: " [📄 document]"
  defp format_media_indicator(other), do: " [📎 #{other}]"

  # Format linked JID indicator for chats
  # Shows when a chat has a linked JID (e.g., @lid linked to @s.whatsapp.net)
  defp format_linked_jid(nil), do: ""
  defp format_linked_jid(""), do: ""
  defp format_linked_jid(linked_jid), do: " [linked: #{linked_jid}]"

  # Format source JID indicator for merged messages
  # Only shows when message is from a different JID than the main chat
  defp format_source_jid(nil, _chat_info), do: ""
  defp format_source_jid("", _chat_info), do: ""
  defp format_source_jid(source_jid, nil), do: " [from: #{source_jid}]"

  defp format_source_jid(source_jid, %{jid: chat_jid}) when source_jid == chat_jid, do: ""

  defp format_source_jid(source_jid, %{jid: _chat_jid}), do: " [from: #{source_jid}]"

  defp format_source_jid(_source_jid, _chat_info), do: ""

  defp format_message_content(nil, nil), do: "(empty message)"
  defp format_message_content(nil, ""), do: "(empty message)"
  defp format_message_content(nil, media_type), do: "(#{media_type} attached)"
  defp format_message_content("", nil), do: "(empty message)"
  defp format_message_content("", ""), do: "(empty message)"
  defp format_message_content("", media_type), do: "(#{media_type} attached)"
  defp format_message_content(text, _media_type), do: text

  defp format_context_messages(messages, section_header) do
    rows =
      Enum.map_join(messages, "\n\n", fn msg ->
        from_me = if msg.is_from_me, do: " (you)", else: ""
        media = format_media_indicator(msg.media_type)
        "[#{msg.timestamp}] #{msg.sender}#{from_me}#{media}:\n#{msg.text || "(no text)"}"
      end)

    section_header <> rows <> "\n\n"
  end

  # Builds a hint for messages output, using actual JID when available
  defp build_messages_hint(nil) do
    "\n\nTip: Use send_message(recipient: \"<JID>\", message: \"...\") to reply to this conversation."
  end

  defp build_messages_hint(%{jid: jid}) do
    "\n\nTip: Use send_message(recipient: \"#{jid}\", message: \"...\") to reply to this conversation."
  end

  # Contact/User tool formatters

  @doc """
  Formats the is_on_whatsapp result.
  """
  @spec format_is_on_whatsapp_result({:ok, list()} | {:error, term()}) ::
          {:ok, String.t()} | {:error, String.t()}
  def format_is_on_whatsapp_result({:ok, []}) do
    {:ok, "No results returned."}
  end

  def format_is_on_whatsapp_result({:ok, results}) when is_list(results) do
    formatted = Enum.map_join(results, "\n", &format_whatsapp_result_line/1)
    registered_count = Enum.count(results, & &1.is_on_whatsapp)
    total_count = length(results)
    summary = "\n\nSummary: #{registered_count}/#{total_count} phone numbers are on WhatsApp."

    {:ok, "WhatsApp Registration Status:\n\n" <> formatted <> summary}
  end

  def format_is_on_whatsapp_result(error), do: format_bridge_error(error)

  defp format_whatsapp_result_line(result) do
    status = if result.is_on_whatsapp, do: "✓ Registered", else: "✗ Not registered"
    jid_info = if result.jid, do: " | JID: #{result.jid}", else: ""
    "#{result.phone}: #{status}#{jid_info}"
  end

  @doc """
  Formats the profile picture result.
  """
  @spec format_profile_picture_result({:ok, map()} | {:error, term()}) ::
          {:ok, String.t()} | {:error, String.t()}
  def format_profile_picture_result({:ok, %{url: url, id: id}}) do
    {:ok, "Profile Picture:\nURL: #{url}\nID: #{id}\n\nNote: This URL is temporary and may expire."}
  end

  def format_profile_picture_result(error), do: format_bridge_error(error)

  @doc """
  Formats the blocklist result.
  """
  @spec format_blocklist_result({:ok, list()} | {:error, term()}) ::
          {:ok, String.t()} | {:error, String.t()}
  def format_blocklist_result({:ok, blocklist}) when is_list(blocklist) do
    if Enum.empty?(blocklist) do
      {:ok, "Your blocklist is empty. No contacts are currently blocked."}
    else
      formatted = Enum.map_join(blocklist, "\n", fn jid -> "- #{jid}" end)
      {:ok, "Blocked Contacts (#{length(blocklist)}):\n\n" <> formatted}
    end
  end

  def format_blocklist_result(error), do: format_bridge_error(error)

  # Group tool formatters

  @doc """
  Formats the list_groups result.
  """
  @spec format_list_groups_result({:ok, list()} | {:error, term()}) ::
          {:ok, String.t()} | {:error, String.t()}
  def format_list_groups_result({:ok, groups}) when is_list(groups) do
    if Enum.empty?(groups) do
      {:ok, "You haven't joined any groups."}
    else
      formatted = Enum.map_join(groups, "\n\n", &format_group_summary/1)
      hint = "\n\nTip: Use get_group_info(jid: \"<JID>\") to see full member list and details."
      {:ok, "Joined Groups (#{length(groups)}):\n\n" <> formatted <> hint}
    end
  end

  def format_list_groups_result(error), do: format_bridge_error(error)

  defp format_group_summary(group) do
    name = group["name"] || "(unnamed)"
    jid = group["jid"]
    topic = if group["topic"] && group["topic"] != "", do: "\n  Topic: #{group["topic"]}", else: ""
    participant_count = group["participant_count"] || 0
    settings = format_group_settings(group)

    "#{name}\n  JID: #{jid}\n  Members: #{participant_count}#{topic}#{settings}"
  end

  defp format_group_settings(group) do
    settings = []
    settings = if group["is_announce"], do: ["announce-only" | settings], else: settings
    settings = if group["is_locked"], do: ["locked" | settings], else: settings

    if Enum.empty?(settings) do
      ""
    else
      "\n  Settings: " <> Enum.join(settings, ", ")
    end
  end

  @doc """
  Formats the get_group_info result.
  """
  @spec format_group_info_result({:ok, map()} | {:error, term()}) ::
          {:ok, String.t()} | {:error, String.t()}
  def format_group_info_result({:ok, group}) when is_map(group) do
    name = group["name"] || "(unnamed)"
    jid = group["jid"]

    header = "Group: #{name}\nJID: #{jid}\n"

    topic_section =
      if group["topic"] && group["topic"] != "" do
        topic_info =
          if group["topic_set_by"] do
            " (set by #{group["topic_set_by"]})"
          else
            ""
          end

        "Topic: #{group["topic"]}#{topic_info}\n"
      else
        ""
      end

    settings_section = format_group_settings_section(group)
    participants_section = format_participants_section(group)

    hint = "\n\nTip: Use send_message(recipient: \"#{jid}\", message: \"...\") to send a message to this group."

    {:ok, header <> topic_section <> settings_section <> participants_section <> hint}
  end

  def format_group_info_result(error), do: format_bridge_error(error)

  @doc """
  Formats the get_group_invite_link result.
  """
  @spec format_group_invite_link_result({:ok, String.t()} | {:error, term()}) ::
          {:ok, String.t()} | {:error, String.t()}
  def format_group_invite_link_result({:ok, invite_link}) when is_binary(invite_link) do
    {:ok,
     """
     Invite Link: #{invite_link}

     Share this link to invite people to the group.
     Tip: Use get_group_invite_link(jid: "...", reset: true) to invalidate this link and generate a new one.\
     """}
  end

  def format_group_invite_link_result(error), do: format_bridge_error(error)

  @doc """
  Formats the join_group result.
  """
  @spec format_join_group_result({:ok, map()} | {:error, term()}) ::
          {:ok, String.t()} | {:error, String.t()}
  def format_join_group_result({:ok, %{group_jid: group_jid, message: message}}) do
    {:ok,
     """
     #{message}

     Group JID: #{group_jid}

     Tip: Use get_messages(chat_id: "#{group_jid}") to read messages from this group.\
     """}
  end

  def format_join_group_result(error), do: format_bridge_error(error)

  @doc """
  Formats the create_group result from the Bridge.

  Displays the newly created group's information including JID, name, and participant count.
  """
  @spec format_create_group_result({:ok, map()} | {:error, term()}) ::
          {:ok, String.t()} | {:error, String.t()}
  def format_create_group_result({:ok, group}) when is_map(group) do
    jid = group["jid"] || "unknown"
    name = group["name"] || "unknown"
    participant_count = group["participant_count"] || 0

    {:ok,
     """
     Successfully created group "#{name}"

     Group JID: #{jid}
     Participants: #{participant_count}

     Tip: Use get_messages(chat_id: "#{jid}") to read messages from this group.\
     """}
  end

  def format_create_group_result(error), do: format_bridge_error(error)

  @doc """
  Formats the leave_group result from the Bridge.

  Confirms that the user has left the group.
  """
  @spec format_leave_group_result({:ok, String.t()} | {:error, term()}) ::
          {:ok, String.t()} | {:error, String.t()}
  def format_leave_group_result({:ok, message}) when is_binary(message) do
    {:ok, message}
  end

  def format_leave_group_result(error), do: format_bridge_error(error)

  @doc """
  Formats the list_contacts result from the Bridge.

  Shows synced WhatsApp contacts with their names and redacted phone numbers.
  Redacted phone numbers are especially useful for identifying @lid contacts.
  """
  @spec format_list_contacts_result({:ok, map()} | {:error, term()}, non_neg_integer()) ::
          {:ok, String.t()} | {:error, String.t()}
  def format_list_contacts_result({:ok, %{contacts: contacts, total: total}}, offset) when is_list(contacts) do
    if Enum.empty?(contacts) do
      if offset > 0 do
        {:ok, "No more contacts (offset #{offset} exceeds total #{total})."}
      else
        {:ok, "No contacts synced. Your WhatsApp contacts will appear here after they sync from your phone."}
      end
    else
      # Calculate showing range
      showing_start = offset + 1
      showing_end = offset + length(contacts)

      header = "Synced Contacts (showing #{showing_start}-#{showing_end} of #{total}):\n\n"

      formatted = Enum.map_join(contacts, "\n\n", &format_contact_entry/1)

      hint =
        if total > showing_end do
          "\n\nTip: Use list_contacts(offset: #{showing_end}) to see more contacts."
        else
          ""
        end

      {:ok, header <> formatted <> hint}
    end
  end

  def format_list_contacts_result(error, _offset), do: format_bridge_error(error)

  defp format_contact_entry(contact) do
    jid = contact["jid"] || "unknown"

    # Build display name from available name fields
    display_name = get_contact_display_name(contact)

    # Build the entry line by line
    lines =
      Enum.reject(
        [
          "JID: #{jid}",
          display_name && "  Name: #{display_name}",
          contact["push_name"] not in ["", nil] && contact["push_name"] != display_name &&
            "  Push Name: #{contact["push_name"]}",
          contact["business_name"] not in ["", nil] && "  Business: #{contact["business_name"]}",
          contact["redacted_phone"] not in ["", nil] && "  Redacted Phone: #{contact["redacted_phone"]}"
        ],
        &(&1 == false || is_nil(&1))
      )

    # Show push name if different from display name
    # Redacted phone is especially useful for @lid contacts
    Enum.join(lines, "\n")
  end

  defp get_contact_display_name(contact) do
    Enum.find_value(["full_name", "first_name", "push_name", "business_name"], fn key ->
      case contact[key] do
        value when value not in ["", nil] -> value
        _ -> nil
      end
    end)
  end

  @doc """
  Formats the merge_chats result from the Bridge.

  Shows the number of messages merged and confirms the source chat was deleted.
  """
  @spec format_merge_chats_result({:ok, map()} | {:error, term()}) ::
          {:ok, String.t()} | {:error, String.t()}
  def format_merge_chats_result({:ok, %{message: message, messages_moved: _count}}) do
    {:ok, "#{message}\n\nThe LID→phone link has been stored for future automatic resolution."}
  end

  def format_merge_chats_result(error), do: format_bridge_error(error)

  @doc """
  Formats the update_group_participants result from the Bridge.

  Shows the result of adding/removing/promoting/demoting group members,
  including any per-participant errors.
  """
  @spec format_update_participants_result({:ok, map()} | {:error, term()}) ::
          {:ok, String.t()} | {:error, String.t()}
  def format_update_participants_result({:ok, %{message: message, participants: participants}}) do
    # Check if any participants had errors
    errors =
      participants
      |> Enum.filter(fn p -> p.error_code != 0 end)
      |> Enum.map(fn p -> "  - #{p.jid}: error code #{p.error_code}" end)

    result =
      if Enum.empty?(errors) do
        message
      else
        message <> "\n\nSome operations failed:\n" <> Enum.join(errors, "\n")
      end

    {:ok, result}
  end

  def format_update_participants_result(error), do: format_bridge_error(error)

  defp format_group_settings_section(group) do
    [
      group["owner_jid"] && "Owner: #{group["owner_jid"]}",
      group["created_at"] && "Created: #{group["created_at"]}",
      group["is_announce"] && "Mode: Announce-only (only admins can send messages)",
      group["is_locked"] && "Locked: Yes (only admins can edit group info)"
    ]
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> ""
      lines -> Enum.join(lines, "\n") <> "\n"
    end
  end

  defp format_participants_section(group) do
    participants = group["participants"] || []
    count = group["participant_count"] || length(participants)

    if Enum.empty?(participants) do
      "Members: #{count}\n"
    else
      admins = Enum.filter(participants, & &1["is_admin"])
      members = Enum.reject(participants, & &1["is_admin"])

      admin_lines = format_admin_lines(admins)
      member_lines = format_member_lines(members)

      admin_section = if admin_lines == "", do: "", else: "Admins:\n#{admin_lines}\n"
      member_section = if member_lines == "", do: "", else: "Members:\n#{member_lines}\n"

      "\nParticipants (#{count}):\n" <> admin_section <> member_section
    end
  end

  defp format_admin_lines(admins) do
    Enum.map_join(admins, "\n", fn p ->
      role = if p["is_super_admin"], do: " (super admin)", else: " (admin)"
      "  - #{p["jid"]}#{role}"
    end)
  end

  defp format_member_lines(members) do
    Enum.map_join(members, "\n", fn p -> "  - #{p["jid"]}" end)
  end

  @doc """
  Formats the privacy settings result from the Bridge.

  Shows all current privacy settings in a readable format.
  """
  @spec format_privacy_settings_result({:ok, map()} | {:error, term()}) ::
          {:ok, String.t()} | {:error, String.t()}
  def format_privacy_settings_result({:ok, settings}) do
    lines = [
      "Privacy Settings:",
      "",
      "• Group Add: #{format_privacy_value(settings.group_add, "Who can add you to groups")}",
      "• Last Seen: #{format_privacy_value(settings.last_seen, "Who can see your last seen")}",
      "• Status: #{format_privacy_value(settings.status, "Who can see your status/about")}",
      "• Profile Photo: #{format_privacy_value(settings.profile, "Who can see your profile photo")}",
      "• Read Receipts: #{format_privacy_value(settings.read_receipts, "Blue ticks")}",
      "• Online Status: #{format_privacy_value(settings.online, "Who can see you online")}",
      "• Calls: #{format_privacy_value(settings.call_add, "Who can call you")}",
      "",
      ~s{To change a setting, use set_privacy_setting(setting: "...", value: "...")}
    ]

    {:ok, Enum.join(lines, "\n")}
  end

  def format_privacy_settings_result(error), do: format_bridge_error(error)

  defp format_privacy_value(nil, _desc), do: "(not set)"
  defp format_privacy_value("", _desc), do: "(not set)"
  defp format_privacy_value("all", _desc), do: "Everyone"
  defp format_privacy_value("contacts", _desc), do: "My Contacts"
  defp format_privacy_value("contact_blacklist", _desc), do: "My Contacts Except..."
  defp format_privacy_value("match_last_seen", _desc), do: "Same as Last Seen"
  defp format_privacy_value("known", _desc), do: "Known Contacts"
  defp format_privacy_value("none", _desc), do: "Nobody"
  defp format_privacy_value(value, _desc), do: value

  @doc """
  Formats the business profile result from the Bridge.

  Shows business details in a readable format, or a message if not a business account.
  """
  @spec format_business_profile_result({:ok, map()} | {:error, term()}) ::
          {:ok, String.t()} | {:error, String.t()}
  def format_business_profile_result({:ok, nil}) do
    {:ok, "This contact is not a WhatsApp Business account."}
  end

  def format_business_profile_result({:ok, profile}) when is_map(profile) do
    lines =
      Enum.reject(
        [
          "Business Profile:",
          "",
          profile["jid"] && "JID: #{profile["jid"]}",
          profile["address"] not in ["", nil] && "Address: #{profile["address"]}",
          profile["email"] not in ["", nil] && "Email: #{profile["email"]}",
          format_business_categories(profile["categories"]),
          format_business_hours(profile["business_hours"], profile["business_hours_timezone"])
        ],
        &(&1 == false || is_nil(&1) || &1 == "")
      )

    {:ok, Enum.join(lines, "\n")}
  end

  def format_business_profile_result(error), do: format_bridge_error(error)

  defp format_business_categories(nil), do: nil
  defp format_business_categories([]), do: nil

  defp format_business_categories(categories) do
    names = Enum.map_join(categories, ", ", fn cat -> cat["name"] || cat["id"] end)
    "Categories: #{names}"
  end

  defp format_business_hours(nil, _tz), do: nil
  defp format_business_hours([], _tz), do: nil

  defp format_business_hours(hours, timezone) do
    tz_info = if timezone in ["", nil], do: "", else: " (#{timezone})"

    days_formatted =
      Enum.map_join(hours, "\n  ", fn day ->
        day_name =
          case day["day_of_week"] do
            nil -> "Unknown"
            "" -> "Unknown"
            name -> String.capitalize(name)
          end

        case day["mode"] do
          "open" -> "#{day_name}: #{day["open_time"]} - #{day["close_time"]}"
          "closed" -> "#{day_name}: Closed"
          mode -> "#{day_name}: #{mode}"
        end
      end)

    "Business Hours#{tz_info}:\n  #{days_formatted}"
  end

  # Newsletter formatters

  @doc """
  Formats the list_newsletters result from the Bridge.

  Shows subscribed WhatsApp channels/newsletters with their metadata.
  """
  @spec format_list_newsletters_result({:ok, list()} | {:error, term()}) ::
          {:ok, String.t()} | {:error, String.t()}
  def format_list_newsletters_result({:ok, newsletters}) when is_list(newsletters) do
    if Enum.empty?(newsletters) do
      {:ok, "You haven't subscribed to any newsletters/channels."}
    else
      formatted = Enum.map_join(newsletters, "\n\n", &format_newsletter_summary/1)
      hint = "\n\nTip: Use get_newsletter_info(jid: \"<JID>\") to see full details."
      {:ok, "Subscribed Newsletters (#{length(newsletters)}):\n\n" <> formatted <> hint}
    end
  end

  def format_list_newsletters_result(error), do: format_bridge_error(error)

  defp format_newsletter_summary(newsletter) do
    name = newsletter["name"] || "(unnamed)"
    jid = newsletter["id"]
    subscriber_count = newsletter["subscriber_count"] || 0

    description =
      if newsletter["description"] && newsletter["description"] != "",
        do: "\n  #{truncate(newsletter["description"], 80)}",
        else: ""

    muted = if newsletter["is_muted"], do: " [muted]", else: ""

    "#{name}#{muted}\n  JID: #{jid}\n  Subscribers: #{format_subscriber_count(subscriber_count)}#{description}"
  end

  defp format_subscriber_count(count) when count >= 1_000_000 do
    "#{Float.round(count / 1_000_000, 1)}M"
  end

  defp format_subscriber_count(count) when count >= 1_000 do
    "#{Float.round(count / 1_000, 1)}K"
  end

  defp format_subscriber_count(count), do: "#{count}"

  @doc """
  Formats the newsletter_info result from the Bridge.

  Shows detailed information about a specific newsletter/channel.
  """
  @spec format_newsletter_info_result({:ok, map()} | {:error, term()}) ::
          {:ok, String.t()} | {:error, String.t()}
  def format_newsletter_info_result({:ok, newsletter}) when is_map(newsletter) do
    name = newsletter["name"] || "(unnamed)"
    jid = newsletter["id"]

    lines =
      Enum.reject(
        [
          "Newsletter: #{name}",
          "JID: #{jid}",
          newsletter["subscriber_count"] && "Subscribers: #{format_subscriber_count(newsletter["subscriber_count"])}",
          newsletter["description"] not in ["", nil] && "Description: #{newsletter["description"]}",
          newsletter["invite_link"] not in ["", nil] && "Invite Link: #{newsletter["invite_link"]}",
          newsletter["created_at"] not in ["", nil] && "Created: #{newsletter["created_at"]}",
          newsletter["is_muted"] && "Status: Muted"
        ],
        &(&1 == false || is_nil(&1))
      )

    hint = "\n\nTip: Use get_newsletter_messages(jid: \"#{jid}\") to read posts from this channel."

    {:ok, Enum.join(lines, "\n") <> hint}
  end

  def format_newsletter_info_result(error), do: format_bridge_error(error)

  @doc """
  Formats the newsletter_messages result from the Bridge.

  Shows messages/posts from a newsletter/channel.
  """
  @spec format_newsletter_messages_result({:ok, list()} | {:error, term()}) ::
          {:ok, String.t()} | {:error, String.t()}
  def format_newsletter_messages_result({:ok, messages}) when is_list(messages) do
    if Enum.empty?(messages) do
      {:ok, "No messages found in this newsletter."}
    else
      formatted = Enum.map_join(messages, "\n\n", &format_newsletter_message/1)
      {:ok, "Newsletter Posts (#{length(messages)}):\n\n" <> formatted}
    end
  end

  def format_newsletter_messages_result(error), do: format_bridge_error(error)

  defp format_newsletter_message(msg) do
    timestamp = msg["timestamp"] || "(unknown time)"
    text = msg["text"] || "(no text)"
    media = if msg["media_type"] && msg["media_type"] != "", do: " [#{msg["media_type"]}]", else: ""

    views =
      if msg["view_count"] && msg["view_count"] > 0,
        do: " | #{format_subscriber_count(msg["view_count"])} views",
        else: ""

    "[#{timestamp}]#{media}#{views}\n#{text}"
  end
end
