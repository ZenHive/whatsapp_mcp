# Elixir MCP Server Refactoring Roadmap

This roadmap breaks down the refactoring of large Elixir files in `lib/whatsapp_mcp/` into manageable, incremental tasks.

## Current State Analysis

### Problem Areas

| File | Lines | Functions | Problem |
|------|-------|-----------|---------|
| `bridge.ex` | 2,116 | 174 | 132 repetitive response handlers |
| `tools/formatters.ex` | 1,506 | 204 | 127 public format functions |
| `tools/definitions.ex` | 995 | 1 | Single 995-line data structure |
| `tools/handlers.ex` | 926 | 163 | 89 `call_tool/2` clauses |
| `database/messages.ex` | 586 | 17 | 82-line function, duplicated JID resolution |
| `database/chats.ex` | 515 | 16 | Duplicated JID resolution patterns |
| `database/contacts.ex` | 482 | 16 | Duplicated JID resolution patterns |

### Target Structure

```
lib/whatsapp_mcp/
├── application.ex           # OTP Application supervisor (~15 lines) ✓
├── cli.ex                   # Escript entry point (~23 lines) ✓
├── config.ex                # Paths and configuration (~73 lines) ✓
├── server.ex                # MCP protocol GenServer (~186 lines) ✓
├── tools.ex                 # Tool dispatcher (~36 lines) ✓
├── bridge/
│   ├── bridge.ex            # Core HTTP client + public API (~500 lines)
│   └── responses.ex         # Response handlers (~600 lines)
├── database/
│   ├── database.ex          # Supervisor (~64 lines) ✓
│   ├── helpers.ex           # SQL utilities (~220 lines) ✓
│   ├── jid_resolver.ex      # NEW: Centralized JID↔LID resolution (~200 lines)
│   ├── chats.ex             # Chat queries (~350 lines)
│   ├── contacts.ex          # Contact queries (~300 lines)
│   └── messages.ex          # Message queries (~400 lines)
└── tools/
    ├── definitions/
    │   ├── definitions.ex   # Entry point, list_tools/0 (~50 lines)
    │   ├── reading.ex       # Read tool definitions (~150 lines)
    │   ├── writing.ex       # Write tool definitions (~150 lines)
    │   ├── groups.ex        # Group tool definitions (~150 lines)
    │   ├── newsletters.ex   # Newsletter tool definitions (~100 lines)
    │   └── privacy.ex       # Privacy/business tool definitions (~100 lines)
    ├── handlers/
    │   ├── handlers.ex      # Dispatcher + shared helpers (~100 lines)
    │   ├── reading.ex       # Read handlers (~200 lines)
    │   ├── writing.ex       # Write handlers (~200 lines)
    │   ├── groups.ex        # Group handlers (~200 lines)
    │   └── newsletters.ex   # Newsletter handlers (~150 lines)
    └── formatters/
        ├── formatters.ex    # Entry point + shared helpers (~100 lines)
        ├── chat.ex          # Chat formatters (~200 lines)
        ├── message.ex       # Message formatters (~300 lines)
        ├── group.ex         # Group formatters (~200 lines)
        └── help.ex          # help_text/0 (~150 lines)
```

---

## Phase 1: Extract JID Resolution (Cross-Cutting)

### Task 1: Create JidResolver Module
- [ ] **Pending** [D:2/B:8 → Priority:4.0] 🎯

**Goal:** Centralize phone↔LID JID resolution logic currently duplicated across database modules.

**Duplicated patterns to extract:**
```elixir
# Found in messages.ex, chats.ex, contacts.ex
get_phone_jid_for_lid/2
get_lid_for_phone_jid/2
find_phone_jid_from_lid/2
find_lid_by_phone/2
```

**Files to create:**
- `lib/whatsapp_mcp/database/jid_resolver.ex`

**Files to modify:**
- `lib/whatsapp_mcp/database/messages.ex` - Remove JID resolution, use JidResolver
- `lib/whatsapp_mcp/database/chats.ex` - Remove JID resolution, use JidResolver
- `lib/whatsapp_mcp/database/contacts.ex` - Remove JID resolution, use JidResolver

**Acceptance criteria:**
- [ ] All JID resolution in `jid_resolver.ex`
- [ ] Database modules delegate to JidResolver
- [ ] `mix test` passes
- [ ] `mix compile` clean

---

## Phase 2: Split Formatters (Highest Impact)

### Task 2: Extract Help Text
- [ ] **Pending** [D:1/B:6 → Priority:6.0] 🎯

**Goal:** Move 130-line `help_text/0` function to dedicated file.

