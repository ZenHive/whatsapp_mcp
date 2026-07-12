# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added

- **Lazy Tool Discovery Pattern**: Reduced MCP token overhead by ~90% by exposing only 3 wrapper tools (`tool_list`, `tool_get`, `tool_call`) instead of 50+ full tool schemas. Tools are now accessed on-demand via `tool_call("tool_name", {args})`.
- Store LID→phone number mappings from WhatsApp history sync for better contact resolution
- Request full history sync with group history support (~13k messages synced vs ~580 before)

### Changed

- Consolidate duplicate bridge error handling in Formatters module into single `format_bridge_error/1` helper (162 lines removed, ~11% reduction)
- Remove message content from bridge logs for privacy (now shows `[text]` or `[image]` instead)
- Remove verbose contact/group name lookup logs for cleaner output
- Improve history sync logging with sync type, progress percentage, and summary counts

### Fixed

- Fix files sent via `send_file` appearing as "unnamed" to recipients. The `FileName` field was not being set on `DocumentMessage`, only `Title`. Now both fields are set correctly.

## Roadmap History

Phase-level summaries for fully-shipped roadmap phases, backfilled from the retired `roadmap.md` during migration to `rmap` (`roadmap/tasks.toml`). Full per-task detail (body, acceptance criteria, files touched) is preserved in `tasks.toml` — query it with `rmap show <id>`. These sections exist so `ROADMAP.md`'s per-phase task tables (collapsed once a phase is `done`) have somewhere to link.

## Phase 1: Foundation

Added the Req HTTP client and switched the database layer to read from the Go bridge's `messages.db` (chats/messages schema), plus the `WhatsappMcp.Bridge` HTTP client module (send/download/health-check).

## Phase 2: Send Features

Added `send_message`, `send_file`, and `send_audio_message` MCP tools (text, image/video/document, and voice-note sending via the Go bridge).

## Phase 3: Media Download

Added the `download_media` MCP tool for downloading images, videos, and documents from messages.

## Phase 4: Enhanced Query Features

Added `search_contacts`, `get_chat`, `get_direct_chat_by_contact`, `get_message_context`, pagination for `list_chats`/`get_messages`, and `get_last_interaction`/`get_contact_chats`.

## Phase 5: Polish & Testing

Added the initial integration test suite (bridge/database/tools, Req.Test mocking, ~87% coverage) and brought README/CLAUDE.md docs and `@doc`/`@moduledoc` coverage up to date, including the `get_help` tool.

## Phase 6: Bridge Health & AI-Friendliness

Optimized MCP tool outputs for AI consumption: a bridge `/api/health` endpoint and `get_bridge_status` tool, message IDs and media indicators on `search_messages`, pagination totals across all list tools, actionable "next step" hints on tool outputs, standardized `JID:` field naming, expanded test coverage for all of the above, and a code-review pass (Server/CLI test coverage, SQL-safety documentation, timestamp edge cases, `search_messages` offset pagination).

## Phase 7: Contact Resolution & UX

Split the growing `tools.ex`/`database.ex` modules into focused submodules, then added `@lid`-to-phone-number resolution (cached in a new `contacts` SQLite table), contact name enrichment so `@lid` chats show real names, and human-readable timestamps in chat/message output.

## Phase 8: Messaging Features

Added typing indicators (`send_typing`), read receipts (`mark_read`), quote-replies (`reply_to_message`), and emoji reactions (`react_to_message`).

## Phase 9: Advanced Features (Lower Priority)

Added message deletion, location messages, and automatic bridge reconnection with exponential backoff. Also explored (Task 36) and then reverted (Task 37) an auto-start-bridge-with-QR-capture approach in favor of the simpler manual `go run .` startup, after race conditions and PID-locking issues across concurrent Claude Code sessions.

## Phase 10: Quick Wins (from AI Testing Feedback)

Small AI-testing-driven improvements: an `after` timestamp parameter on `get_messages`, message counts on `get_chat`, a `has_media` filter on `search_messages`, contact names in `get_message_context`, and improved `get_last_interaction`/`get_chat_by_name` contact-name resolution.

## Phase 11: Whatsmeow Feature Expansion

Exposed further whatsmeow capabilities not yet surfaced via MCP: contact/user tools (`is_on_whatsapp`, profile pictures, blocklist), presence and disappearing messages, message editing, full group management (reading, invite links, lifecycle, admin operations — split into Tasks 41a-41d), polls, newsletters/channels, privacy and business-profile tools, and a unified message view that merges `@lid`/`@s.whatsapp.net` duplicate contact threads.
