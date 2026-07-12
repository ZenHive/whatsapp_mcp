# WhatsApp MCP Server - Feature Roadmap

This roadmap extends the Elixir MCP server to integrate with the Go WhatsApp bridge, enabling full read/write capabilities.

Managed via `rmap` — `roadmap/tasks.toml` is the canonical source; this file is rendered. Don't hand-edit the task tables between the `TASKS:BEGIN`/`TASKS:END` marker pairs.

## Prerequisites

Before starting, ensure the Go bridge is set up:
```bash
cd bridge
go run .
# Scan QR code with WhatsApp mobile app
# Bridge runs on http://localhost:8080
```

## Project Structure

```
whatsapp_mcp/
├── lib/                    # Elixir MCP server
├── bridge/                 # Go WhatsApp bridge
│   ├── main.go
│   ├── go.mod
│   └── store/              # SQLite databases (messages.db)
├── mix.exs
├── roadmap/                # rmap source (tasks.toml, data.json)
└── README.md
```

---

## Test Strategy

All new modules follow a **two-tier testing approach**:

### 1. Unit Tests with Req.Test (Default)
- Use [Req.Test](https://hexdocs.pm/req/Req.Test.html) (built into Req, no extra deps)
- Fast, deterministic, run without Go bridge
- Test all success paths and error scenarios
- Supports stubs, expects, and transport error simulation
- Run with: `mix test`

### 2. Integration Tests (Tagged)
- Test against real Go bridge
- Verify actual API behavior and catch drift
- Tag with `@moduletag :integration`
- Run with: `mix test --include integration`

### Test Coverage Requirements
| Module | Unit Tests | Integration Tests |
|--------|-----------|-------------------|
| `Bridge` | HTTP mocking with Req.Test | Real send/download |
| `Database` | Mock SQLite DB | Real messages.db |
| `Tools` | Mock Bridge + DB | Full E2E with bridge |

### Req.Test Example
```elixir
# Setup stub for bridge API
Req.Test.stub(:bridge, fn conn ->
  Req.Test.json(conn, %{success: true, message: "Message sent"})
end)

# Bridge module uses plug: {Req.Test, :bridge} in test mode
```

---

## Phase 1: Foundation

<!-- TASKS:BEGIN phase=1 -->
> 2 tasks. See [CHANGELOG.md](CHANGELOG.md#phase-1-foundation).
<!-- TASKS:END -->

---

## Phase 2: Send Features

<!-- TASKS:BEGIN phase=2 -->
> 3 tasks. See [CHANGELOG.md](CHANGELOG.md#phase-2-send-features).
<!-- TASKS:END -->

---

## Phase 3: Media Download

<!-- TASKS:BEGIN phase=3 -->
> 1 task. See [CHANGELOG.md](CHANGELOG.md#phase-3-media-download).
<!-- TASKS:END -->

---

## Phase 4: Enhanced Query Features

<!-- TASKS:BEGIN phase=4 -->
> 5 tasks. See [CHANGELOG.md](CHANGELOG.md#phase-4-enhanced-query-features).
<!-- TASKS:END -->

---

## Phase 5: Polish & Testing

<!-- TASKS:BEGIN phase=5 -->
> 2 tasks. See [CHANGELOG.md](CHANGELOG.md#phase-5-polish-testing).
<!-- TASKS:END -->

---

## Phase 6: Bridge Health & AI-Friendliness

These tasks add operational visibility and optimize MCP tool outputs for AI consumption.

<!-- TASKS:BEGIN phase=6 -->
> 7 tasks. See [CHANGELOG.md](CHANGELOG.md#phase-6-bridge-health-ai-friendliness).
<!-- TASKS:END -->

---

## Phase 7: Contact Resolution & UX

**Why this phase matters:** WhatsApp's newer `@lid` format breaks phone-based contact search, making it hard for users to find people. These tasks restore phone lookup and ensure all contacts display readable names instead of cryptic IDs.

<!-- TASKS:BEGIN phase=7 -->
> 4 tasks. See [CHANGELOG.md](CHANGELOG.md#phase-7-contact-resolution-ux).
<!-- TASKS:END -->

---

## Phase 8: Messaging Features

**Why this phase matters:** These features make AI-powered messaging feel more natural and human-like. Typing indicators, read receipts, and replies help maintain social context in automated interactions.

<!-- TASKS:BEGIN phase=8 -->
> 4 tasks. See [CHANGELOG.md](CHANGELOG.md#phase-8-messaging-features).
<!-- TASKS:END -->

---

## Phase 9: Advanced Features (Lower Priority)

**Why this phase matters:** Power-user features for complete WhatsApp control. Lower priority because the core use case (AI assistant messaging) works without them.

<!-- TASKS:BEGIN phase=9 -->
> 5 tasks. See [CHANGELOG.md](CHANGELOG.md#phase-9-advanced-features-lower-priority).
<!-- TASKS:END -->

---

## Phase 10: Quick Wins (from AI Testing Feedback)

These tasks were identified from AI testing of the MCP tools.

<!-- TASKS:BEGIN phase=10 -->
> 5 tasks. See [CHANGELOG.md](CHANGELOG.md#phase-10-quick-wins-from-ai-testing-feedback).
<!-- TASKS:END -->

---

## Phase 11: Whatsmeow Feature Expansion

Features supported by whatsmeow but not yet exposed. See [whatsmeow docs](https://pkg.go.dev/go.mau.fi/whatsmeow).

Task 41 ("Group Management") was split into sub-tasks 41a-41d (read, invite links, lifecycle, admin ops) rather than shipped as one task.

<!-- TASKS:BEGIN phase=11 -->
> 11 tasks. See [CHANGELOG.md](CHANGELOG.md#phase-11-whatsmeow-feature-expansion).
<!-- TASKS:END -->

---

## Phase 12: Architecture & Developer Experience

<!-- TASKS:BEGIN phase=12 -->
| Task | Status | Notes |
|------|--------|-------|
| Task 46 | 🔶 | 🎁 **architecture** · Tool Definition DSL (Macro Refactor) [D:5/B:5/U:5 → Eff:1.0?] 📋 ⛔ Deferred until needed: current explicit code (47 tools) is repetitive but clear/debuggable, ~27% LOC reduction doesn't justify macro complexity yet. Revisit if: building a REST/GraphQL interface, tool count exceeds 75+, or extracting as a reusable library for other MCP projects. |
| Task 47 | ✅ | 🎁 **architecture** · Manual Chat Merge for Unresolved LID Contacts [D:3/B:7/U:7 → Eff:2.33?] 🎯 |
| Task 48 | ✅ | 🎁 **architecture** · Expose Contacts Store [D:2/B:8/U:8 → Eff:4.0?] 🎯 |
| Task 49 | ✅ | 🎁 **architecture** · Go Bridge Refactoring [D:4/B:8/U:8 → Eff:2.0?] 🎯 |
<!-- TASKS:END -->

---

## Known Limitations

### On-Demand History Sync (Not Supported)

**Problem:** Message history doesn't sync until a contact sends a new message or the bridge is rebooted. Users expected to request older messages on demand.

**Attempted Solution:** Use whatsmeow's `BuildHistorySyncRequest` to request history for sparse chats.

**Result:** ❌ Does not work. WhatsApp's protocol does not support on-demand history requests.

**Evidence:**
- [tulir/whatsmeow#654](https://github.com/tulir/whatsmeow/issues/654) - "Requesting historical messages fail" - closed as "not planned"
- [tulir/whatsmeow#422](https://github.com/tulir/whatsmeow/discussions/422) - "The conversations are pushed by the server during logon. As far as I know, there is no way to request more data for a specific conversation. Even the official WhatsApp Web interface has the same limitation: It shows a message 'Use WhatsApp on your phone to see earlier messages'."

**Workaround:** Delete `bridge/store/` and re-scan QR code to get fresh history dump (limited to what WhatsApp sends during initial sync).

**Code preserved:** `feature/history-sync-request` branch contains the implementation for future reference if WhatsApp/whatsmeow adds support.
