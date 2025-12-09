defmodule WhatsappMcp.Tools.Handlers do
  @moduledoc """
  MCP tool handler implementations.

  Implements the logic for each tool, delegating to Database and Bridge
  modules and formatting results via Formatters.

  ## Adding New Tools

  To add a new tool:

  1. Add the tool definition in `WhatsappMcp.Tools.Definitions.list_tools/0`
  2. Add a 2-arity clause: `def call_tool("tool_name", args), do: call_tool("tool_name", args, [])`
  3. Add a 3-arity clause implementing the tool logic
  4. Return `{:ok, formatted_string}` or `{:error, reason}`

  All tool handlers follow this contract:

      @spec call_tool(String.t(), map(), keyword()) :: {:ok, String.t()} | {:error, term()}

  """

  alias WhatsappMcp.Bridge
  alias WhatsappMcp.Database
  alias WhatsappMcp.Tools.Formatters

  @default_chat_limit 50
  @default_message_limit 100
  @default_search_limit 50
  @default_contact_limit 50
  @valid_disappearing_timers ~w(off 24h 7d 90d)
  # Maximum number of @lid JIDs to resolve per list_chats request
  @max_lid_resolution_per_request 5

  @doc """
  Calls a tool by name with the given arguments.

  Returns `{:ok, text}` with formatted result or `{:error, reason}`.
  """
  @spec call_tool(String.t(), map()) :: {:ok, String.t()} | {:error, term()}
  def call_tool("list_chats", args), do: call_tool("list_chats", args, [])
  def call_tool("get_messages", args), do: call_tool("get_messages", args, [])
  def call_tool("search_messages", args), do: call_tool("search_messages", args, [])
  def call_tool("send_message", args), do: call_tool("send_message", args, [])
  def call_tool("send_file", args), do: call_tool("send_file", args, [])
  def call_tool("send_audio_message", args), do: call_tool("send_audio_message", args, [])
  def call_tool("download_media", args), do: call_tool("download_media", args, [])
  def call_tool("search_contacts", args), do: call_tool("search_contacts", args, [])
  def call_tool("get_chat", args), do: call_tool("get_chat", args, [])
  def call_tool("get_direct_chat_by_contact", args), do: call_tool("get_direct_chat_by_contact", args, [])
  def call_tool("get_message_context", args), do: call_tool("get_message_context", args, [])
  def call_tool("get_last_interaction", args), do: call_tool("get_last_interaction", args, [])
  def call_tool("get_contact_chats", args), do: call_tool("get_contact_chats", args, [])
  def call_tool("get_bridge_status", _args), do: call_tool("get_bridge_status", %{}, [])
  def call_tool("get_help", _args), do: {:ok, Formatters.help_text()}
  def call_tool("send_typing", args), do: call_tool("send_typing", args, [])
  def call_tool("mark_read", args), do: call_tool("mark_read", args, [])
  def call_tool("react_to_message", args), do: call_tool("react_to_message", args, [])
  def call_tool("delete_message", args), do: call_tool("delete_message", args, [])
  def call_tool("reply_to_message", args), do: call_tool("reply_to_message", args, [])
  def call_tool("edit_message", args), do: call_tool("edit_message", args, [])
  def call_tool("send_location", args), do: call_tool("send_location", args, [])
  def call_tool("set_presence", args), do: call_tool("set_presence", args, [])
  def call_tool("subscribe_presence", args), do: call_tool("subscribe_presence", args, [])
  def call_tool("set_disappearing_timer", args), do: call_tool("set_disappearing_timer", args, [])
  def call_tool("is_on_whatsapp", args), do: call_tool("is_on_whatsapp", args, [])
  def call_tool("get_profile_picture", args), do: call_tool("get_profile_picture", args, [])
  def call_tool("get_blocklist", _args), do: call_tool("get_blocklist", %{}, [])
  def call_tool("update_blocklist", args), do: call_tool("update_blocklist", args, [])
  def call_tool("create_poll", args), do: call_tool("create_poll", args, [])
  def call_tool("list_groups", _args), do: call_tool("list_groups", %{}, [])
  def call_tool("get_group_info", args), do: call_tool("get_group_info", args, [])
  def call_tool("get_group_invite_link", args), do: call_tool("get_group_invite_link", args, [])
  def call_tool("join_group", args), do: call_tool("join_group", args, [])
  def call_tool("create_group", args), do: call_tool("create_group", args, [])
  def call_tool("leave_group", args), do: call_tool("leave_group", args, [])
  def call_tool("list_contacts", args), do: call_tool("list_contacts", args, [])
  def call_tool("merge_chats", args), do: call_tool("merge_chats", args, [])

  def call_tool(unknown_tool, _args) do
    {:error, "Unknown tool: #{unknown_tool}"}
  end

  @doc """
  Calls tools with options for testing.

  ## Options
  - `:plug` - Plug for testing HTTP calls with Req.Test
  - `:db_path` - Override database path for testing
  """
  @spec call_tool(String.t(), map(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def call_tool("list_chats", args, opts) do
    limit = args["limit"] || @default_chat_limit
    offset = args["offset"] || 0

    db_opts = Formatters.maybe_add([limit: limit, offset: offset], :db_path, opts[:db_path])

    count_opts = Formatters.maybe_add([], :db_path, opts[:db_path])

    with {:ok, chats} <- Database.list_chats(db_opts),
         {:ok, total} <- Database.count_chats(count_opts) do
      # Proactively resolve unresolved @lid contacts and enrich with linked JIDs
      enriched_chats = enrich_chats_with_linked_jids(chats, opts)

      pagination = %{offset: offset, limit: limit, total: total, count: length(enriched_chats)}
      {:ok, Formatters.format_chats(enriched_chats, pagination)}
    end
  end

  def call_tool("get_messages", args, opts) do
    limit = args["limit"] || @default_message_limit
    offset = args["offset"] || 0

    db_opts =
      [limit: limit, offset: offset]
      |> Formatters.maybe_add(:chat_id, args["chat_id"])
      |> Formatters.maybe_add(:chat_name, args["chat_name"])
      |> Formatters.maybe_add(:before, args["before"])
      |> Formatters.maybe_add(:after, args["after"])
      |> Formatters.maybe_add(:db_path, opts[:db_path])

    count_opts =
      []
      |> Formatters.maybe_add(:chat_id, args["chat_id"])
      |> Formatters.maybe_add(:chat_name, args["chat_name"])
      |> Formatters.maybe_add(:before, args["before"])
      |> Formatters.maybe_add(:after, args["after"])
      |> Formatters.maybe_add(:db_path, opts[:db_path])

    # Get chat metadata for summary header
    chat_info = Formatters.get_chat_info_for_messages(args, opts)

    case Database.get_messages(db_opts) do
      {:ok, messages} ->
        case Database.count_messages(count_opts) do
          {:ok, total} ->
            pagination = %{offset: offset, limit: limit, total: total, count: length(messages)}
            {:ok, Formatters.format_messages_with_summary(messages, chat_info, pagination)}

          {:error, reason} ->
            {:error, format_db_error(reason)}
        end

      {:error, reason} ->
        {:error, format_db_error(reason)}
    end
  end

  def call_tool("search_messages", args, opts) do
    query = args["query"]
    has_media = args["has_media"] || false

    if query || has_media do
      limit = args["limit"] || @default_search_limit
      offset = args["offset"] || 0

      db_opts =
        [limit: limit, offset: offset, has_media: has_media]
        |> Formatters.maybe_add(:query, query)
        |> Formatters.maybe_add(:chat_id, args["chat_id"])
        |> Formatters.maybe_add(:db_path, opts[:db_path])

      count_opts =
        [has_media: has_media]
        |> Formatters.maybe_add(:query, query)
        |> Formatters.maybe_add(:chat_id, args["chat_id"])
        |> Formatters.maybe_add(:db_path, opts[:db_path])

      with {:ok, results} <- Database.search_messages(db_opts),
           {:ok, total} <- Database.count_search_results(count_opts) do
        pagination = %{offset: offset, limit: limit, total: total, count: length(results)}
        {:ok, Formatters.format_search_results(results, pagination)}
      end
    else
      {:error, "query parameter is required (or set has_media: true)"}
    end
  end

  def call_tool("search_contacts", args, opts) do
    query = args["query"]

    if query do
      limit = args["limit"] || @default_contact_limit

      db_opts = Formatters.maybe_add([query: query, limit: limit], :db_path, opts[:db_path])

      count_opts = Formatters.maybe_add([query: query], :db_path, opts[:db_path])

      with {:ok, contacts} <- Database.search_contacts(db_opts),
           {:ok, total} <- Database.count_contacts(count_opts) do
        pagination = %{limit: limit, total: total, count: length(contacts)}
        {:ok, Formatters.format_contacts(contacts, pagination)}
      end
    else
      {:error, "query parameter is required"}
    end
  end

  def call_tool("get_chat", args, opts) do
    jid = args["jid"]

    if jid do
      db_opts = Formatters.maybe_add([jid: jid], :db_path, opts[:db_path])

      case Database.get_chat(db_opts) do
        {:ok, chat} -> {:ok, Formatters.format_chat(chat)}
        {:error, :not_found} -> {:error, "Chat not found: #{jid}"}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, "jid parameter is required"}
    end
  end

  def call_tool("get_direct_chat_by_contact", args, opts) do
    phone = args["phone"]

    if phone do
      db_opts = Formatters.maybe_add([phone: phone], :db_path, opts[:db_path])

      case Database.get_chat_by_phone(db_opts) do
        {:ok, chat} -> {:ok, Formatters.format_chat(chat)}
        {:error, :not_found} -> {:error, "No chat found for phone: #{phone}"}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, "phone parameter is required"}
    end
  end

  def call_tool("get_message_context", args, opts) do
    message_id = args["message_id"]

    if message_id do
      db_opts =
        [message_id: message_id]
        |> Formatters.maybe_add(:before, args["before"])
        |> Formatters.maybe_add(:after, args["after"])
        |> Formatters.maybe_add(:db_path, opts[:db_path])

      case Database.get_message_context(db_opts) do
        {:ok, context} -> {:ok, Formatters.format_message_context(context)}
        {:error, :not_found} -> {:error, "Message not found: #{message_id}"}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, "message_id parameter is required"}
    end
  end

  def call_tool("get_last_interaction", args, opts) do
    contact_jid = args["contact_jid"]

    if contact_jid do
      db_opts = Formatters.maybe_add([contact_jid: contact_jid], :db_path, opts[:db_path])

      case Database.get_last_interaction(db_opts) do
        {:ok, message} -> {:ok, Formatters.format_last_interaction(message, contact_jid, opts)}
        {:error, :not_found} -> {:error, "No messages found with contact: #{contact_jid}"}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, "contact_jid parameter is required"}
    end
  end

  def call_tool("get_contact_chats", args, opts) do
    contact_jid = args["contact_jid"]

    if contact_jid do
      limit = args["limit"] || @default_chat_limit

      db_opts = Formatters.maybe_add([contact_jid: contact_jid, limit: limit], :db_path, opts[:db_path])

      count_opts = Formatters.maybe_add([contact_jid: contact_jid], :db_path, opts[:db_path])

      with {:ok, chats} <- Database.get_contact_chats(db_opts),
           {:ok, total} <- Database.count_contact_chats(count_opts) do
        pagination = %{limit: limit, total: total, count: length(chats)}
        {:ok, Formatters.format_contact_chats(chats, pagination)}
      end
    else
      {:error, "contact_jid parameter is required"}
    end
  end

  def call_tool("send_message", args, opts) do
    with {:ok, recipient} <- validate_required(args["recipient"], "recipient"),
         {:ok, message} <- validate_required(args["message"], "message") do
      recipient
      |> Bridge.send_message(message, opts)
      |> Formatters.format_bridge_result()
    end
  end

  def call_tool("send_file", args, opts) do
    with {:ok, recipient} <- validate_required(args["recipient"], "recipient"),
         {:ok, file_path} <- validate_required(args["file_path"], "file_path") do
      caption = args["caption"] || ""

      recipient
      |> Bridge.send_file(file_path, caption, opts)
      |> Formatters.format_bridge_result()
    end
  end

  def call_tool("send_audio_message", args, opts) do
    with {:ok, recipient} <- validate_required(args["recipient"], "recipient"),
         {:ok, file_path} <- validate_required(args["file_path"], "file_path"),
         :ok <- validate_ogg_extension(file_path) do
      recipient
      |> Bridge.send_audio(file_path, opts)
      |> Formatters.format_bridge_result()
    end
  end

  def call_tool("download_media", args, opts) do
    with {:ok, message_id} <- validate_required(args["message_id"], "message_id"),
         {:ok, chat_jid} <- validate_required(args["chat_jid"], "chat_jid") do
      message_id
      |> Bridge.download_media(chat_jid, opts)
      |> Formatters.format_download_result()
    end
  end

  def call_tool("get_bridge_status", _args, opts) do
    # Get HTTP health check from bridge API
    http_status = Bridge.health_check(opts)
    Formatters.format_bridge_status(http_status)
  end

  def call_tool("send_typing", args, opts) do
    with {:ok, recipient} <- validate_required(args["recipient"], "recipient") do
      composing = args["composing"] != false

      recipient
      |> Bridge.send_typing(composing, opts)
      |> Formatters.format_bridge_result()
    end
  end

  def call_tool("mark_read", args, opts) do
    with {:ok, chat_jid} <- validate_required(args["chat_jid"], "chat_jid"),
         {:ok, message_ids} <- validate_message_ids(args["message_ids"]) do
      chat_jid
      |> Bridge.mark_read(message_ids, opts)
      |> Formatters.format_bridge_result()
    end
  end

  def call_tool("react_to_message", args, opts) do
    with {:ok, chat_jid} <- validate_required(args["chat_jid"], "chat_jid"),
         {:ok, message_id} <- validate_required(args["message_id"], "message_id"),
         {:ok, sender} <- validate_required(args["sender"], "sender") do
      emoji = args["emoji"] || ""

      chat_jid
      |> Bridge.send_reaction(message_id, sender, emoji, opts)
      |> Formatters.format_bridge_result()
    end
  end

  def call_tool("delete_message", args, opts) do
    with {:ok, chat_jid} <- validate_required(args["chat_jid"], "chat_jid"),
         {:ok, message_id} <- validate_required(args["message_id"], "message_id"),
         {:ok, sender} <- validate_required(args["sender"], "sender") do
      chat_jid
      |> Bridge.delete_message(message_id, sender, opts)
      |> Formatters.format_bridge_result()
    end
  end

  def call_tool("reply_to_message", args, opts) do
    with {:ok, recipient} <- validate_required(args["recipient"], "recipient"),
         {:ok, message} <- validate_required(args["message"], "message"),
         {:ok, quoted_message_id} <- validate_required(args["quoted_message_id"], "quoted_message_id"),
         {:ok, quoted_chat_jid} <- validate_required(args["quoted_chat_jid"], "quoted_chat_jid"),
         {:ok, quoted_sender} <- validate_required(args["quoted_sender"], "quoted_sender") do
      recipient
      |> Bridge.reply_to_message(message, quoted_message_id, quoted_chat_jid, quoted_sender, opts)
      |> Formatters.format_bridge_result()
    end
  end

  def call_tool("edit_message", args, opts) do
    with {:ok, chat_jid} <- validate_required(args["chat_jid"], "chat_jid"),
         {:ok, message_id} <- validate_required(args["message_id"], "message_id"),
         {:ok, new_content} <- validate_required(args["new_content"], "new_content") do
      chat_jid
      |> Bridge.edit_message(message_id, new_content, opts)
      |> Formatters.format_bridge_result()
    end
  end

  def call_tool("send_location", args, opts) do
    with {:ok, recipient} <- validate_required(args["recipient"], "recipient"),
         {:ok, latitude} <- validate_latitude(args["latitude"]),
         {:ok, longitude} <- validate_longitude(args["longitude"]) do
      location_opts =
        opts
        |> Formatters.maybe_add(:name, args["name"])
        |> Formatters.maybe_add(:address, args["address"])

      recipient
      |> Bridge.send_location(latitude, longitude, location_opts)
      |> Formatters.format_bridge_result()
    end
  end

  def call_tool("set_presence", args, opts) do
    case args["available"] do
      nil ->
        {:error, "available parameter is required"}

      available when is_boolean(available) ->
        available
        |> Bridge.set_presence(opts)
        |> Formatters.format_bridge_result()

      _other ->
        {:error, "available must be a boolean"}
    end
  end

  def call_tool("subscribe_presence", args, opts) do
    with {:ok, jid} <- validate_required(args["jid"], "jid") do
      jid
      |> Bridge.subscribe_presence(opts)
      |> Formatters.format_bridge_result()
    end
  end

  def call_tool("set_disappearing_timer", args, opts) do
    with {:ok, chat_jid} <- validate_required(args["chat_jid"], "chat_jid"),
         {:ok, timer} <- validate_disappearing_timer(args["timer"]) do
      chat_jid
      |> Bridge.set_disappearing_timer(timer, opts)
      |> Formatters.format_bridge_result()
    end
  end

  def call_tool("is_on_whatsapp", args, opts) do
    with {:ok, phones} <- validate_phones(args["phones"]) do
      phones
      |> Bridge.check_whatsapp_registration(opts)
      |> Formatters.format_is_on_whatsapp_result()
    end
  end

  def call_tool("get_profile_picture", args, opts) do
    with {:ok, jid} <- validate_required(args["jid"], "jid") do
      jid
      |> Bridge.get_profile_picture(opts)
      |> Formatters.format_profile_picture_result()
    end
  end

  def call_tool("get_blocklist", _args, opts) do
    opts
    |> Bridge.get_blocklist()
    |> Formatters.format_blocklist_result()
  end

  def call_tool("update_blocklist", args, opts) do
    with {:ok, jid} <- validate_required(args["jid"], "jid"),
         {:ok, action} <- validate_blocklist_action(args["action"]) do
      jid
      |> Bridge.update_blocklist(action, opts)
      |> Formatters.format_bridge_result()
    end
  end

  @min_poll_options 2
  @max_poll_options 12

  def call_tool("create_poll", args, opts) do
    with {:ok, recipient} <- validate_required(args["recipient"], "recipient"),
         {:ok, question} <- validate_required(args["question"], "question"),
         {:ok, options} <- validate_poll_options(args["options"]) do
      max_selections = args["max_selections"] || 1

      recipient
      |> Bridge.create_poll(question, options, max_selections, opts)
      |> Formatters.format_bridge_result()
    end
  end

  def call_tool("list_groups", _args, opts) do
    opts
    |> Bridge.list_groups()
    |> Formatters.format_list_groups_result()
  end

  def call_tool("get_group_info", args, opts) do
    with {:ok, jid} <- validate_required(args["jid"], "jid"),
         :ok <- validate_group_jid(jid) do
      jid
      |> Bridge.get_group_info(opts)
      |> Formatters.format_group_info_result()
    end
  end

  def call_tool("get_group_invite_link", args, opts) do
    with {:ok, jid} <- validate_required(args["jid"], "jid"),
         :ok <- validate_group_jid(jid) do
      reset = args["reset"] == true

      bridge_opts = if reset, do: Keyword.put(opts, :reset, true), else: opts

      jid
      |> Bridge.get_group_invite_link(bridge_opts)
      |> Formatters.format_group_invite_link_result()
    end
  end

  def call_tool("join_group", args, opts) do
    with {:ok, invite_link} <- validate_required(args["invite_link"], "invite_link") do
      invite_link
      |> Bridge.join_group(opts)
      |> Formatters.format_join_group_result()
    end
  end

  def call_tool("create_group", args, opts) do
    with {:ok, name} <- validate_required(args["name"], "name") do
      participants = args["participants"] || []

      name
      |> Bridge.create_group(participants, opts)
      |> Formatters.format_create_group_result()
    end
  end

  def call_tool("leave_group", args, opts) do
    with {:ok, jid} <- validate_required(args["jid"], "jid"),
         :ok <- validate_group_jid(jid) do
      jid
      |> Bridge.leave_group(opts)
      |> Formatters.format_leave_group_result()
    end
  end

  def call_tool("list_contacts", args, opts) do
    limit = args["limit"] || 100
    offset = args["offset"] || 0
    query = args["query"]

    bridge_opts =
      opts
      |> Keyword.put(:limit, limit)
      |> Keyword.put(:offset, offset)

    bridge_opts = if query, do: Keyword.put(bridge_opts, :query, query), else: bridge_opts

    bridge_opts
    |> Bridge.list_contacts()
    |> Formatters.format_list_contacts_result(offset)
  end

  def call_tool("merge_chats", args, opts) do
    with {:ok, source_jid} <- validate_required(args["source_jid"], "source_jid"),
         {:ok, target_jid} <- validate_required(args["target_jid"], "target_jid"),
         :ok <- validate_different_jids(source_jid, target_jid) do
      source_jid
      |> Bridge.merge_chats(target_jid, opts)
      |> Formatters.format_merge_chats_result()
    end
  end

  def call_tool("update_group_name", args, opts) do
    with {:ok, jid} <- validate_required(args["jid"], "jid"),
         {:ok, name} <- validate_required(args["name"], "name"),
         :ok <- validate_group_jid(jid) do
      jid
      |> Bridge.update_group_name(name, opts)
      |> Formatters.format_bridge_result()
    end
  end

  def call_tool("update_group_description", args, opts) do
    with {:ok, jid} <- validate_required(args["jid"], "jid"),
         :ok <- validate_group_jid(jid) do
      # Description can be empty string (to clear), so don't require it
      description = args["description"] || ""

      jid
      |> Bridge.update_group_description(description, opts)
      |> Formatters.format_bridge_result()
    end
  end

  def call_tool("update_group_settings", args, opts) do
    with {:ok, jid} <- validate_required(args["jid"], "jid"),
         :ok <- validate_group_jid(jid),
         :ok <- validate_at_least_one_setting(args["locked"], args["announce"]) do
      settings_opts =
        opts
        |> maybe_add_setting(:locked, args["locked"])
        |> maybe_add_setting(:announce, args["announce"])

      jid
      |> Bridge.update_group_settings(settings_opts)
      |> Formatters.format_bridge_result()
    end
  end

  def call_tool("manage_group_members", args, opts) do
    with {:ok, jid} <- validate_required(args["jid"], "jid"),
         {:ok, participants} <- validate_participants(args["participants"]),
         {:ok, action} <- validate_participant_action(args["action"]),
         :ok <- validate_group_jid(jid) do
      jid
      |> Bridge.update_group_participants(participants, action, opts)
      |> Formatters.format_update_participants_result()
    end
  end

  def call_tool("get_privacy_settings", _args, opts) do
    opts
    |> Bridge.get_privacy_settings()
    |> Formatters.format_privacy_settings_result()
  end

  def call_tool("set_privacy_setting", args, opts) do
    with {:ok, setting} <- validate_privacy_setting(args["setting"]),
         {:ok, value} <- validate_privacy_value(args["value"]) do
      setting
      |> Bridge.set_privacy_setting(value, opts)
      |> Formatters.format_bridge_result()
    end
  end

  def call_tool("get_business_profile", args, opts) do
    with {:ok, jid} <- validate_required(args["jid"], "jid") do
      jid
      |> Bridge.get_business_profile(opts)
      |> Formatters.format_business_profile_result()
    end
  end

  def call_tool("reject_call", args, opts) do
    with {:ok, call_from} <- validate_required(args["call_from"], "call_from"),
         {:ok, call_id} <- validate_required(args["call_id"], "call_id") do
      call_from
      |> Bridge.reject_call(call_id, opts)
      |> Formatters.format_bridge_result()
    end
  end

  def call_tool("list_newsletters", _args, opts) do
    opts
    |> Bridge.list_newsletters()
    |> Formatters.format_list_newsletters_result()
  end

  def call_tool("get_newsletter_info", args, opts) do
    with {:ok, jid} <- validate_required(args["jid"], "jid"),
         :ok <- validate_newsletter_jid(jid) do
      jid
      |> Bridge.get_newsletter_info(opts)
      |> Formatters.format_newsletter_info_result()
    end
  end

  def call_tool("get_newsletter_messages", args, opts) do
    with {:ok, jid} <- validate_required(args["jid"], "jid"),
         :ok <- validate_newsletter_jid(jid) do
      msg_opts =
        opts
        |> maybe_add_opt(:count, args["count"])
        |> maybe_add_opt(:before, args["before"])

      jid
      |> Bridge.get_newsletter_messages(msg_opts)
      |> Formatters.format_newsletter_messages_result()
    end
  end

  def call_tool("follow_newsletter", args, opts) do
    with {:ok, jid} <- validate_required(args["jid"], "jid"),
         :ok <- validate_newsletter_jid(jid) do
      jid
      |> Bridge.follow_newsletter(opts)
      |> Formatters.format_bridge_result()
    end
  end

  def call_tool("unfollow_newsletter", args, opts) do
    with {:ok, jid} <- validate_required(args["jid"], "jid"),
         :ok <- validate_newsletter_jid(jid) do
      jid
      |> Bridge.unfollow_newsletter(opts)
      |> Formatters.format_bridge_result()
    end
  end

  # Private validation helpers

  defp validate_different_jids(source, target) when source == target do
    {:error, "source_jid and target_jid cannot be the same"}
  end

  defp validate_different_jids(_source, _target), do: :ok

  defp validate_ogg_extension(file_path) do
    if String.ends_with?(String.downcase(file_path), ".ogg") do
      :ok
    else
      {:error, "Audio file must have .ogg extension. WhatsApp voice messages require OGG Opus format."}
    end
  end

  defp validate_required(nil, param), do: {:error, "#{param} parameter is required"}
  defp validate_required("", param), do: {:error, "#{param} parameter is required"}
  defp validate_required(value, _param), do: {:ok, value}

  defp validate_message_ids(nil), do: {:error, "message_ids parameter is required"}
  defp validate_message_ids([]), do: {:error, "message_ids cannot be empty"}
  defp validate_message_ids(ids) when is_list(ids), do: {:ok, ids}
  defp validate_message_ids(_), do: {:error, "message_ids must be a list"}

  defp validate_latitude(nil), do: {:error, "latitude parameter is required"}

  defp validate_latitude(lat) when is_number(lat) and lat >= -90 and lat <= 90 do
    {:ok, lat}
  end

  defp validate_latitude(lat) when is_number(lat) do
    {:error, "latitude must be between -90 and 90"}
  end

  defp validate_latitude(_), do: {:error, "latitude must be a number"}

  defp validate_longitude(nil), do: {:error, "longitude parameter is required"}

  defp validate_longitude(lon) when is_number(lon) and lon >= -180 and lon <= 180 do
    {:ok, lon}
  end

  defp validate_longitude(lon) when is_number(lon) do
    {:error, "longitude must be between -180 and 180"}
  end

  defp validate_longitude(_), do: {:error, "longitude must be a number"}

  defp validate_disappearing_timer(nil), do: {:error, "timer parameter is required"}
  defp validate_disappearing_timer(""), do: {:error, "timer parameter is required"}

  defp validate_disappearing_timer(timer) when timer in @valid_disappearing_timers do
    {:ok, timer}
  end

  defp validate_disappearing_timer(_timer) do
    {:error, "timer must be one of: off, 24h, 7d, 90d"}
  end

  @max_phones_per_request 50
  defp validate_phones(nil), do: {:error, "phones parameter is required"}
  defp validate_phones([]), do: {:error, "phones array cannot be empty"}

  defp validate_phones(phones) when is_list(phones) and length(phones) > @max_phones_per_request do
    {:error, "maximum #{@max_phones_per_request} phone numbers allowed per request"}
  end

  defp validate_phones(phones) when is_list(phones), do: {:ok, phones}
  defp validate_phones(_), do: {:error, "phones must be an array"}

  @valid_blocklist_actions ~w(block unblock)
  defp validate_blocklist_action(nil), do: {:error, "action parameter is required"}
  defp validate_blocklist_action(""), do: {:error, "action parameter is required"}

  defp validate_blocklist_action(action) when action in @valid_blocklist_actions do
    {:ok, action}
  end

  defp validate_blocklist_action(_action) do
    {:error, "action must be 'block' or 'unblock'"}
  end

  defp validate_poll_options(nil), do: {:error, "options parameter is required"}
  defp validate_poll_options(options) when not is_list(options), do: {:error, "options must be an array"}

  defp validate_poll_options(options) when length(options) < @min_poll_options do
    {:error, "at least #{@min_poll_options} options are required"}
  end

  defp validate_poll_options(options) when length(options) > @max_poll_options do
    {:error, "maximum #{@max_poll_options} options allowed"}
  end

  defp validate_poll_options(options) do
    if Enum.any?(options, &(is_nil(&1) or &1 == "")) do
      {:error, "options cannot contain empty strings"}
    else
      {:ok, options}
    end
  end

  defp validate_group_jid(jid) do
    if String.ends_with?(jid, "@g.us") do
      :ok
    else
      {:error, "JID must be a group JID (ending with @g.us)"}
    end
  end

  defp validate_at_least_one_setting(nil, nil) do
    {:error, "At least one of 'locked' or 'announce' must be specified"}
  end

  defp validate_at_least_one_setting(_locked, _announce), do: :ok

  defp maybe_add_setting(opts, _key, nil), do: opts
  defp maybe_add_setting(opts, key, value) when is_boolean(value), do: Keyword.put(opts, key, value)
  defp maybe_add_setting(opts, _key, _value), do: opts

  defp validate_participants(nil), do: {:error, "participants parameter is required"}
  defp validate_participants([]), do: {:error, "participants array cannot be empty"}
  defp validate_participants(participants) when is_list(participants), do: {:ok, participants}
  defp validate_participants(_), do: {:error, "participants must be an array"}

  @valid_participant_actions ~w(add remove promote demote)
  defp validate_participant_action(nil), do: {:error, "action parameter is required"}
  defp validate_participant_action(""), do: {:error, "action parameter is required"}

  defp validate_participant_action(action) when action in @valid_participant_actions do
    {:ok, action}
  end

  defp validate_participant_action(_action) do
    {:error, "action must be one of: add, remove, promote, demote"}
  end

  @valid_privacy_settings ~w(groupadd last status profile readreceipts online calladd)
  defp validate_privacy_setting(nil), do: {:error, "setting parameter is required"}
  defp validate_privacy_setting(""), do: {:error, "setting parameter is required"}

  defp validate_privacy_setting(setting) when setting in @valid_privacy_settings do
    {:ok, setting}
  end

  defp validate_privacy_setting(_setting) do
    {:error, "setting must be one of: groupadd, last, status, profile, readreceipts, online, calladd"}
  end

  @valid_privacy_values ~w(all contacts contact_blacklist match_last_seen known none)
  defp validate_privacy_value(nil), do: {:error, "value parameter is required"}
  defp validate_privacy_value(""), do: {:error, "value parameter is required"}

  defp validate_privacy_value(value) when value in @valid_privacy_values do
    {:ok, value}
  end

  defp validate_privacy_value(_value) do
    {:error, "value must be one of: all, contacts, contact_blacklist, match_last_seen, known, none"}
  end

  defp validate_newsletter_jid(jid) do
    if String.ends_with?(jid, "@newsletter") do
      :ok
    else
      {:error, "JID must be a newsletter JID (ending with @newsletter)"}
    end
  end

  defp maybe_add_opt(opts, _key, nil), do: opts
  defp maybe_add_opt(opts, key, value), do: Keyword.put(opts, key, value)

  # Database error formatting - converts raw atoms/tuples to user-friendly strings
  defp format_db_error({:chat_not_found, name}), do: "Chat not found: #{name}"
  defp format_db_error(:chat_id_or_name_required), do: "Either chat_id or chat_name parameter is required"
  defp format_db_error(:query_required), do: "query parameter is required"
  defp format_db_error(:message_id_required), do: "message_id parameter is required"
  defp format_db_error(:jid_required), do: "jid parameter is required"
  defp format_db_error(:phone_required), do: "phone parameter is required"
  defp format_db_error(:contact_jid_required), do: "contact_jid parameter is required"
  defp format_db_error(:not_found), do: "Not found"
  defp format_db_error(reason) when is_binary(reason), do: reason
  defp format_db_error(reason), do: inspect(reason)

  # LID resolution and linking helpers

  # Enriches chats with linked_jid field and proactively resolves unresolved @lid contacts
  defp enrich_chats_with_linked_jids(chats, opts) do
    db_opts = Formatters.maybe_add([], :db_path, opts[:db_path])

    # First, try to resolve any unresolved @lid chats (limit to avoid slowdown)
    resolve_unresolved_lid_contacts(chats, db_opts, opts)

    # Then enrich all chats with linked_jid if available
    Enum.map(chats, fn chat ->
      case Database.get_linked_jid(Keyword.put(db_opts, :jid, chat.jid)) do
        {:ok, nil} -> chat
        {:ok, linked_jid} -> Map.put(chat, :linked_jid, linked_jid)
        {:error, _} -> chat
      end
    end)
  end

  # Proactively resolve @lid JIDs that don't have a cached phone number
  # This populates the contacts cache for future lookups
  defp resolve_unresolved_lid_contacts(chats, db_opts, bridge_opts) do
    # Find @lid chats that don't have a cached phone yet (single filter pass)
    unresolved_lids =
      chats
      |> Enum.filter(fn chat ->
        String.ends_with?(chat.jid, "@lid") and
          not has_cached_phone?(chat.jid, db_opts)
      end)
      |> Enum.take(@max_lid_resolution_per_request)

    # Try to resolve each unresolved LID via the bridge (fire and forget - don't block on failures)
    Enum.each(unresolved_lids, fn chat ->
      # Silently try to resolve - result is cached by the bridge
      Bridge.resolve_lid(chat.jid, bridge_opts)
    end)
  end

  # Check if a JID has a cached phone number
  defp has_cached_phone?(jid, db_opts) do
    case Database.get_cached_contact(Keyword.put(db_opts, :jid, jid)) do
      {:ok, %{phone: phone}} when is_binary(phone) and phone != "" -> true
      _ -> false
    end
  end
end
