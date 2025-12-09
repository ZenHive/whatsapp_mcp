defmodule WhatsappMcp.Tools.Definitions do
  @moduledoc """
  MCP tool schema definitions.

  Defines the available tools and their input schemas in MCP format.
  """

  @doc """
  Returns the list of available tools in MCP format.
  """
  @spec list_tools() :: [map()]
  def list_tools do
    [
      %{
        "name" => "list_chats",
        "description" =>
          "List all WhatsApp chats with JIDs, names, and last message preview. Returns chat JIDs needed for get_messages and other tools. Supports pagination with offset/limit.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "limit" => %{
              "type" => "integer",
              "description" => "Maximum number of chats to return (default: 50)",
              "default" => 50
            },
            "offset" => %{
              "type" => "integer",
              "description" => "Number of chats to skip for pagination (default: 0)",
              "default" => 0
            }
          }
        }
      },
      %{
        "name" => "get_messages",
        "description" =>
          "Get messages from a specific WhatsApp chat. Provide either chat_id (from list_chats) or chat_name (partial match).",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "chat_id" => %{
              "type" => "string",
              "description" => "Chat JID from list_chats (e.g., '12025551234@s.whatsapp.net')"
            },
            "chat_name" => %{
              "type" => "string",
              "description" => "Partial chat/contact name to match (alternative to chat_id)"
            },
            "limit" => %{
              "type" => "integer",
              "description" => "Maximum number of messages to return (default: 100)",
              "default" => 100
            },
            "offset" => %{
              "type" => "integer",
              "description" => "Number of messages to skip for pagination (default: 0)",
              "default" => 0
            },
            "before" => %{
              "type" => "string",
              "description" =>
                "Only return messages before this timestamp (ISO8601 format, e.g., '2025-12-11T10:00:00'). All timestamps are in UTC. Convert user's local time to UTC before filtering."
            },
            "after" => %{
              "type" => "string",
              "description" =>
                "Only return messages after this timestamp (ISO8601 format, e.g., '2025-12-10T00:00:00'). All timestamps are in UTC. Convert user's local time to UTC before filtering."
            }
          }
        }
      },
      %{
        "name" => "search_messages",
        "description" =>
          "Search for messages containing specific text across all chats or within a specific chat. Returns message IDs for use with get_message_context or download_media. Can also filter by media attachments.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "query" => %{
              "type" => "string",
              "description" => "Text to search for in messages (optional if has_media is true)"
            },
            "chat_id" => %{
              "type" => "string",
              "description" => "Optional: limit search to this chat JID"
            },
            "has_media" => %{
              "type" => "boolean",
              "description" => "If true, only return messages with attachments (image, video, audio, document)",
              "default" => false
            },
            "limit" => %{
              "type" => "integer",
              "description" => "Maximum number of results (default: 50)",
              "default" => 50
            },
            "offset" => %{
              "type" => "integer",
              "description" => "Number of results to skip for pagination (default: 0)",
              "default" => 0
            }
          }
        }
      },
      %{
        "name" => "send_message",
        "description" => "Send a WhatsApp message to a person or group.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "recipient" => %{
              "type" => "string",
              "description" =>
                "Phone number (e.g., '12025551234') or JID (e.g., '12025551234@s.whatsapp.net' or group JID)"
            },
            "message" => %{
              "type" => "string",
              "description" => "The message text to send"
            }
          },
          "required" => ["recipient", "message"]
        }
      },
      %{
        "name" => "send_file",
        "description" => "Send a file (image, video, document) via WhatsApp.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "recipient" => %{
              "type" => "string",
              "description" => "Phone number or JID"
            },
            "file_path" => %{
              "type" => "string",
              "description" => "Absolute path to the file to send"
            },
            "caption" => %{
              "type" => "string",
              "description" => "Optional caption for the file"
            }
          },
          "required" => ["recipient", "file_path"]
        }
      },
      %{
        "name" => "send_audio_message",
        "description" =>
          "Send an audio file as a WhatsApp voice message. The file must be in OGG Opus format (.ogg extension).",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "recipient" => %{
              "type" => "string",
              "description" => "Phone number or JID"
            },
            "file_path" => %{
              "type" => "string",
              "description" => "Absolute path to the audio file (must be .ogg format)"
            }
          },
          "required" => ["recipient", "file_path"]
        }
      },
      %{
        "name" => "download_media",
        "description" => "Download media (image, video, audio, document) from a WhatsApp message.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "message_id" => %{
              "type" => "string",
              "description" => "The message ID containing media"
            },
            "chat_jid" => %{
              "type" => "string",
              "description" => "The chat JID where the message exists"
            }
          },
          "required" => ["message_id", "chat_jid"]
        }
      },
      %{
        "name" => "search_contacts",
        "description" =>
          "Search WhatsApp contacts by name or phone number. Returns contacts with JID, name, and phone. Use returned JID for send_message, get_messages, etc. IMPORTANT: Only names stored on WhatsApp's servers are searchable (push names, Business profile names, group names) - NOT phone address book names. If a contact hasn't set a push name, they appear as their phone number only. If name search fails, ASK THE USER for the phone number.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "query" => %{
              "type" => "string",
              "description" => "Search term to match against names or phone numbers"
            },
            "limit" => %{
              "type" => "integer",
              "description" => "Maximum number of results (default: 50)",
              "default" => 50
            }
          },
          "required" => ["query"]
        }
      },
      %{
        "name" => "get_chat",
        "description" => "Get metadata for a specific chat by JID.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "jid" => %{
              "type" => "string",
              "description" => "The chat JID (e.g., '12025551234@s.whatsapp.net' or group JID)"
            }
          },
          "required" => ["jid"]
        }
      },
      %{
        "name" => "get_direct_chat_by_contact",
        "description" => "Get chat metadata for an individual contact by phone number. Does not work for groups.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "phone" => %{
              "type" => "string",
              "description" => "Phone number (e.g., '12025551234')"
            }
          },
          "required" => ["phone"]
        }
      },
      %{
        "name" => "get_message_context",
        "description" =>
          "Get messages before and after a specific message for context. Useful when you find a message via search and want to see the surrounding conversation.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "message_id" => %{
              "type" => "string",
              "description" => "The target message ID"
            },
            "before" => %{
              "type" => "integer",
              "description" => "Number of messages before the target (default: 5)",
              "default" => 5
            },
            "after" => %{
              "type" => "integer",
              "description" => "Number of messages after the target (default: 5)",
              "default" => 5
            }
          },
          "required" => ["message_id"]
        }
      },
      %{
        "name" => "get_last_interaction",
        "description" =>
          "Get the most recent message with a contact. Finds the latest message in direct chat or sent by contact in groups.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "contact_jid" => %{
              "type" => "string",
              "description" => "The contact's JID (e.g., '12025551234@s.whatsapp.net')"
            }
          },
          "required" => ["contact_jid"]
        }
      },
      %{
        "name" => "get_contact_chats",
        "description" =>
          "List all chats involving a contact, including direct chat and groups where they've sent messages. NOTE: Some contacts (especially @lid format) may only appear in group chats if you've never had a direct conversation with them.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "contact_jid" => %{
              "type" => "string",
              "description" => "The contact's JID (e.g., '12025551234@s.whatsapp.net')"
            },
            "limit" => %{
              "type" => "integer",
              "description" => "Maximum number of chats to return (default: 50)",
              "default" => 50
            }
          },
          "required" => ["contact_jid"]
        }
      },
      %{
        "name" => "get_bridge_status",
        "description" =>
          "Check if the WhatsApp bridge is running and get connection status. Returns whether connected, phone number, and account name. If bridge is not running, returns startup instructions.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{}
        }
      },
      %{
        "name" => "get_help",
        "description" =>
          "Get help on using WhatsApp MCP tools. IMPORTANT: Call this tool first if you're unsure about phone number formats, JIDs, or how to find contacts.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{}
        }
      },
      %{
        "name" => "send_typing",
        "description" =>
          "Send a typing indicator to show you're composing a message. Use composing: true to start, false to stop.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "recipient" => %{
              "type" => "string",
              "description" => "Phone number or JID"
            },
            "composing" => %{
              "type" => "boolean",
              "description" => "true to start typing indicator, false to stop",
              "default" => true
            }
          },
          "required" => ["recipient"]
        }
      },
      %{
        "name" => "mark_read",
        "description" =>
          "Mark messages as read (sends blue tick receipts). Provide the chat JID and list of message IDs.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "chat_jid" => %{
              "type" => "string",
              "description" => "The chat JID where the messages exist"
            },
            "message_ids" => %{
              "type" => "array",
              "items" => %{"type" => "string"},
              "description" => "List of message IDs to mark as read"
            }
          },
          "required" => ["chat_jid", "message_ids"]
        }
      },
      %{
        "name" => "react_to_message",
        "description" => "Add an emoji reaction to a message. Use an empty emoji string to remove an existing reaction.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "chat_jid" => %{
              "type" => "string",
              "description" => "The chat JID where the message exists"
            },
            "message_id" => %{
              "type" => "string",
              "description" => "The message ID to react to"
            },
            "sender" => %{
              "type" => "string",
              "description" => "The sender JID of the original message"
            },
            "emoji" => %{
              "type" => "string",
              "description" => "The emoji to react with (e.g., '👍', '❤️'). Empty string removes reaction."
            }
          },
          "required" => ["chat_jid", "message_id", "sender", "emoji"]
        }
      },
      %{
        "name" => "delete_message",
        "description" =>
          "Delete a message for everyone. Only works for your own messages within WhatsApp's time limit (~1 hour).",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "chat_jid" => %{
              "type" => "string",
              "description" => "The chat JID where the message exists"
            },
            "message_id" => %{
              "type" => "string",
              "description" => "The message ID to delete"
            },
            "sender" => %{
              "type" => "string",
              "description" => "The sender JID of the message (must be your own JID)"
            }
          },
          "required" => ["chat_jid", "message_id", "sender"]
        }
      },
      %{
        "name" => "reply_to_message",
        "description" => "Reply to a specific message (quote-reply). The reply will show the quoted original message.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "recipient" => %{
              "type" => "string",
              "description" => "Phone number or JID to send the reply to"
            },
            "message" => %{
              "type" => "string",
              "description" => "The reply message text"
            },
            "quoted_message_id" => %{
              "type" => "string",
              "description" => "The message ID being replied to"
            },
            "quoted_chat_jid" => %{
              "type" => "string",
              "description" => "The chat JID where the quoted message exists"
            },
            "quoted_sender" => %{
              "type" => "string",
              "description" => "The JID of the person who sent the quoted message"
            }
          },
          "required" => ["recipient", "message", "quoted_message_id", "quoted_chat_jid", "quoted_sender"]
        }
      },
      %{
        "name" => "edit_message",
        "description" =>
          "Edit a sent message. Only works for your own messages within WhatsApp's time limit (~15 minutes).",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "chat_jid" => %{
              "type" => "string",
              "description" => "The chat JID where the message exists"
            },
            "message_id" => %{
              "type" => "string",
              "description" => "The message ID to edit"
            },
            "new_content" => %{
              "type" => "string",
              "description" => "The new text content for the message"
            }
          },
          "required" => ["chat_jid", "message_id", "new_content"]
        }
      },
      %{
        "name" => "send_location",
        "description" =>
          "Send a location pin to a WhatsApp chat. Specify coordinates and optionally a place name and address.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "recipient" => %{
              "type" => "string",
              "description" => "Phone number or JID to send the location to"
            },
            "latitude" => %{
              "type" => "number",
              "description" => "Latitude in degrees (-90 to 90)",
              "minimum" => -90,
              "maximum" => 90
            },
            "longitude" => %{
              "type" => "number",
              "description" => "Longitude in degrees (-180 to 180)",
              "minimum" => -180,
              "maximum" => 180
            },
            "name" => %{
              "type" => "string",
              "description" => "Optional place name (e.g., 'Eiffel Tower')"
            },
            "address" => %{
              "type" => "string",
              "description" => "Optional address (e.g., 'Champ de Mars, 75007 Paris')"
            }
          },
          "required" => ["recipient", "latitude", "longitude"]
        }
      },
      %{
        "name" => "set_presence",
        "description" =>
          "Set your online presence status. Controls whether you appear as online (available) or offline (unavailable) to your contacts.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "available" => %{
              "type" => "boolean",
              "description" => "true to appear online, false to appear offline"
            }
          },
          "required" => ["available"]
        }
      },
      %{
        "name" => "subscribe_presence",
        "description" =>
          "Subscribe to presence updates for a contact. After subscribing, you'll be notified when the contact comes online or goes offline.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "jid" => %{
              "type" => "string",
              "description" => "The contact's JID (e.g., '12025551234@s.whatsapp.net')"
            }
          },
          "required" => ["jid"]
        }
      },
      %{
        "name" => "set_disappearing_timer",
        "description" =>
          "Set the disappearing messages timer for a chat. Messages sent after enabling will automatically delete after the specified duration.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "chat_jid" => %{
              "type" => "string",
              "description" => "The chat JID (individual or group)"
            },
            "timer" => %{
              "type" => "string",
              "description" => "Timer duration: 'off' (disable), '24h' (24 hours), '7d' (7 days), or '90d' (90 days)",
              "enum" => ["off", "24h", "7d", "90d"]
            }
          },
          "required" => ["chat_jid", "timer"]
        }
      },
      %{
        "name" => "is_on_whatsapp",
        "description" =>
          "Check if phone numbers are registered on WhatsApp. Validates up to 50 numbers at once. Returns each number's WhatsApp status and JID if registered.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "phones" => %{
              "type" => "array",
              "items" => %{"type" => "string"},
              "description" => "List of phone numbers to check (e.g., ['12025551234', '44123456789']). Max 50 numbers.",
              "maxItems" => 50
            }
          },
          "required" => ["phones"]
        }
      },
      %{
        "name" => "get_profile_picture",
        "description" =>
          "Get the profile picture URL for a contact or group. Returns the image URL that can be downloaded. May fail if the contact has privacy settings enabled.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "jid" => %{
              "type" => "string",
              "description" => "The contact or group JID (e.g., '12025551234@s.whatsapp.net')"
            }
          },
          "required" => ["jid"]
        }
      },
      %{
        "name" => "get_blocklist",
        "description" => "Get the list of all blocked contacts. Returns an array of blocked JIDs.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{}
        }
      },
      %{
        "name" => "update_blocklist",
        "description" => "Block or unblock a contact. Blocked contacts cannot send you messages.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "jid" => %{
              "type" => "string",
              "description" => "The contact JID to block or unblock"
            },
            "action" => %{
              "type" => "string",
              "description" => "Action to perform: 'block' to add to blocklist, 'unblock' to remove",
              "enum" => ["block", "unblock"]
            }
          },
          "required" => ["jid", "action"]
        }
      },
      %{
        "name" => "create_poll",
        "description" =>
          "Create and send a WhatsApp poll. Polls support 2-12 options and can be single-choice (1 selection) or multi-choice (multiple selections allowed).",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "recipient" => %{
              "type" => "string",
              "description" => "Phone number or JID to send the poll to"
            },
            "question" => %{
              "type" => "string",
              "description" => "The poll question"
            },
            "options" => %{
              "type" => "array",
              "items" => %{"type" => "string"},
              "description" => "List of poll options (2-12 options)",
              "minItems" => 2,
              "maxItems" => 12
            },
            "max_selections" => %{
              "type" => "integer",
              "description" =>
                "Maximum number of options a user can select. Use 1 for single-choice polls, or higher for multi-choice (default: 1)",
              "default" => 1,
              "minimum" => 1
            }
          },
          "required" => ["recipient", "question", "options"]
        }
      },
      %{
        "name" => "list_groups",
        "description" =>
          "List all joined WhatsApp groups. Returns group JIDs, names, topics, participant counts, and settings. Use returned JIDs with get_group_info for detailed member lists.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{}
        }
      },
      %{
        "name" => "get_group_info",
        "description" =>
          "Get detailed information about a WhatsApp group including all participants and their roles (admin/member). The JID must be a group JID ending in @g.us.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "jid" => %{
              "type" => "string",
              "description" => "The group JID (must end with @g.us, e.g., '120363123456789012@g.us')"
            }
          },
          "required" => ["jid"]
        }
      },
      %{
        "name" => "get_group_invite_link",
        "description" =>
          "Get the invite link for a group. Only group admins can access invite links. Use reset: true to invalidate the current link and generate a new one.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "jid" => %{
              "type" => "string",
              "description" => "The group JID (must end with @g.us)"
            },
            "reset" => %{
              "type" => "boolean",
              "description" => "If true, reset the invite link (invalidates old link). Default: false",
              "default" => false
            }
          },
          "required" => ["jid"]
        }
      },
      %{
        "name" => "join_group",
        "description" =>
          "Join a WhatsApp group using an invite link. Accepts either a full link (https://chat.whatsapp.com/CODE) or just the invite code.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "invite_link" => %{
              "type" => "string",
              "description" =>
                "The invite link (e.g., 'https://chat.whatsapp.com/ABC123') or just the code (e.g., 'ABC123')"
            }
          },
          "required" => ["invite_link"]
        }
      },
      %{
        "name" => "create_group",
        "description" => "Create a new WhatsApp group with initial members. Group names are limited to 25 characters.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "name" => %{
              "type" => "string",
              "description" => "The group name (max 25 characters)"
            },
            "participants" => %{
              "type" => "array",
              "items" => %{"type" => "string"},
              "description" =>
                "List of JIDs to add as initial members (e.g., ['12025551234@s.whatsapp.net']). Your own JID is added automatically."
            }
          },
          "required" => ["name"]
        }
      },
      %{
        "name" => "leave_group",
        "description" => "Leave a WhatsApp group.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "jid" => %{
              "type" => "string",
              "description" => "The group JID to leave (must end with @g.us)"
            }
          },
          "required" => ["jid"]
        }
      },
      %{
        "name" => "list_contacts",
        "description" =>
          "List all synced WhatsApp contacts from your phone's address book. Shows names and redacted phone numbers which can help identify @lid contacts. Use this to find contacts that may not appear in chat list or to match unknown @lid JIDs to known contacts by their redacted phone pattern.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "limit" => %{
              "type" => "integer",
              "description" => "Maximum contacts to return (default: 100)",
              "default" => 100
            },
            "offset" => %{
              "type" => "integer",
              "description" => "Pagination offset (default: 0)",
              "default" => 0
            },
            "query" => %{
              "type" => "string",
              "description" => "Optional: filter by name (searches full name, first name, push name, and business name)"
            }
          }
        }
      },
      %{
        "name" => "merge_chats",
        "description" =>
          "Merge messages from one chat into another (for duplicate contacts with different JIDs). Moves all messages from source to target chat and deletes the source. Use this to consolidate chats when the same person appears as both @lid and @s.whatsapp.net JIDs.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "source_jid" => %{
              "type" => "string",
              "description" => "JID of chat to merge FROM (will be deleted after merge)"
            },
            "target_jid" => %{
              "type" => "string",
              "description" => "JID of chat to merge INTO (will contain all messages)"
            }
          },
          "required" => ["source_jid", "target_jid"]
        }
      },
      %{
        "name" => "update_group_name",
        "description" =>
          "Update the name of a WhatsApp group. Only group admins can update the name. Group names are limited to 25 characters.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "jid" => %{
              "type" => "string",
              "description" => "The group JID (must end with @g.us)"
            },
            "name" => %{
              "type" => "string",
              "description" => "The new group name (max 25 characters)"
            }
          },
          "required" => ["jid", "name"]
        }
      },
      %{
        "name" => "update_group_description",
        "description" =>
          "Update the description/topic of a WhatsApp group. Only group admins can update the description. Use an empty string to clear the description.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "jid" => %{
              "type" => "string",
              "description" => "The group JID (must end with @g.us)"
            },
            "description" => %{
              "type" => "string",
              "description" => "The new group description (empty string to clear)"
            }
          },
          "required" => ["jid", "description"]
        }
      },
      %{
        "name" => "update_group_settings",
        "description" =>
          "Update group settings. 'locked' controls whether only admins can edit group info. 'announce' controls whether only admins can send messages (broadcast mode). At least one setting must be specified.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "jid" => %{
              "type" => "string",
              "description" => "The group JID (must end with @g.us)"
            },
            "locked" => %{
              "type" => "boolean",
              "description" => "If true, only admins can edit group info. If false, all members can edit."
            },
            "announce" => %{
              "type" => "boolean",
              "description" => "If true, only admins can send messages (broadcast mode). If false, all members can send."
            }
          },
          "required" => ["jid"]
        }
      },
      %{
        "name" => "manage_group_members",
        "description" =>
          "Add, remove, promote, or demote group members. Only group admins can perform these actions. Action must be one of: 'add', 'remove', 'promote', 'demote'.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "jid" => %{
              "type" => "string",
              "description" => "The group JID (must end with @g.us)"
            },
            "participants" => %{
              "type" => "array",
              "items" => %{"type" => "string"},
              "description" => "List of participant JIDs to modify (e.g., ['12025551234@s.whatsapp.net'])"
            },
            "action" => %{
              "type" => "string",
              "description" => "The action to perform",
              "enum" => ["add", "remove", "promote", "demote"]
            }
          },
          "required" => ["jid", "participants", "action"]
        }
      },
      %{
        "name" => "get_privacy_settings",
        "description" =>
          "Get your WhatsApp privacy settings. Returns settings for who can see your last seen, profile photo, about, online status, and who can add you to groups or call you.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{}
        }
      },
      %{
        "name" => "set_privacy_setting",
        "description" =>
          "Update a WhatsApp privacy setting. Settings: 'groupadd' (who can add to groups), 'last' (last seen), 'status' (about/status), 'profile' (profile photo), 'readreceipts' (read receipts), 'online' (online status), 'calladd' (who can call). Values: 'all', 'contacts', 'contact_blacklist', 'match_last_seen', 'known', 'none'. Not all values work for all settings.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "setting" => %{
              "type" => "string",
              "description" => "The setting to update",
              "enum" => ["groupadd", "last", "status", "profile", "readreceipts", "online", "calladd"]
            },
            "value" => %{
              "type" => "string",
              "description" =>
                "The new value. Valid options depend on setting: most accept 'all', 'contacts', 'contact_blacklist', 'none'. 'readreceipts' only accepts 'all' or 'none'. 'online' accepts 'all' or 'match_last_seen'. 'calladd' accepts 'all' or 'known'.",
              "enum" => ["all", "contacts", "contact_blacklist", "match_last_seen", "known", "none"]
            }
          },
          "required" => ["setting", "value"]
        }
      },
      %{
        "name" => "get_business_profile",
        "description" =>
          "Get the business profile for a WhatsApp Business contact. Returns business details including address, email, categories, and operating hours if the contact is a business account.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "jid" => %{
              "type" => "string",
              "description" => "The contact JID (e.g., '12025551234@s.whatsapp.net')"
            }
          },
          "required" => ["jid"]
        }
      },
      %{
        "name" => "reject_call",
        "description" =>
          "Reject an incoming WhatsApp call. Use this in response to a call event to decline a call programmatically.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "call_from" => %{
              "type" => "string",
              "description" => "The JID of the caller"
            },
            "call_id" => %{
              "type" => "string",
              "description" => "The call ID (from the call event)"
            }
          },
          "required" => ["call_from", "call_id"]
        }
      },
      %{
        "name" => "list_newsletters",
        "description" =>
          "List all subscribed WhatsApp channels (newsletters). Returns channel JIDs, names, descriptions, subscriber counts, and invite links.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{}
        }
      },
      %{
        "name" => "get_newsletter_info",
        "description" =>
          "Get detailed info about a specific WhatsApp channel. Returns name, description, subscriber count, and invite link.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "jid" => %{
              "type" => "string",
              "description" => "The newsletter JID (ends with @newsletter)"
            }
          },
          "required" => ["jid"]
        }
      },
      %{
        "name" => "get_newsletter_messages",
        "description" =>
          "Get recent messages from a WhatsApp channel. Returns message text, timestamps, view counts, and media types.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "jid" => %{
              "type" => "string",
              "description" => "The newsletter JID (ends with @newsletter)"
            },
            "count" => %{
              "type" => "integer",
              "description" => "Number of messages to fetch (default: 50)"
            },
            "before" => %{
              "type" => "integer",
              "description" => "Server ID to fetch messages before (for pagination)"
            }
          },
          "required" => ["jid"]
        }
      },
      %{
        "name" => "follow_newsletter",
        "description" =>
          "Subscribe to a WhatsApp channel (newsletter). After following, you'll receive updates and can read messages.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "jid" => %{
              "type" => "string",
              "description" => "The newsletter JID (ends with @newsletter)"
            }
          },
          "required" => ["jid"]
        }
      },
      %{
        "name" => "unfollow_newsletter",
        "description" =>
          "Unsubscribe from a WhatsApp channel (newsletter). You will no longer receive updates from the channel.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "jid" => %{
              "type" => "string",
              "description" => "The newsletter JID (ends with @newsletter)"
            }
          },
          "required" => ["jid"]
        }
      }
    ]
  end
end