**Code to extract:**
```elixir
def help_text do
  # 130 lines of static text
end
```

**Files to create:**
- `lib/whatsapp_mcp/tools/formatters/help.ex`

**Acceptance criteria:**
- [ ] `help_text/0` in dedicated module
- [ ] `mix test` passes

---

### Task 3: Split Formatters by Domain
- [ ] **Pending** [D:3/B:9 → Priority:3.0] 🎯

**Goal:** Split `formatters.ex` (1,506 lines) into domain-specific modules.

**Proposed split:**

| New Module | Functions | Est. Lines |
|------------|-----------|------------|
| `Formatters.Chat` | `format_chat_result/1`, `format_chats_result/1`, chat-related | ~200 |
| `Formatters.Message` | `format_message/1`, `format_messages_result/1`, message-related | ~300 |
| `Formatters.Group` | `format_group_info/1`, `format_groups_list/1`, group-related | ~200 |
| `Formatters.Newsletter` | `format_newsletter_info/1`, newsletter-related | ~150 |
| `Formatters` | Entry point, shared helpers, delegations | ~100 |

**Files to create:**
- `lib/whatsapp_mcp/tools/formatters/chat.ex`
- `lib/whatsapp_mcp/tools/formatters/message.ex`
- `lib/whatsapp_mcp/tools/formatters/group.ex`
- `lib/whatsapp_mcp/tools/formatters/newsletter.ex`

**Files to modify:**
- `lib/whatsapp_mcp/tools/formatters.ex` - Delegate to submodules

**Acceptance criteria:**
- [ ] formatters.ex under 200 lines
- [ ] Each submodule under 350 lines
- [ ] `mix test` passes

---

## Phase 3: Split Handlers

### Task 4: Convert Handlers to Dispatch Map
- [ ] **Pending** [D:3/B:7 → Priority:2.3] 🚀

**Goal:** Replace 89 `call_tool/2` function clauses with a dispatch map.

**Current pattern (926 lines):**
```elixir
def call_tool("list_chats", params), do: handle_list_chats(params)
def call_tool("get_messages", params), do: handle_get_messages(params)
def call_tool("send_message", params), do: handle_send_message(params)
# ... 86 more clauses
```

**New pattern:**
```elixir
@tool_handlers %{
  "list_chats" => &handle_list_chats/1,
  "get_messages" => &handle_get_messages/1,
  "send_message" => &handle_send_message/1,
  # ...
}

def call_tool(tool_name, params) do
  case Map.get(@tool_handlers, tool_name) do
    nil -> {:error, "Unknown tool: #{tool_name}"}
    handler -> handler.(params)
  end
end
```

**Files to modify:**
- `lib/whatsapp_mcp/tools/handlers.ex`

**Acceptance criteria:**
- [ ] Single `call_tool/2` function
- [ ] Dispatch via map lookup
- [ ] `mix test` passes

---

### Task 5: Split Handlers by Domain
- [ ] **Pending** [D:3/B:6 → Priority:2.0] 🚀

**Goal:** Split handler implementations into domain-specific modules.

**Proposed split:**

| New Module | Handlers | Est. Lines |
|------------|----------|------------|
| `Handlers.Reading` | list_chats, get_messages, search_*, get_* | ~250 |
| `Handlers.Writing` | send_message, send_file, send_audio, download_media, create_poll | ~200 |
| `Handlers.Groups` | list_groups, get_group_info, manage_group_members, etc. | ~250 |
| `Handlers.Newsletters` | list_newsletters, get_newsletter_info, follow/unfollow | ~150 |
| `Handlers` | Dispatcher, shared helpers | ~150 |

**Files to create:**
- `lib/whatsapp_mcp/tools/handlers/reading.ex`
- `lib/whatsapp_mcp/tools/handlers/writing.ex`
- `lib/whatsapp_mcp/tools/handlers/groups.ex`
- `lib/whatsapp_mcp/tools/handlers/newsletters.ex`

**Acceptance criteria:**
- [ ] handlers.ex under 200 lines
- [ ] Each submodule under 300 lines
- [ ] `mix test` passes

---

## Phase 4: Split Definitions

### Task 6: Split Tool Definitions by Domain
- [ ] **Pending** [D:2/B:5 → Priority:2.5] 🎯

**Goal:** Split `definitions.ex` (995 lines) into domain-specific modules.

**Current structure:**
```elixir
def list_tools do
  [
    # 51 tool definitions, ~20 lines each
  ]
end
```

