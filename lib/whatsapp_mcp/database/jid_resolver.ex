defmodule WhatsappMcp.Database.JidResolver do
  @moduledoc """
  Centralized JID resolution for WhatsApp contacts.

  WhatsApp uses two JID formats for individual contacts:
  - `{phone}@s.whatsapp.net` - Traditional phone-based JID
  - `{numeric_id}@lid` - Linked ID format (privacy feature since 2025)

  This module provides functions to:
  - Determine JID type (phone, lid, group)
  - Resolve between @lid and @s.whatsapp.net formats
  - Find all linked JIDs for a contact

  ## Example

      # Get the phone JID for a LID contact
      {:ok, "12025551234@s.whatsapp.net"} = phone_jid_for_lid("144555781402794@lid", db_path)

      # Get all JIDs for a contact (both formats)
      {:ok, ["12025551234@s.whatsapp.net", "144555781402794@lid"]} = find_all_linked_jids("12025551234@s.whatsapp.net", db_path)

  """

  alias WhatsappMcp.Database.Helpers

  @typedoc "JID type classification"
  @type jid_type() :: :phone_jid | :lid_jid | :group_jid | :unknown

  @doc """
  Determines the type of a WhatsApp JID.

  ## Returns

  - `:phone_jid` - Traditional phone format (ends with `@s.whatsapp.net`)
  - `:lid_jid` - Linked ID format (ends with `@lid`)
  - `:group_jid` - Group chat (ends with `@g.us`)
  - `:unknown` - Unrecognized format

  ## Examples

      iex> jid_type("12025551234@s.whatsapp.net")
      :phone_jid

      iex> jid_type("144555781402794@lid")
      :lid_jid

      iex> jid_type("120363123456789012@g.us")
      :group_jid

  """
  @spec jid_type(String.t()) :: jid_type()
  def jid_type(jid) when is_binary(jid) do
    cond do
      String.ends_with?(jid, "@s.whatsapp.net") -> :phone_jid
      String.ends_with?(jid, "@lid") -> :lid_jid
      String.ends_with?(jid, "@g.us") -> :group_jid
      true -> :unknown
    end
  end

  @doc """
  Extracts the phone number from a phone JID.

  ## Examples

      iex> extract_phone_from_jid("12025551234@s.whatsapp.net")
      "12025551234"

      iex> extract_phone_from_jid("144555781402794@lid")
      nil

  """
  @spec extract_phone_from_jid(String.t()) :: String.t() | nil
  def extract_phone_from_jid(jid) when is_binary(jid) do
    case jid_type(jid) do
      :phone_jid -> String.replace(jid, "@s.whatsapp.net", "")
      _ -> nil
    end
  end

  @doc """
  Converts a phone number to the standard phone JID format.

  ## Examples

      iex> phone_to_jid("12025551234")
      "12025551234@s.whatsapp.net"

  """
  @spec phone_to_jid(String.t()) :: String.t()
  def phone_to_jid(phone) when is_binary(phone) do
    "#{phone}@s.whatsapp.net"
  end

  @doc """
  Gets the @s.whatsapp.net JID for an @lid JID.

  Looks up the phone number from the contacts cache and constructs
  the phone-based JID.

  ## Parameters

  - `lid_jid` - The @lid format JID
  - `db_path` - Path to the SQLite database

  ## Returns

  - `{:ok, phone_jid}` - The corresponding phone JID
  - `{:ok, nil}` - No phone mapping found in cache
  - `{:error, reason}` - Database error

  """
  @spec phone_jid_for_lid(String.t(), String.t()) :: {:ok, String.t() | nil} | {:error, term()}
  def phone_jid_for_lid(lid_jid, db_path) do
    query = "SELECT phone FROM contacts WHERE jid = ?"

    case Helpers.with_readonly_connection(db_path, query, [lid_jid]) do
      {:ok, [[phone]]} when is_binary(phone) and phone != "" ->
        {:ok, phone_to_jid(phone)}

      {:ok, [[nil]]} ->
        {:ok, nil}

      {:ok, []} ->
        {:ok, nil}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets the @lid JID for an @s.whatsapp.net JID.

  Extracts the phone number and looks for a corresponding @lid JID
  in the contacts cache.

  ## Parameters

  - `phone_jid` - The @s.whatsapp.net format JID
  - `db_path` - Path to the SQLite database

  ## Returns

  - `{:ok, lid_jid}` - The corresponding LID JID
  - `{:ok, nil}` - No LID mapping found in cache
  - `{:error, reason}` - Database error

  """
  @spec lid_for_phone_jid(String.t(), String.t()) :: {:ok, String.t() | nil} | {:error, term()}
  def lid_for_phone_jid(phone_jid, db_path) do
    phone = String.replace(phone_jid, "@s.whatsapp.net", "")
    query = "SELECT jid FROM contacts WHERE phone = ? AND jid LIKE '%@lid' LIMIT 1"

    case Helpers.with_readonly_connection(db_path, query, [phone]) do
      {:ok, [[lid_jid]]} -> {:ok, lid_jid}
      {:ok, []} -> {:ok, nil}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Finds all JIDs linked to a contact.

  Returns all known JID formats for the same contact:
  - For @s.whatsapp.net input: returns input + any @lid JIDs with matching phone
  - For @lid input: returns input + the @s.whatsapp.net version if phone is cached
  - For @g.us (groups): returns just the input (groups don't have linked JIDs)

  ## Parameters

  - `jid` - Any JID format
  - `db_path` - Path to the SQLite database

  ## Returns

  A list of all known JIDs for this contact (always includes the input JID).

  ## Examples

      # Phone JID with known LID mapping
      {:ok, ["12025551234@s.whatsapp.net", "144555781402794@lid"]}

      # LID with cached phone
      {:ok, ["144555781402794@lid", "12025551234@s.whatsapp.net"]}

      # No linked JIDs found
      {:ok, ["12025551234@s.whatsapp.net"]}

  """
  @spec find_all_linked_jids(String.t(), String.t()) :: {:ok, [String.t()]} | {:error, term()}
  def find_all_linked_jids(jid, db_path) do
    linked_jids = MapSet.new([jid])

    result =
      case jid_type(jid) do
        :phone_jid ->
          find_lids_for_phone(jid, db_path, linked_jids)

        :lid_jid ->
          find_phone_jids_for_lid(jid, db_path, linked_jids)

        :group_jid ->
          linked_jids

        :unknown ->
          linked_jids
      end

    {:ok, MapSet.to_list(result)}
  end

  # Find @lid JIDs that have the same phone number
  @spec find_lids_for_phone(String.t(), String.t(), MapSet.t()) :: MapSet.t()
  defp find_lids_for_phone(phone_jid, db_path, linked_jids) do
    phone = String.replace(phone_jid, "@s.whatsapp.net", "")

    query = """
    SELECT jid
    FROM contacts
    WHERE phone = ? AND jid LIKE '%@lid'
    """

    case Helpers.with_readonly_connection(db_path, query, [phone]) do
      {:ok, rows} ->
        Enum.reduce(rows, linked_jids, fn [lid_jid], acc ->
          MapSet.put(acc, lid_jid)
        end)

      {:error, _} ->
        linked_jids
    end
  end

  # Find @s.whatsapp.net JID from @lid by looking up cached phone
  @spec find_phone_jids_for_lid(String.t(), String.t(), MapSet.t()) :: MapSet.t()
  defp find_phone_jids_for_lid(lid_jid, db_path, linked_jids) do
    query = """
    SELECT phone
    FROM contacts
    WHERE jid = ?
    """

    case Helpers.with_readonly_connection(db_path, query, [lid_jid]) do
      {:ok, [[phone]]} when is_binary(phone) and phone != "" ->
        MapSet.put(linked_jids, phone_to_jid(phone))

      {:ok, [[nil]]} ->
        linked_jids

      {:ok, []} ->
        linked_jids

      {:error, _} ->
        linked_jids
    end
  end
end
