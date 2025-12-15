# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added

- Store LID→phone number mappings from WhatsApp history sync for better contact resolution
- Request full history sync with group history support (requires re-pairing to take effect)

### Changed

- Remove message content from bridge logs for privacy (now shows `[text]` or `[image]` instead)
- Remove verbose contact/group name lookup logs for cleaner output
- Improve history sync logging with sync type, progress percentage, and summary counts

### Fixed

- Fix files sent via `send_file` appearing as "unnamed" to recipients. The `FileName` field was not being set on `DocumentMessage`, only `Title`. Now both fields are set correctly.