**New structure:**
```elixir
# definitions.ex
def list_tools do
  Definitions.Reading.tools() ++
  Definitions.Writing.tools() ++
  Definitions.Groups.tools() ++
  Definitions.Newsletters.tools() ++
  Definitions.Privacy.tools()
end
```

**Files to create:**
- `lib/whatsapp_mcp/tools/definitions/reading.ex`
- `lib/whatsapp_mcp/tools/definitions/writing.ex`
- `lib/whatsapp_mcp/tools/definitions/groups.ex`
- `lib/whatsapp_mcp/tools/definitions/newsletters.ex`
- `lib/whatsapp_mcp/tools/definitions/privacy.ex`

**Acceptance criteria:**
- [ ] definitions.ex under 100 lines
- [ ] Each submodule contains related tools only
- [ ] `mix test` passes

---

## Phase 5: Extract Bridge Response Handlers

### Task 7: Extract Response Handlers from Bridge
- [ ] **Pending** [D:4/B:7 → Priority:1.75] 🚀

**Goal:** Extract 132 repetitive `handle_*_response/1` functions from `bridge.ex`.

**Current pattern (2,116 lines):**
```elixir
# 132 handlers like:
defp handle_list_chats_response({:ok, %{status: 200, body: body}}) do
  {:ok, body}
end
defp handle_list_chats_response({:ok, %{status: status, body: body}}) do
  {:error, "HTTP #{status}: #{inspect(body)}"}
end
defp handle_list_chats_response({:error, reason}) do
  {:error, "Request failed: #{inspect(reason)}"}
end
```

**Refactoring approach:**
```elixir
# Generic response handler
defp handle_response({:ok, %{status: 200, body: body}}), do: {:ok, body}
defp handle_response({:ok, %{status: status, body: body}}), do: {:error, "HTTP #{status}: #{inspect(body)}"}
defp handle_response({:error, reason}), do: {:error, "Request failed: #{inspect(reason)}"}
```

**Files to modify:**
- `lib/whatsapp_mcp/bridge.ex` - Replace 132 handlers with 1 generic handler

**Acceptance criteria:**
- [ ] Single generic `handle_response/1` function
- [ ] bridge.ex under 800 lines
- [ ] `mix test` passes

---

## Phase 6: Simplify Database Modules

### Task 8: Extract Long Function in messages.ex
- [ ] **Pending** [D:2/B:4 → Priority:2.0] 🚀

**Goal:** Refactor `do_get_message_context/4` (82 lines) into smaller functions.

**Files to modify:**
- `lib/whatsapp_mcp/database/messages.ex`

**Acceptance criteria:**
- [ ] No function over 40 lines
- [ ] messages.ex under 450 lines
- [ ] `mix test` passes

---

## Summary

| Phase | Tasks | Status | Impact |
|-------|-------|--------|--------|
| 1. JID Resolution | 1 | ⏳ Pending | Removes duplication across 3 files |
| 2. Formatters | 2-3 | ⏳ Pending | 1,506 → ~1,000 lines split across 5 files |
| 3. Handlers | 4-5 | ⏳ Pending | 926 → ~1,000 lines split across 5 files |
| 4. Definitions | 6 | ⏳ Pending | 995 → ~700 lines split across 6 files |
| 5. Bridge | 7 | ⏳ Pending | 2,116 → ~800 lines |
| 6. Database | 8 | ⏳ Pending | messages.ex: 586 → ~450 lines |

### Priority Order (by D/B ratio)

| Priority | Task | Description | D/B/P |
|----------|------|-------------|-------|
| 1 | 2 | Extract help_text/0 | 1/6/6.0 |
| 2 | 1 | Create JidResolver module | 2/8/4.0 |
| 3 | 3 | Split formatters by domain | 3/9/3.0 |
| 4 | 6 | Split definitions by domain | 2/5/2.5 |
| 5 | 4 | Convert handlers to dispatch map | 3/7/2.3 |
| 6 | 5 | Split handlers by domain | 3/6/2.0 |
| 7 | 8 | Extract long function in messages.ex | 2/4/2.0 |
| 8 | 7 | Extract bridge response handlers | 4/7/1.75 |

**Total: 8 tasks**

---

## Well-Sized Modules (No Action Needed)

| File | Lines | Functions | Status |
|------|-------|-----------|--------|
| `database/helpers.ex` | 220 | 15 | ✓ Good |
| `server.ex` | 186 | 16 | ✓ Good |
| `config.ex` | 73 | - | ✓ Good |
| `database.ex` | 64 | - | ✓ Good |
| `tools.ex` | 36 | - | ✓ Good |
| `cli.ex` | 23 | - | ✓ Good |
| `application.ex` | 15 | - | ✓ Good |
