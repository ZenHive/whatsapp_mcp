defmodule WhatsappMcp.Database do
  @moduledoc """
  SQLite database queries for WhatsApp chat history.

  Queries the Go bridge's SQLite database (messages.db) which stores
  messages synced via the WhatsApp Web Multi-Device API.

  ## Schema

  - `chats` table: `jid`, `name`, `last_message_time`
  - `messages` table: `id`, `chat_jid`, `sender`, `content`, `timestamp`,
    `is_from_me`, `media_type`, `filename`
  - `contacts` table: `jid`, `phone`, `name`, `updated_at` (LID→phone cache)

  ## Types

  This module re-exports types from submodules for convenience:
  - `t:message/0` - from `WhatsappMcp.Database.Messages`
  - `t:message_context/0` - from `WhatsappMcp.Database.Messages`

  ## Submodules

  This module delegates to specialized submodules:
  - `WhatsappMcp.Database.Chats` - Chat listing and retrieval
  - `WhatsappMcp.Database.Messages` - Message queries and search
  - `WhatsappMcp.Database.Contacts` - Contact search and interactions
  - `WhatsappMcp.Database.Helpers` - Shared utilities
  """
  alias WhatsappMcp.Database.Chats
  alias WhatsappMcp.Database.Contacts
  alias WhatsappMcp.Database.Messages

  # Re-export types from Messages submodule
  @typedoc "A message with metadata"
  @type message :: Messages.message()

  @typedoc "Context surrounding a target message"
  @type message_context :: Messages.message_context()

  # Chat functions - delegate to Chats submodule
  defdelegate list_chats(opts \\ []), to: Chats
  defdelegate get_chat(opts \\ []), to: Chats
  defdelegate get_chat_by_phone(opts \\ []), to: Chats
  defdelegate get_chat_by_name(opts \\ []), to: Chats
  defdelegate get_contact_chats(opts \\ []), to: Chats
  defdelegate count_chats(opts \\ []), to: Chats
  defdelegate count_contact_chats(opts \\ []), to: Chats
  defdelegate get_linked_jid(opts \\ []), to: Chats

  # Message functions - delegate to Messages submodule
  defdelegate get_messages(opts \\ []), to: Messages
  defdelegate search_messages(opts \\ []), to: Messages
  defdelegate get_message_context(opts \\ []), to: Messages
  defdelegate count_messages(opts \\ []), to: Messages
  defdelegate count_search_results(opts \\ []), to: Messages

  # Contact functions - delegate to Contacts submodule
  defdelegate search_contacts(opts \\ []), to: Contacts
  defdelegate get_last_interaction(opts \\ []), to: Contacts
  defdelegate count_contacts(opts \\ []), to: Contacts
  defdelegate get_cached_contact(opts \\ []), to: Contacts
  defdelegate find_contact_by_phone(opts \\ []), to: Contacts
  defdelegate find_linked_jids(opts \\ []), to: Contacts
end
