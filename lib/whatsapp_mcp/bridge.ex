defmodule WhatsappMcp.Bridge do
  @moduledoc """
  HTTP client for communicating with the Go WhatsApp bridge.

  The bridge runs on localhost:8080 and provides endpoints for:
  - Sending messages and files
  - Downloading media from messages

  ## Error Conventions

  Functions return `{:ok, result}` or `{:error, reason}` tuples where:

  - **Atoms** are used for programmatic/transport errors:
    - `:bridge_not_running` - Connection refused or bridge unavailable
    - `:timeout` - Request timed out
    - `:file_not_found` - Local file doesn't exist

  - **Strings** are used for errors from the Go bridge API, preserving the
    original error message for user display.
  """

  require Logger

  @default_base_url "http://localhost:8080/api"

  # Timeout for HTTP requests to Go bridge. 30s allows for slow media operations
  # like uploading large files or downloading media from WhatsApp servers.
  @request_timeout_ms 30_000

  @typedoc "Result of send operations: success message or error reason"
  @type send_result :: {:ok, String.t()} | {:error, atom() | String.t()}

  @typedoc "Result of download operations: file metadata or error reason"
  @type download_result ::
          {:ok, %{path: String.t(), filename: String.t(), media_type: String.t()}} | {:error, atom() | String.t()}

  @typedoc "Result of health check: status info or error"
  @type health_result :: {:ok, map()} | {:error, :bridge_not_running}

  @typedoc "Result of LID resolution: contact info or error reason"
  @type resolve_result ::
          {:ok, %{phone: String.t(), name: String.t() | nil}} | {:error, atom() | String.t()}

  @doc """
  Check if the Go bridge is running and get connection status.

  Returns connection status, phone number, and account name when connected.

  ## Options
  - `:base_url` - Override the default base URL
  - `:plug` - Plug for testing with Req.Test

  ## Examples

      iex> WhatsappMcp.Bridge.health_check()
      {:ok, %{"connected" => true, "phone" => "14155551234", "name" => "Alice"}}

      iex> WhatsappMcp.Bridge.health_check()
      {:ok, %{"connected" => false}}

      iex> WhatsappMcp.Bridge.health_check()
      {:error, :bridge_not_running}
  """
  @spec health_check(keyword()) :: health_result()
  def health_check(opts \\ []) do
    opts
    |> build_request()
    |> Req.get(url: "/health")
    |> handle_health_response()
  end

  @doc """
  Send a text message to a recipient.

  ## Parameters
  - `recipient` - Phone number (e.g., "12025551234") or JID (e.g., "12025551234@s.whatsapp.net")
  - `message` - The text message to send

  ## Options
  - `:base_url` - Override the default base URL
  - `:plug` - Plug for testing with Req.Test

  ## Examples

      iex> WhatsappMcp.Bridge.send_message("12025551234", "Hello!")
      {:ok, "Message sent to 12025551234"}

      iex> WhatsappMcp.Bridge.send_message("invalid", "Hi")
      {:error, "Error parsing JID: ..."}
  """
  @spec send_message(String.t(), String.t(), keyword()) :: send_result()
  def send_message(recipient, message, opts \\ []) do
    opts
    |> build_request()
    |> Req.post(url: "/send", json: %{recipient: recipient, message: message})
    |> handle_send_response()
  end

  @doc """
  Send a file (image, video, document) to a recipient.

  ## Parameters
  - `recipient` - Phone number or JID
  - `file_path` - Absolute path to the file to send
  - `caption` - Optional caption for the file (default: "")

  ## Options
  - `:base_url` - Override the default base URL
  - `:plug` - Plug for testing with Req.Test

  ## Examples

      iex> WhatsappMcp.Bridge.send_file("12025551234", "/path/to/image.jpg")
      {:ok, "Message sent to 12025551234"}

      iex> WhatsappMcp.Bridge.send_file("12025551234", "/path/to/doc.pdf", "Check this out")
      {:ok, "Message sent to 12025551234"}
  """
  @spec send_file(String.t(), String.t(), String.t(), keyword()) :: send_result()
  def send_file(recipient, file_path, caption \\ "", opts \\ []) do
    with :ok <- validate_file_path(file_path),
         true <- File.exists?(file_path) do
      opts
      |> build_request()
      |> Req.post(
        url: "/send",
        json: %{recipient: recipient, message: caption, media_path: file_path}
      )
      |> handle_send_response()
    else
      {:error, reason} -> {:error, reason}
      false -> {:error, :file_not_found}
    end
  end

  @doc """
  Send an audio file as a voice message (PTT - Push To Talk).

  The audio file must be in OGG Opus format. The Go bridge will analyze the file
  to extract duration and generate a waveform for the WhatsApp voice message UI.

  ## Implementation Note

  This function uses the same `/api/send` endpoint as `send_file/4`. The Go bridge
  auto-detects OGG Opus files by analyzing the file format and handles them as
  voice messages (PTT). No special endpoint or flag is needed.

  ## Parameters
  - `recipient` - Phone number or JID
  - `file_path` - Absolute path to the OGG Opus audio file

  ## Options
  - `:base_url` - Override the default base URL
  - `:plug` - Plug for testing with Req.Test

  ## Examples

      iex> WhatsappMcp.Bridge.send_audio("12025551234", "/path/to/voice.ogg")
      {:ok, "Message sent to 12025551234"}

      iex> WhatsappMcp.Bridge.send_audio("12025551234", "/path/to/invalid.ogg")
      {:error, "Failed to analyze Ogg Opus file: ..."}
  """
  @spec send_audio(String.t(), String.t(), keyword()) :: send_result()
  def send_audio(recipient, file_path, opts \\ []) do
    with :ok <- validate_file_path(file_path),
         true <- File.exists?(file_path) do
      opts
      |> build_request()
      |> Req.post(
        url: "/send",
        json: %{recipient: recipient, message: "", media_path: file_path}
      )
      |> handle_send_response()
    else
      {:error, reason} -> {:error, reason}
      false -> {:error, :file_not_found}
    end
  end

  @doc """
  Download media from a message.

  ## Parameters
  - `message_id` - The message ID containing media
  - `chat_jid` - The chat JID where the message exists

  ## Options
  - `:base_url` - Override the default base URL
  - `:plug` - Plug for testing with Req.Test

  ## Examples

      iex> WhatsappMcp.Bridge.download_media("ABC123", "12025551234@s.whatsapp.net")
      {:ok, %{path: "/absolute/path/to/file.jpg", filename: "image.jpg", media_type: "image"}}

      iex> WhatsappMcp.Bridge.download_media("ABC123", "12025551234@s.whatsapp.net")
      {:error, "not a media message"}
  """
  @spec download_media(String.t(), String.t(), keyword()) :: download_result()
  def download_media(message_id, chat_jid, opts \\ []) do
    opts
    |> build_request()
    |> Req.post(url: "/download", json: %{message_id: message_id, chat_jid: chat_jid})
    |> handle_download_response()
  end

  @doc """
  Resolve a LID (Linked ID) JID to a phone number.

  WhatsApp's newer Linked ID format stores contacts as numeric IDs instead of
  phone numbers. This function calls the WhatsApp API to resolve the LID to
  the actual phone number.

  Results are cached in the bridge's contacts table to avoid repeated API calls.

  ## Parameters
  - `lid` - The LID JID to resolve (e.g., "144555781402794@lid")

  ## Options
  - `:base_url` - Override the default base URL
  - `:plug` - Plug for testing with Req.Test

  ## Examples

      iex> WhatsappMcp.Bridge.resolve_lid("144555781402794@lid")
      {:ok, %{phone: "14155552345", name: "John Doe"}}

      iex> WhatsappMcp.Bridge.resolve_lid("invalid@lid")
      {:error, "No user info found for this LID"}
  """
  @spec resolve_lid(String.t(), keyword()) :: resolve_result()
  def resolve_lid(lid, opts \\ []) do
    opts
    |> build_request()
    |> Req.post(url: "/resolve-lid", json: %{lid: lid})
    |> handle_resolve_response()
  end

  @doc """
  Send a typing indicator to a recipient.

  Shows "typing..." status in the recipient's chat. Send `composing: true` to
  start the indicator and `composing: false` to stop it.

  ## Parameters
  - `recipient` - Phone number or JID
  - `composing` - true to start typing indicator, false to stop

  ## Options
  - `:base_url` - Override the default base URL
  - `:plug` - Plug for testing with Req.Test

  ## Examples

      iex> WhatsappMcp.Bridge.send_typing("12025551234", true)
      {:ok, "Typing indicator started for 12025551234"}

      iex> WhatsappMcp.Bridge.send_typing("12025551234", false)
      {:ok, "Typing indicator stopped for 12025551234"}
  """
  @spec send_typing(String.t(), boolean(), keyword()) :: send_result()
  def send_typing(recipient, composing, opts \\ []) do
    opts
    |> build_request()
    |> Req.post(url: "/typing", json: %{recipient: recipient, composing: composing})
    |> handle_send_response()
  end

  @doc """
  Mark messages as read in a chat.

  Sends read receipts (blue ticks) for the specified messages.

  ## Parameters
  - `chat_jid` - The chat JID where the messages exist
  - `message_ids` - List of message IDs to mark as read

  ## Options
  - `:base_url` - Override the default base URL
  - `:plug` - Plug for testing with Req.Test

  ## Examples

      iex> WhatsappMcp.Bridge.mark_read("12025551234@s.whatsapp.net", ["ABC123", "DEF456"])
      {:ok, "Marked 2 message(s) as read in 12025551234@s.whatsapp.net"}
  """
  @spec mark_read(String.t(), [String.t()], keyword()) :: send_result()
  def mark_read(chat_jid, message_ids, opts \\ []) do
    opts
    |> build_request()
    |> Req.post(url: "/mark-read", json: %{chat_jid: chat_jid, message_ids: message_ids})
    |> handle_send_response()
  end

  @doc """
  Send a reaction emoji to a message.

  Adds an emoji reaction to a specific message. Send an empty string for emoji
  to remove an existing reaction.

  ## Parameters
  - `chat_jid` - The chat JID where the message exists
  - `message_id` - The message ID to react to
  - `sender` - The sender JID of the original message
  - `emoji` - The emoji to react with (empty string to remove reaction)

  ## Options
  - `:base_url` - Override the default base URL
  - `:plug` - Plug for testing with Req.Test

  ## Examples

      iex> WhatsappMcp.Bridge.send_reaction("12025551234@s.whatsapp.net", "ABC123", "12025551234@s.whatsapp.net", "👍")
      {:ok, "Reaction added for message ABC123"}

      iex> WhatsappMcp.Bridge.send_reaction("12025551234@s.whatsapp.net", "ABC123", "12025551234@s.whatsapp.net", "")
      {:ok, "Reaction removed for message ABC123"}
  """
  @spec send_reaction(String.t(), String.t(), String.t(), String.t(), keyword()) :: send_result()
  def send_reaction(chat_jid, message_id, sender, emoji, opts \\ []) do
    opts
    |> build_request()
    |> Req.post(
      url: "/reaction",
      json: %{chat_jid: chat_jid, message_id: message_id, sender: sender, emoji: emoji}
    )
    |> handle_send_response()
  end

  @doc """
  Delete a message ("delete for everyone").

  Revokes a message so it's deleted for all participants. Only works for your own
  messages and within WhatsApp's time limit (usually 1 hour 8 minutes).

  ## Parameters
  - `chat_jid` - The chat JID where the message exists
  - `message_id` - The message ID to delete
  - `sender` - The sender JID of the message (must be your own JID)

  ## Options
  - `:base_url` - Override the default base URL
  - `:plug` - Plug for testing with Req.Test

  ## Examples

      iex> WhatsappMcp.Bridge.delete_message("12025551234@s.whatsapp.net", "ABC123", "14155551234@s.whatsapp.net")
      {:ok, "Message ABC123 deleted from 12025551234@s.whatsapp.net"}
  """
  @spec delete_message(String.t(), String.t(), String.t(), keyword()) :: send_result()
  def delete_message(chat_jid, message_id, sender, opts \\ []) do
    opts
    |> build_request()
    |> Req.post(
      url: "/delete",
      json: %{chat_jid: chat_jid, message_id: message_id, sender: sender}
    )
    |> handle_send_response()
  end

  @doc """
  Reply to a specific message (quote-reply).

  Sends a message as a reply to another message, showing the quoted original
  message in WhatsApp's UI.

  ## Parameters
  - `recipient` - Phone number or JID to send the reply to
  - `message` - The reply message text
  - `quoted_message_id` - The message ID being replied to
  - `quoted_chat_jid` - The chat JID where the quoted message exists
  - `quoted_sender` - The JID of the person who sent the quoted message

  ## Options
  - `:base_url` - Override the default base URL
  - `:plug` - Plug for testing with Req.Test

  ## Examples

      iex> WhatsappMcp.Bridge.reply_to_message("12025551234", "Thanks!", "ABC123", "12025551234@s.whatsapp.net", "14155551234@s.whatsapp.net")
      {:ok, "Reply sent to 12025551234"}
  """
  @spec reply_to_message(String.t(), String.t(), String.t(), String.t(), String.t(), keyword()) ::
          send_result()
  def reply_to_message(recipient, message, quoted_message_id, quoted_chat_jid, quoted_sender, opts \\ []) do
    opts
    |> build_request()
    |> Req.post(
      url: "/reply",
      json: %{
        recipient: recipient,
        message: message,
        quoted_message_id: quoted_message_id,
        quoted_chat_jid: quoted_chat_jid,
        quoted_sender: quoted_sender
      }
    )
    |> handle_send_response()
  end

  @doc """
  Edit a previously sent message.

  Replaces the content of a message you sent with new text. Only works for your own
  messages and within WhatsApp's time limit (approximately 15 minutes).

  ## Parameters
  - `chat_jid` - The chat JID where the message exists
  - `message_id` - The message ID to edit
  - `new_content` - The new text content for the message

  ## Options
  - `:base_url` - Override the default base URL
  - `:plug` - Plug for testing with Req.Test

  ## Examples

      iex> WhatsappMcp.Bridge.edit_message("12025551234@s.whatsapp.net", "ABC123", "Fixed typo!")
      {:ok, "Message ABC123 edited in 12025551234@s.whatsapp.net"}

      iex> WhatsappMcp.Bridge.edit_message("12025551234@s.whatsapp.net", "OLD123", "Too late")
      {:error, "Failed to edit message: message too old"}
  """
  @spec edit_message(String.t(), String.t(), String.t(), keyword()) :: send_result()
  def edit_message(chat_jid, message_id, new_content, opts \\ []) do
    opts
    |> build_request()
    |> Req.post(
      url: "/edit",
      json: %{chat_jid: chat_jid, message_id: message_id, new_content: new_content}
    )
    |> handle_send_response()
  end

  @doc """
  Send a location pin to a recipient.

  Sends a location message with latitude/longitude coordinates. Optionally include
  a place name and address for display.

  ## Parameters
  - `recipient` - Phone number or JID
  - `latitude` - Latitude in degrees (-90 to 90)
  - `longitude` - Longitude in degrees (-180 to 180)

  ## Options
  - `:name` - Optional place name (e.g., "Eiffel Tower")
  - `:address` - Optional address (e.g., "Champ de Mars, Paris")
  - `:base_url` - Override the default base URL
  - `:plug` - Plug for testing with Req.Test

  ## Examples

      iex> WhatsappMcp.Bridge.send_location("12025551234", 48.8584, 2.2945)
      {:ok, "Location sent to 12025551234"}

      iex> WhatsappMcp.Bridge.send_location("12025551234", 48.8584, 2.2945, name: "Eiffel Tower")
      {:ok, "Location sent to 12025551234"}
  """
  @spec send_location(String.t(), float(), float(), keyword()) :: send_result()
  def send_location(recipient, latitude, longitude, opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, "")
    {address, opts} = Keyword.pop(opts, :address, "")

    json_body =
      %{recipient: recipient, latitude: latitude, longitude: longitude}
      |> maybe_add_field(:name, name)
      |> maybe_add_field(:address, address)

    opts
    |> build_request()
    |> Req.post(url: "/location", json: json_body)
    |> handle_send_response()
  end

  @doc """
  Set your online presence status.

  Controls whether you appear as online (available) or offline (unavailable) to
  your contacts.

  ## Parameters
  - `available` - true to appear online, false to appear offline

  ## Options
  - `:base_url` - Override the default base URL
  - `:plug` - Plug for testing with Req.Test

  ## Examples

      iex> WhatsappMcp.Bridge.set_presence(true)
      {:ok, "Presence set to available"}

      iex> WhatsappMcp.Bridge.set_presence(false)
      {:ok, "Presence set to unavailable"}
  """
  @spec set_presence(boolean(), keyword()) :: send_result()
  def set_presence(available, opts \\ []) do
    opts
    |> build_request()
    |> Req.post(url: "/presence", json: %{available: available})
    |> handle_send_response()
  end

  @doc """
  Subscribe to presence updates for a contact.

  After subscribing, you'll receive notifications when the contact comes online
  or goes offline. Note: This is a one-time subscription request; the actual
  presence updates are delivered via events in the Go bridge.

  ## Parameters
  - `jid` - The contact's JID (e.g., "12025551234@s.whatsapp.net")

  ## Options
  - `:base_url` - Override the default base URL
  - `:plug` - Plug for testing with Req.Test

  ## Examples

      iex> WhatsappMcp.Bridge.subscribe_presence("12025551234@s.whatsapp.net")
      {:ok, "Subscribed to presence updates for 12025551234@s.whatsapp.net"}
  """
  @spec subscribe_presence(String.t(), keyword()) :: send_result()
  def subscribe_presence(jid, opts \\ []) do
    opts
    |> build_request()
    |> Req.post(url: "/subscribe-presence", json: %{jid: jid})
    |> handle_send_response()
  end

  @doc """
  Set the disappearing messages timer for a chat.

  Enables or disables disappearing messages in a chat. Messages sent after
  enabling this feature will automatically delete after the specified duration.

  ## Parameters
  - `chat_jid` - The chat JID (individual or group)
  - `timer` - Timer duration: "off", "24h", "7d", or "90d"

  ## Options
  - `:base_url` - Override the default base URL
  - `:plug` - Plug for testing with Req.Test

  ## Examples

      iex> WhatsappMcp.Bridge.set_disappearing_timer("12025551234@s.whatsapp.net", "24h")
      {:ok, "Disappearing messages set to 24h for 12025551234@s.whatsapp.net"}

      iex> WhatsappMcp.Bridge.set_disappearing_timer("12025551234@s.whatsapp.net", "off")
      {:ok, "Disappearing messages set to off for 12025551234@s.whatsapp.net"}
  """
  @spec set_disappearing_timer(String.t(), String.t(), keyword()) :: send_result()
  def set_disappearing_timer(chat_jid, timer, opts \\ []) do
    opts
    |> build_request()
    |> Req.post(url: "/disappearing", json: %{chat_jid: chat_jid, timer: timer})
    |> handle_send_response()
  end

  @typedoc "Result of check_whatsapp_registration operation: list of results or error"
  @type whatsapp_registration_result ::
          {:ok, [%{phone: String.t(), is_on_whatsapp: boolean(), jid: String.t() | nil}]}
          | {:error, atom() | String.t()}

  @doc """
  Check if phone numbers are registered on WhatsApp.

  Verifies whether given phone numbers have WhatsApp accounts. Useful for
  validating numbers before sending messages. Supports batch checking up to
  50 numbers at a time.

  ## Parameters
  - `phones` - List of phone numbers to check (e.g., ["12025551234", "44123456789"])

  ## Options
  - `:base_url` - Override the default base URL
  - `:plug` - Plug for testing with Req.Test

  ## Examples

      iex> WhatsappMcp.Bridge.check_whatsapp_registration(["12025551234", "44123456789"])
      {:ok, [
        %{phone: "12025551234", is_on_whatsapp: true, jid: "12025551234@s.whatsapp.net"},
        %{phone: "44123456789", is_on_whatsapp: false, jid: nil}
      ]}

      iex> WhatsappMcp.Bridge.check_whatsapp_registration([])
      {:error, "phones array is required and cannot be empty"}
  """
  @spec check_whatsapp_registration([String.t()], keyword()) :: whatsapp_registration_result()
  def check_whatsapp_registration(phones, opts \\ []) do
    opts
    |> build_request()
    |> Req.post(url: "/is-on-whatsapp", json: %{phones: phones})
    |> handle_is_on_whatsapp_response()
  end

  @typedoc "Result of profile picture operation: URL info or error"
  @type profile_picture_result ::
          {:ok, %{url: String.t(), id: String.t()}}
          | {:error, atom() | String.t()}

  @doc """
  Get the profile picture URL for a contact or group.

  Returns the URL and ID of the profile picture. The URL can be used to download
  the image. Note that profile pictures may not be available if the contact has
  privacy settings enabled.

  ## Parameters
  - `jid` - The contact or group JID (e.g., "12025551234@s.whatsapp.net")

  ## Options
  - `:base_url` - Override the default base URL
  - `:plug` - Plug for testing with Req.Test

  ## Examples

      iex> WhatsappMcp.Bridge.get_profile_picture("12025551234@s.whatsapp.net")
      {:ok, %{url: "https://pps.whatsapp.net/...", id: "1234567890"}}

      iex> WhatsappMcp.Bridge.get_profile_picture("private@s.whatsapp.net")
      {:error, "No profile picture set for this contact"}
  """
  @spec get_profile_picture(String.t(), keyword()) :: profile_picture_result()
  def get_profile_picture(jid, opts \\ []) do
    opts
    |> build_request()
    |> Req.post(url: "/profile-picture", json: %{jid: jid})
    |> handle_profile_picture_response()
  end

  @typedoc "Result of blocklist operation: list of blocked JIDs or error"
  @type blocklist_result :: {:ok, [String.t()]} | {:error, atom() | String.t()}

  @doc """
  Get the list of blocked contacts.

  Returns all JIDs that are currently blocked.

  ## Options
  - `:base_url` - Override the default base URL
  - `:plug` - Plug for testing with Req.Test

  ## Examples

      iex> WhatsappMcp.Bridge.get_blocklist()
      {:ok, ["12025551234@s.whatsapp.net", "44123456789@s.whatsapp.net"]}

      iex> WhatsappMcp.Bridge.get_blocklist()
      {:ok, []}
  """
  @spec get_blocklist(keyword()) :: blocklist_result()
  def get_blocklist(opts \\ []) do
    opts
    |> build_request()
    |> Req.get(url: "/blocklist")
    |> handle_blocklist_response()
  end

  @doc """
  Block or unblock a contact.

  Adds or removes a contact from your blocklist.

  ## Parameters
  - `jid` - The contact JID to block/unblock
  - `action` - Either "block" or "unblock"

  ## Options
  - `:base_url` - Override the default base URL
  - `:plug` - Plug for testing with Req.Test

  ## Examples

      iex> WhatsappMcp.Bridge.update_blocklist("12025551234@s.whatsapp.net", "block")
      {:ok, "Contact 12025551234@s.whatsapp.net blocked"}

      iex> WhatsappMcp.Bridge.update_blocklist("12025551234@s.whatsapp.net", "unblock")
      {:ok, "Contact 12025551234@s.whatsapp.net unblocked"}
  """
  @spec update_blocklist(String.t(), String.t(), keyword()) :: send_result()
  def update_blocklist(jid, action, opts \\ []) do
    opts
    |> build_request()
    |> Req.post(url: "/block", json: %{jid: jid, action: action})
    |> handle_send_response()
  end

  @typedoc "Result of list_groups operation: list of group info or error"
  @type list_groups_result ::
          {:ok, [map()]}
          | {:error, atom() | String.t()}

  @doc """
  List all joined WhatsApp groups.

  Returns basic information about each group including JID, name, topic,
  participant count, and settings.

  ## Options
  - `:base_url` - Override the default base URL
  - `:plug` - Plug for testing with Req.Test

  ## Examples

      iex> WhatsappMcp.Bridge.list_groups()
      {:ok, [
        %{
          "jid" => "120363123456789012@g.us",
          "name" => "Family Group",
          "topic" => "Stay connected!",
          "participant_count" => 5,
          "is_announce" => false,
          "is_locked" => false
        }
      ]}

      iex> WhatsappMcp.Bridge.list_groups()
      {:ok, []}
  """
  @spec list_groups(keyword()) :: list_groups_result()
  def list_groups(opts \\ []) do
    opts
    |> build_request()
    |> Req.get(url: "/groups")
    |> handle_list_groups_response()
  end

  @typedoc "Result of get_group_info operation: detailed group info or error"
  @type group_info_result ::
          {:ok, map()}
          | {:error, atom() | String.t()}

  @doc """
  Get detailed information about a specific group.

  Returns full group details including all participants and their roles.

  ## Parameters
  - `jid` - The group JID (must end with @g.us)

  ## Options
  - `:base_url` - Override the default base URL
  - `:plug` - Plug for testing with Req.Test

  ## Examples

      iex> WhatsappMcp.Bridge.get_group_info("120363123456789012@g.us")
      {:ok, %{
        "jid" => "120363123456789012@g.us",
        "name" => "Family Group",
        "topic" => "Stay connected!",
        "participant_count" => 5,
        "participants" => [
          %{"jid" => "12025551234@s.whatsapp.net", "is_admin" => true, "is_super_admin" => false},
          %{"jid" => "12025555678@s.whatsapp.net", "is_admin" => false, "is_super_admin" => false}
        ],
        "is_announce" => false,
        "is_locked" => false
      }}

      iex> WhatsappMcp.Bridge.get_group_info("12025551234@s.whatsapp.net")
      {:error, "JID is not a group (must end with @g.us)"}
  """
  @spec get_group_info(String.t(), keyword()) :: group_info_result()
  def get_group_info(jid, opts \\ []) do
    opts
    |> build_request()
    |> Req.post(url: "/group-info", json: %{jid: jid})
    |> handle_group_info_response()
  end

  @typedoc "Result of get_group_invite_link operation: invite link or error"
  @type group_invite_link_result ::
          {:ok, String.t()}
          | {:error, atom() | String.t()}

  @doc """
  Get the invite link for a group.

  Returns the current invite link or generates a new one if `reset: true` is passed.
  Only group admins can get/reset invite links.

  ## Parameters
  - `jid` - The group JID (must end with @g.us)

  ## Options
  - `:reset` - If true, invalidate the current invite link and generate a new one
  - `:base_url` - Override the default base URL
  - `:plug` - Plug for testing with Req.Test

  ## Examples

      iex> WhatsappMcp.Bridge.get_group_invite_link("120363123456789012@g.us")
      {:ok, "https://chat.whatsapp.com/ABC123xyz"}

      iex> WhatsappMcp.Bridge.get_group_invite_link("120363123456789012@g.us", reset: true)
      {:ok, "https://chat.whatsapp.com/NEW456abc"}

      iex> WhatsappMcp.Bridge.get_group_invite_link("120363123456789012@g.us")
      {:error, "not a group admin"}
  """
  @spec get_group_invite_link(String.t(), keyword()) :: group_invite_link_result()
  def get_group_invite_link(jid, opts \\ []) do
    {reset, opts} = Keyword.pop(opts, :reset, false)

    opts
    |> build_request()
    |> Req.post(url: "/group-invite-link", json: %{jid: jid, reset: reset})
    |> handle_group_invite_link_response()
  end

  @typedoc "Result of join_group operation: group JID or error"
  @type join_group_result ::
          {:ok, %{group_jid: String.t(), message: String.t()}}
          | {:error, atom() | String.t()}

  @doc """
  Join a group using an invite link.

  Accepts either a full invite link (https://chat.whatsapp.com/CODE) or just the
  invite code.

  ## Parameters
  - `invite_link` - The invite link or code

  ## Options
  - `:base_url` - Override the default base URL
  - `:plug` - Plug for testing with Req.Test

  ## Examples

      iex> WhatsappMcp.Bridge.join_group("https://chat.whatsapp.com/ABC123xyz")
      {:ok, %{group_jid: "120363123456789012@g.us", message: "Successfully joined group..."}}

      iex> WhatsappMcp.Bridge.join_group("ABC123xyz")
      {:ok, %{group_jid: "120363123456789012@g.us", message: "Successfully joined group..."}}

      iex> WhatsappMcp.Bridge.join_group("invalid")
      {:error, "Failed to join group: invite link expired"}
  """
  @spec join_group(String.t(), keyword()) :: join_group_result()
  def join_group(invite_link, opts \\ []) do
    opts
    |> build_request()
    |> Req.post(url: "/join-group", json: %{invite_link: invite_link})
    |> handle_join_group_response()
  end

  @typedoc "Result of create_group operation: group info or error"
  @type create_group_result ::
          {:ok, map()}
          | {:error, atom() | String.t()}

  @doc """
  Create a new WhatsApp group.

  Creates a new group with the specified name and initial participants.
  Group names are limited to 25 characters.

  ## Parameters
  - `name` - The group name (max 25 characters)
  - `participants` - List of JIDs to add as initial members

  ## Options
  - `:base_url` - Override the default base URL
  - `:plug` - Plug for testing with Req.Test

  ## Examples

      iex> WhatsappMcp.Bridge.create_group("Family Chat", ["12025551234@s.whatsapp.net"])
      {:ok, %{
        "jid" => "120363123456789012@g.us",
        "name" => "Family Chat",
        "participant_count" => 2
      }}

      iex> WhatsappMcp.Bridge.create_group("A name that is way too long for a group", [])
      {:error, "Group name must be 25 characters or less"}
  """
  @spec create_group(String.t(), [String.t()], keyword()) :: create_group_result()
  def create_group(name, participants, opts \\ []) do
    opts
    |> build_request()
    |> Req.post(url: "/create-group", json: %{name: name, participants: participants})
    |> handle_create_group_response()
  end

  @typedoc "Result of leave_group operation: success message or error"
  @type leave_group_result ::
          {:ok, String.t()}
          | {:error, atom() | String.t()}

  @doc """
  Leave a WhatsApp group.

  ## Parameters
  - `jid` - The group JID (must end with @g.us)

  ## Options
  - `:base_url` - Override the default base URL
  - `:plug` - Plug for testing with Req.Test

  ## Examples

      iex> WhatsappMcp.Bridge.leave_group("120363123456789012@g.us")
      {:ok, "Successfully left group 120363123456789012@g.us"}

      iex> WhatsappMcp.Bridge.leave_group("12025551234@s.whatsapp.net")
      {:error, "JID must be a group (must end with @g.us)"}
  """
  @spec leave_group(String.t(), keyword()) :: leave_group_result()
  def leave_group(jid, opts \\ []) do
    opts
    |> build_request()
    |> Req.post(url: "/leave-group", json: %{jid: jid})
    |> handle_leave_group_response()
  end

  @doc """
  Create and send a poll to a recipient.

  Creates a WhatsApp poll with a question and multiple options. Supports both
  single-choice (1 selection) and multi-choice (2+ selections) polls.

  ## Parameters
  - `recipient` - Phone number or JID
  - `question` - The poll question
  - `options` - List of poll options (2-12 options)
  - `max_selections` - Maximum selections allowed (1 for single-choice, 2+ for multi-choice)

  ## Options
  - `:base_url` - Override the default base URL
  - `:plug` - Plug for testing with Req.Test

  ## Examples

      iex> WhatsappMcp.Bridge.create_poll("12025551234", "What's for lunch?", ["Pizza", "Sushi", "Salad"], 1)
      {:ok, "Poll sent to 12025551234 (single-choice with 3 options)"}

      iex> WhatsappMcp.Bridge.create_poll("12025551234", "Select toppings", ["Cheese", "Pepperoni", "Mushrooms"], 3)
      {:ok, "Poll sent to 12025551234 (multi-choice (up to 3) with 3 options)"}
  """
  @spec create_poll(String.t(), String.t(), [String.t()], pos_integer(), keyword()) :: send_result()
  def create_poll(recipient, question, options, max_selections, opts \\ []) do
    opts
    |> build_request()
    |> Req.post(
      url: "/poll",
      json: %{
        recipient: recipient,
        question: question,
        options: options,
        max_selections: max_selections
      }
    )
    |> handle_send_response()
  end

  @typedoc "Result of list_contacts operation: list of contacts or error"
  @type list_contacts_result ::
          {:ok, %{contacts: [map()], total: non_neg_integer()}}
          | {:error, atom() | String.t()}

  @doc """
  List all synced WhatsApp contacts from the contacts store.

  Returns contacts from your phone's address book that have been synced to WhatsApp.
  For @lid contacts (newer WhatsApp format), includes redacted phone numbers which
  can help identify unknown contacts.

  ## Options
  - `:limit` - Maximum contacts to return (default: 100)
  - `:offset` - Pagination offset (default: 0)
  - `:query` - Optional filter by name
  - `:base_url` - Override the default base URL
  - `:plug` - Plug for testing with Req.Test

  ## Examples

      iex> WhatsappMcp.Bridge.list_contacts()
      {:ok, %{
        contacts: [
          %{
            "jid" => "12025551234@s.whatsapp.net",
            "full_name" => "John Doe",
            "push_name" => "John",
            "first_name" => "John",
            "business_name" => nil,
            "redacted_phone" => nil
          },
          %{
            "jid" => "78834275733504@lid",
            "full_name" => nil,
            "push_name" => "Esteban",
            "first_name" => nil,
            "business_name" => nil,
            "redacted_phone" => "+33∙∙∙∙∙∙∙∙53"
          }
        ],
        total: 127
      }}

      iex> WhatsappMcp.Bridge.list_contacts(query: "John")
      {:ok, %{contacts: [...], total: 5}}
  """
  @spec list_contacts(keyword()) :: list_contacts_result()
  def list_contacts(opts \\ []) do
    {limit, opts} = Keyword.pop(opts, :limit, 100)
    {offset, opts} = Keyword.pop(opts, :offset, 0)
    {query, opts} = Keyword.pop(opts, :query)

    query_params = [limit: limit, offset: offset]
    query_params = if query, do: [{:query, query} | query_params], else: query_params

    opts
    |> build_request()
    |> Req.get(url: "/contacts", params: query_params)
    |> handle_list_contacts_response()
  end

  @typedoc "Result of update_group_participants operation: success info or error"
  @type update_participants_result ::
          {:ok, %{message: String.t(), participants: [%{jid: String.t(), error_code: integer()}]}}
          | {:error, atom() | String.t()}

  @typedoc "Result of merge_chats operation: success info or error"
  @type merge_chats_result ::
          {:ok, %{message: String.t(), messages_moved: non_neg_integer()}}
          | {:error, atom() | String.t()}

  @doc """
  Merge messages from one chat into another, then delete the source chat.

  This is useful for consolidating duplicate chat threads, especially when the
  same contact appears as both a phone number JID (@s.whatsapp.net) and a LID
  (@lid) due to WhatsApp's privacy features.

  After merging, the LID→phone link is stored in the contacts table for future
  automatic resolution.

  ## Parameters
  - `source_jid` - The chat JID to merge FROM (will be deleted after merge)
  - `target_jid` - The chat JID to merge INTO (will contain all messages)

  ## Options
  - `:base_url` - Override the default base URL
  - `:plug` - Plug for testing with Req.Test

  ## Examples

      iex> WhatsappMcp.Bridge.merge_chats("78834275733504@lid", "14155554567@s.whatsapp.net")
      {:ok, %{message: "Merged 5 messages from 78834275733504@lid into 14155554567@s.whatsapp.net. Source chat deleted.", messages_moved: 5}}

      iex> WhatsappMcp.Bridge.merge_chats("unknown@lid", "14155554567@s.whatsapp.net")
      {:error, "source chat does not exist: unknown@lid"}
  """
  @spec merge_chats(String.t(), String.t(), keyword()) :: merge_chats_result()
  def merge_chats(source_jid, target_jid, opts \\ []) do
    opts
    |> build_request()
    |> Req.post(url: "/merge-chats", json: %{source_jid: source_jid, target_jid: target_jid})
    |> handle_merge_chats_response()
  end

  @doc """
  Update a group's name.

  Group names are limited to 25 characters by WhatsApp.

  ## Parameters
  - `jid` - The group JID (must end with @g.us)
  - `name` - The new group name (max 25 characters)

  ## Options
  - `:base_url` - Override the default base URL
  - `:plug` - Plug for testing with Req.Test

  ## Examples

      iex> WhatsappMcp.Bridge.update_group_name("120363123456789012@g.us", "New Name")
      {:ok, "Group name updated to \\"New Name\\""}

      iex> WhatsappMcp.Bridge.update_group_name("120363123456789012@g.us", "Way too long name for group")
      {:error, "Group name must be 25 characters or less"}
  """
  @spec update_group_name(String.t(), String.t(), keyword()) :: send_result()
  def update_group_name(jid, name, opts \\ []) do
    opts
    |> build_request()
    |> Req.post(url: "/update-group-name", json: %{jid: jid, name: name})
    |> handle_send_response()
  end

  @doc """
  Update a group's description/topic.

  Set an empty string to clear the description.

  ## Parameters
  - `jid` - The group JID (must end with @g.us)
  - `description` - The new group description (empty string to clear)

  ## Options
  - `:base_url` - Override the default base URL
  - `:plug` - Plug for testing with Req.Test

  ## Examples

      iex> WhatsappMcp.Bridge.update_group_description("120363123456789012@g.us", "Welcome to our group!")
      {:ok, "Group description updated"}

      iex> WhatsappMcp.Bridge.update_group_description("120363123456789012@g.us", "")
      {:ok, "Group description cleared"}
  """
  @spec update_group_description(String.t(), String.t(), keyword()) :: send_result()
  def update_group_description(jid, description, opts \\ []) do
    opts
    |> build_request()
    |> Req.post(url: "/update-group-description", json: %{jid: jid, description: description})
    |> handle_send_response()
  end

  @doc """
  Update group settings (locked and/or announce mode).

  - **Locked**: When true, only admins can edit group info (name, description, photo).
  - **Announce**: When true, only admins can send messages (broadcast mode).

  At least one of `:locked` or `:announce` must be specified.

  ## Parameters
  - `jid` - The group JID (must end with @g.us)

  ## Options
  - `:locked` - true to lock group info editing to admins only
  - `:announce` - true to enable announce mode (only admins can send messages)
  - `:base_url` - Override the default base URL
  - `:plug` - Plug for testing with Req.Test

  ## Examples

      iex> WhatsappMcp.Bridge.update_group_settings("120363123456789012@g.us", locked: true)
      {:ok, "Group settings updated: locked (only admins can edit info)"}

      iex> WhatsappMcp.Bridge.update_group_settings("120363123456789012@g.us", announce: true)
      {:ok, "Group settings updated: announce mode enabled (only admins can send)"}

      iex> WhatsappMcp.Bridge.update_group_settings("120363123456789012@g.us", locked: false, announce: true)
      {:ok, "Group settings updated: unlocked (all members can edit info), announce mode enabled (only admins can send)"}
  """
  @spec update_group_settings(String.t(), keyword()) :: send_result()
  def update_group_settings(jid, opts \\ []) do
    {locked, opts} = Keyword.pop(opts, :locked)
    {announce, opts} = Keyword.pop(opts, :announce)

    json_body =
      %{jid: jid}
      |> maybe_add_field(:locked, locked)
      |> maybe_add_field(:announce, announce)

    opts
    |> build_request()
    |> Req.post(url: "/update-group-settings", json: json_body)
    |> handle_send_response()
  end

  @doc """
  Add, remove, promote, or demote group members.

  ## Parameters
  - `jid` - The group JID (must end with @g.us)
  - `participants` - List of participant JIDs to modify
  - `action` - One of: "add", "remove", "promote", "demote"

  ## Options
  - `:base_url` - Override the default base URL
  - `:plug` - Plug for testing with Req.Test

  ## Examples

      iex> WhatsappMcp.Bridge.update_group_participants("120363123456789012@g.us", ["12025551234@s.whatsapp.net"], "add")
      {:ok, %{message: "Successfully added to group: 1 participant(s)", participants: [%{jid: "12025551234@s.whatsapp.net", error_code: 0}]}}

      iex> WhatsappMcp.Bridge.update_group_participants("120363123456789012@g.us", ["12025551234@s.whatsapp.net"], "promote")
      {:ok, %{message: "Successfully promoted in group: 1 participant(s)", participants: [...]}}

      iex> WhatsappMcp.Bridge.update_group_participants("120363123456789012@g.us", [], "add")
      {:error, "At least one participant is required"}
  """
  @spec update_group_participants(String.t(), [String.t()], String.t(), keyword()) :: update_participants_result()
  def update_group_participants(jid, participants, action, opts \\ []) do
    opts
    |> build_request()
    |> Req.post(url: "/update-group-participants", json: %{jid: jid, participants: participants, action: action})
    |> handle_update_participants_response()
  end

  @typedoc "Result of privacy settings operation: settings map or error"
  @type privacy_settings_result ::
          {:ok, map()}
          | {:error, atom() | String.t()}

  @doc """
  Get the user's privacy settings.

  Returns all current privacy settings including who can see last seen, profile photo,
  about, and more.

  ## Options
  - `:base_url` - Override the default base URL
  - `:plug` - Plug for testing with Req.Test

  ## Examples

      iex> WhatsappMcp.Bridge.get_privacy_settings()
      {:ok, %{
        "group_add" => "contacts",
        "last_seen" => "contacts",
        "status" => "all",
        "profile" => "contacts",
        "read_receipts" => "all",
        "online" => "all",
        "call_add" => "all"
      }}
  """
  @spec get_privacy_settings(keyword()) :: privacy_settings_result()
  def get_privacy_settings(opts \\ []) do
    opts
    |> build_request()
    |> Req.get(url: "/privacy-settings")
    |> handle_privacy_settings_response()
  end

  @doc """
  Update a privacy setting.

  ## Parameters
  - `setting` - The setting to update: "groupadd", "last", "status", "profile", "readreceipts", "online", "calladd"
  - `value` - The new value: "all", "contacts", "contact_blacklist", "match_last_seen", "known", "none"

  ## Valid Setting/Value Combinations
  - **groupadd** - Who can add you to groups: "all", "contacts", "contact_blacklist", "none"
  - **last** - Who can see your last seen: "all", "contacts", "contact_blacklist", "none"
  - **status** - Who can see your status: "all", "contacts", "contact_blacklist", "none"
  - **profile** - Who can see your profile photo: "all", "contacts", "contact_blacklist", "none"
  - **readreceipts** - Whether to send read receipts: "all", "none"
  - **online** - Who can see you online: "all", "match_last_seen"
  - **calladd** - Who can call you: "all", "known"

  ## Options
  - `:base_url` - Override the default base URL
  - `:plug` - Plug for testing with Req.Test

  ## Examples

      iex> WhatsappMcp.Bridge.set_privacy_setting("last", "contacts")
      {:ok, "Privacy setting 'last' updated to 'contacts'"}

      iex> WhatsappMcp.Bridge.set_privacy_setting("readreceipts", "none")
      {:ok, "Privacy setting 'readreceipts' updated to 'none'"}
  """
  @spec set_privacy_setting(String.t(), String.t(), keyword()) :: send_result()
  def set_privacy_setting(setting, value, opts \\ []) do
    opts
    |> build_request()
    |> Req.post(url: "/privacy-setting", json: %{setting: setting, value: value})
    |> handle_send_response()
  end

  @typedoc "Result of business profile operation: profile info or error"
  @type business_profile_result ::
          {:ok, map()}
          | {:error, atom() | String.t()}

  @doc """
  Get the business profile for a contact.

  Returns business details including address, email, categories, and operating hours
  if the contact is a WhatsApp Business account.

  ## Parameters
  - `jid` - The contact JID (e.g., "12025551234@s.whatsapp.net")

  ## Options
  - `:base_url` - Override the default base URL
  - `:plug` - Plug for testing with Req.Test

  ## Examples

      iex> WhatsappMcp.Bridge.get_business_profile("12025551234@s.whatsapp.net")
      {:ok, %{
        "jid" => "12025551234@s.whatsapp.net",
        "address" => "123 Main St",
        "email" => "contact@example.com",
        "categories" => [%{"id" => "123", "name" => "Retail"}],
        "business_hours_timezone" => "America/New_York",
        "business_hours" => [
          %{"day_of_week" => "monday", "mode" => "open", "open_time" => "09:00", "close_time" => "17:00"}
        ]
      }}

      iex> WhatsappMcp.Bridge.get_business_profile("personal@s.whatsapp.net")
      {:error, "Contact is not a business account"}
  """
  @spec get_business_profile(String.t(), keyword()) :: business_profile_result()
  def get_business_profile(jid, opts \\ []) do
    opts
    |> build_request()
    |> Req.post(url: "/business-profile", json: %{jid: jid})
    |> handle_business_profile_response()
  end

  @doc """
  Reject an incoming WhatsApp call.

  This is typically used in response to a call event from the bridge to decline
  an incoming call programmatically.

  ## Parameters
  - `call_from` - The JID of the caller
  - `call_id` - The call ID (from the call event)

  ## Options
  - `:base_url` - Override the default base URL
  - `:plug` - Plug for testing with Req.Test

  ## Examples

      iex> WhatsappMcp.Bridge.reject_call("12025551234@s.whatsapp.net", "call_abc123")
      {:ok, "Call call_abc123 from 12025551234@s.whatsapp.net rejected"}
  """
  @spec reject_call(String.t(), String.t(), keyword()) :: send_result()
  def reject_call(call_from, call_id, opts \\ []) do
    opts
    |> build_request()
    |> Req.post(url: "/reject-call", json: %{call_from: call_from, call_id: call_id})
    |> handle_send_response()
  end

  # Newsletter functions

  @typedoc "Result of list newsletters operation: list of newsletters or error"
  @type list_newsletters_result ::
          {:ok, [map()]}
          | {:error, atom() | String.t()}

  @doc """
  List all subscribed WhatsApp channels (newsletters).

  Returns a list of newsletter metadata including name, description, subscriber count,
  and invite link.

  ## Options
  - `:base_url` - Override the default base URL
  - `:plug` - Plug for testing with Req.Test

  ## Examples

      iex> WhatsappMcp.Bridge.list_newsletters()
      {:ok, [
        %{
          "id" => "123456@newsletter",
          "name" => "Tech News",
          "description" => "Daily tech updates",
          "subscriber_count" => 50000,
          "invite_link" => "https://whatsapp.com/channel/abc123"
        }
      ]}
  """
  @spec list_newsletters(keyword()) :: list_newsletters_result()
  def list_newsletters(opts \\ []) do
    opts
    |> build_request()
    |> Req.get(url: "/newsletters")
    |> handle_list_newsletters_response()
  end

  @typedoc "Result of get newsletter info operation: newsletter info or error"
  @type newsletter_info_result ::
          {:ok, map()}
          | {:error, atom() | String.t()}

  @doc """
  Get info about a specific newsletter.

  ## Parameters
  - `jid` - The newsletter JID (ends with @newsletter)

  ## Options
  - `:base_url` - Override the default base URL
  - `:plug` - Plug for testing with Req.Test

  ## Examples

      iex> WhatsappMcp.Bridge.get_newsletter_info("123456@newsletter")
      {:ok, %{
        "id" => "123456@newsletter",
        "name" => "Tech News",
        "description" => "Daily tech updates",
        "subscriber_count" => 50000
      }}
  """
  @spec get_newsletter_info(String.t(), keyword()) :: newsletter_info_result()
  def get_newsletter_info(jid, opts \\ []) do
    opts
    |> build_request()
    |> Req.post(url: "/newsletter-info", json: %{jid: jid})
    |> handle_newsletter_info_response()
  end

  @typedoc "Result of get newsletter messages operation: list of messages or error"
  @type newsletter_messages_result ::
          {:ok, [map()]}
          | {:error, atom() | String.t()}

  @doc """
  Get messages from a newsletter.

  ## Parameters
  - `jid` - The newsletter JID (ends with @newsletter)

  ## Options

  API options:
  - `:count` - Number of messages to fetch (default: 50)
  - `:before` - Server ID to fetch messages before (for pagination)

  Request options:
  - `:base_url` - Override the default base URL
  - `:plug` - Plug for testing with Req.Test

  ## Examples

      iex> WhatsappMcp.Bridge.get_newsletter_messages("123456@newsletter", count: 10)
      {:ok, [
        %{
          "server_id" => 123,
          "text" => "Hello from the channel!",
          "timestamp" => "2025-01-15T10:30:00Z",
          "view_count" => 1500
        }
      ]}
  """
  @spec get_newsletter_messages(String.t(), keyword()) :: newsletter_messages_result()
  def get_newsletter_messages(jid, opts \\ []) do
    {count, opts} = Keyword.pop(opts, :count, 50)
    {before, opts} = Keyword.pop(opts, :before, nil)

    body = %{jid: jid, count: count}
    body = if before, do: Map.put(body, :before, before), else: body

    opts
    |> build_request()
    |> Req.post(url: "/newsletter-messages", json: body)
    |> handle_newsletter_messages_response()
  end

  @doc """
  Follow (subscribe to) a newsletter.

  ## Parameters
  - `jid` - The newsletter JID (ends with @newsletter)

  ## Options
  - `:base_url` - Override the default base URL
  - `:plug` - Plug for testing with Req.Test

  ## Examples

      iex> WhatsappMcp.Bridge.follow_newsletter("123456@newsletter")
      {:ok, "Successfully followed newsletter 123456@newsletter"}
  """
  @spec follow_newsletter(String.t(), keyword()) :: send_result()
  def follow_newsletter(jid, opts \\ []) do
    opts
    |> build_request()
    |> Req.post(url: "/follow-newsletter", json: %{jid: jid})
    |> handle_send_response()
  end

  @doc """
  Unfollow (unsubscribe from) a newsletter.

  ## Parameters
  - `jid` - The newsletter JID (ends with @newsletter)

  ## Options
  - `:base_url` - Override the default base URL
  - `:plug` - Plug for testing with Req.Test

  ## Examples

      iex> WhatsappMcp.Bridge.unfollow_newsletter("123456@newsletter")
      {:ok, "Successfully unfollowed newsletter 123456@newsletter"}
  """
  @spec unfollow_newsletter(String.t(), keyword()) :: send_result()
  def unfollow_newsletter(jid, opts \\ []) do
    opts
    |> build_request()
    |> Req.post(url: "/unfollow-newsletter", json: %{jid: jid})
    |> handle_send_response()
  end

  # Private functions

  defp maybe_add_field(map, _key, ""), do: map
  defp maybe_add_field(map, _key, nil), do: map
  defp maybe_add_field(map, key, value), do: Map.put(map, key, value)

  # Validates that a file path is safe (absolute path, no traversal patterns).
  # Returns :ok or {:error, :invalid_path}.
  @spec validate_file_path(String.t()) :: :ok | {:error, :invalid_path}
  defp validate_file_path(file_path) when is_binary(file_path) do
    cond do
      # Reject non-absolute paths
      not String.starts_with?(file_path, "/") ->
        {:error, :invalid_path}

      # Reject path traversal patterns
      String.contains?(file_path, "..") ->
        {:error, :invalid_path}

      # Path is safe
      true ->
        :ok
    end
  end

  defp validate_file_path(_), do: {:error, :invalid_path}

  defp build_request(opts) do
    base_url = Keyword.get(opts, :base_url, @default_base_url)
    plug = Keyword.get(opts, :plug)

    req = Req.new(base_url: base_url, receive_timeout: @request_timeout_ms, retry: false)

    if plug do
      Req.merge(req, plug: plug)
    else
      req
    end
  end

  # Generic response handler with custom success extractor.
  #
  # The extractor function is only called on successful responses (status 200
  # with "success" => true). It receives the full response body map and should
  # return {:ok, result} with the extracted data.
  @spec handle_response_with_extractor(
          {:ok, Req.Response.t()} | {:error, term()},
          (map() -> {:ok, term()}),
          String.t()
        ) :: {:ok, term()} | {:error, atom() | String.t()}
  defp handle_response_with_extractor(response, success_extractor, error_context) do
    case response do
      {:ok, %Req.Response{status: 200, body: %{"success" => true} = body}} ->
        success_extractor.(body)

      {:ok, %Req.Response{status: 200, body: %{"success" => false, "message" => message}}} ->
        {:error, message}

      {:ok, %Req.Response{status: 429, body: body}} ->
        {:error, rate_limit_error(body)}

      {:ok, %Req.Response{status: status, body: body}} when status in 400..599 ->
        {:error, body_to_error(body, error_context)}

      {:error, %Req.TransportError{reason: reason}} when reason in [:econnrefused, :closed] ->
        {:error, :bridge_not_running}

      {:error, %Req.TransportError{reason: :timeout}} ->
        {:error, :timeout}

      {:error, error} ->
        Logger.debug("Bridge request failed: #{inspect(error)}")
        {:error, inspect(error)}
    end
  end

  # Simplified handler for responses that extract a single key
  @spec handle_response_extract_key(
          {:ok, Req.Response.t()} | {:error, term()},
          String.t(),
          String.t()
        ) :: {:ok, term()} | {:error, atom() | String.t()}
  defp handle_response_extract_key(response, key, error_context) do
    handle_response_with_extractor(
      response,
      fn body -> {:ok, body[key]} end,
      error_context
    )
  end

  defp handle_health_response({:ok, %Req.Response{status: 200, body: body}}) when is_map(body) do
    {:ok, body}
  end

  defp handle_health_response({:ok, %Req.Response{status: _status}}) do
    {:ok, %{"connected" => false}}
  end

  defp handle_health_response({:error, %Req.TransportError{reason: reason}})
       when reason in [:econnrefused, :closed, :timeout] do
    {:error, :bridge_not_running}
  end

  defp handle_health_response({:error, _}), do: {:error, :bridge_not_running}

  defp handle_send_response({:ok, %Req.Response{status: 200, body: %{"success" => true, "message" => message}}}) do
    {:ok, message}
  end

  defp handle_send_response({:ok, %Req.Response{status: 200, body: %{"success" => false, "message" => message}}}) do
    {:error, message}
  end

  defp handle_send_response({:ok, %Req.Response{status: 429, body: body}}) do
    {:error, rate_limit_error(body)}
  end

  defp handle_send_response({:ok, %Req.Response{status: status, body: body}}) when status in 400..499 do
    {:error, body_to_error(body, "Bad request")}
  end

  defp handle_send_response({:ok, %Req.Response{status: status, body: body}}) when status in 500..599 do
    {:error, body_to_error(body, "Server error")}
  end

  defp handle_send_response({:error, %Req.TransportError{reason: reason}}) when reason in [:econnrefused, :closed] do
    {:error, :bridge_not_running}
  end

  defp handle_send_response({:error, %Req.TransportError{reason: :timeout}}) do
    {:error, :timeout}
  end

  defp handle_send_response({:error, error}) do
    Logger.debug("Bridge request failed: #{inspect(error)}")
    {:error, inspect(error)}
  end

  defp handle_download_response(response) do
    handle_response_with_extractor(
      response,
      fn body ->
        {:ok,
         %{
           path: body["path"],
           filename: body["filename"],
           media_type: extract_media_type(body["message"])
         }}
      end,
      "Download failed"
    )
  end

  defp handle_resolve_response(response) do
    handle_response_with_extractor(
      response,
      fn body -> {:ok, %{phone: body["phone"], name: body["name"]}} end,
      "Failed to resolve LID"
    )
  end

  defp handle_is_on_whatsapp_response(response) do
    handle_response_with_extractor(
      response,
      fn body ->
        parsed_results =
          Enum.map(body["results"], fn result ->
            %{
              phone: result["phone"],
              is_on_whatsapp: result["is_on_whatsapp"],
              jid: if(result["is_on_whatsapp"], do: result["jid"])
            }
          end)

        {:ok, parsed_results}
      end,
      "Failed to check phone numbers"
    )
  end

  defp handle_profile_picture_response(response) do
    handle_response_with_extractor(
      response,
      fn body -> {:ok, %{url: body["url"], id: body["id"]}} end,
      "Failed to get profile picture"
    )
  end

  defp handle_blocklist_response(response) do
    handle_response_extract_key(response, "blocklist", "Failed to get blocklist")
  end

  defp handle_list_groups_response(response) do
    handle_response_extract_key(response, "groups", "Failed to list groups")
  end

  defp handle_group_info_response(response) do
    handle_response_extract_key(response, "group", "Failed to get group info")
  end

  defp handle_group_invite_link_response(response) do
    handle_response_extract_key(response, "invite_link", "Failed to get invite link")
  end

  defp handle_join_group_response(response) do
    handle_response_with_extractor(
      response,
      fn body -> {:ok, %{group_jid: body["group_jid"], message: body["message"]}} end,
      "Failed to join group"
    )
  end

  defp handle_create_group_response(response) do
    handle_response_extract_key(response, "group", "Failed to create group")
  end

  defp handle_leave_group_response(response) do
    handle_response_extract_key(response, "message", "Failed to leave group")
  end

  defp handle_list_contacts_response(response) do
    handle_response_with_extractor(
      response,
      fn body -> {:ok, %{contacts: body["contacts"], total: body["total"]}} end,
      "Failed to list contacts"
    )
  end

  defp handle_merge_chats_response(response) do
    handle_response_with_extractor(
      response,
      fn body -> {:ok, %{message: body["message"], messages_moved: body["messages_moved"]}} end,
      "Failed to merge chats"
    )
  end

  defp handle_update_participants_response(response) do
    handle_response_with_extractor(
      response,
      fn body ->
        parsed_participants =
          Enum.map(body["participants"], fn p ->
            %{jid: p["jid"], error_code: p["error_code"] || 0}
          end)

        {:ok, %{message: body["message"], participants: parsed_participants}}
      end,
      "Failed to update participants"
    )
  end

  defp handle_privacy_settings_response(response) do
    handle_response_with_extractor(
      response,
      fn body ->
        {:ok,
         %{
           group_add: body["group_add"],
           last_seen: body["last_seen"],
           status: body["status"],
           profile: body["profile"],
           read_receipts: body["read_receipts"],
           online: body["online"],
           call_add: body["call_add"]
         }}
      end,
      "Failed to get privacy settings"
    )
  end

  defp handle_business_profile_response(response) do
    handle_response_extract_key(response, "profile", "Failed to get business profile")
  end

  defp handle_list_newsletters_response(response) do
    handle_response_extract_key(response, "newsletters", "Failed to list newsletters")
  end

  defp handle_newsletter_info_response(response) do
    handle_response_extract_key(response, "newsletter", "Failed to get newsletter info")
  end

  defp handle_newsletter_messages_response(response) do
    handle_response_extract_key(response, "messages", "Failed to get newsletter messages")
  end

  defp body_to_error(%{"message" => message}, _default), do: message
  defp body_to_error(body, _default) when is_binary(body), do: body
  defp body_to_error(_body, default), do: default

  defp rate_limit_error(%{"message" => message}),
    do: "Rate limited by WhatsApp: #{message}. Wait a few minutes before retrying."

  defp rate_limit_error(_body), do: "Rate limited by WhatsApp. Wait a few minutes before retrying."

  # Extract media type from success message like "Successfully downloaded image media"
  defp extract_media_type(message) when is_binary(message) do
    cond do
      String.contains?(message, "image") -> "image"
      String.contains?(message, "video") -> "video"
      String.contains?(message, "audio") -> "audio"
      String.contains?(message, "document") -> "document"
      true -> "unknown"
    end
  end

  defp extract_media_type(_), do: "unknown"
end
