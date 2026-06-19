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
