# AI Memory Chat — Project Documentation


ENGLISH/[中文](README.md).

> A Flutter-based OpenAI-compatible AI chat application featuring a three-tier memory system, multi-agent group chat, unified agent sidebar, Material 3 theme, and strict tool calling mechanisms.

> [!WARNING]
> This software was developed with AI programming assistance. If you are allergic to AI programming, please do not use it.

---

## Table of Contents

1. [Project Overview](#project-overview)
2. [Architecture Overview](#architecture-overview)
3. [Tool System](#tool-system)
4. [System Prompt](#system-prompt)
5. [Three-tier Memory System](#three-tier-memory-system)
6. [Group Chat System](#group-chat-system)
7. [API Service Layer](#api-service-layer)
8. [Provider Management](#provider-management)
9. [Configuration Import & Export](#configuration-import--export)
10. [Multilingual Support](#multilingual-support)
11. [Core Code File Index](#core-code-file-index)

---

## Project Overview

**Tech Stack**: Flutter 3.x + Dart + Riverpod + sqflite + shared_preferences + AES encryption + Material 3  
**Target Platforms**: Android / iOS  
**Core Capabilities**:
- OpenAI-compatible API calls (chat + vision)
- Mandatory tool calls (`tool_choice: required`)
- Three-tier memory + group-shared memory
- Multi-agent (Agent) and group chat
- Per-agent configurable opening line
- Unified sidebar for all conversation targets (agents / groups)
- Proactive care, planned messages, local notifications
- Multi-provider switching, token usage statistics and charts
- Plugin system (experimental)
- Chinese-English bilingual localization (120+ key-value pairs)
- Material 3 design theme (`AppTheme`)

---

## Architecture Overview

```
lib/
├── main.dart                       # Entry: MaterialApp, ProviderScope, theme/locale/notification init
├── theme/
│   └── app_theme.dart              # Material 3 design tokens: spacing, radii, shadows, ThemeData
├── l10n/
│   └── app_localizations.dart      # Chinese-English bilingual localization (120+ key-value pairs)
├── utils/
│   └── responsive_layout.dart      # Responsive layout helpers (breakpoints, scaling)
├── services/
│   ├── api_service.dart            # HTTP requests, tool definitions, vision API, error handling
│   ├── memory_service.dart         # Three-tier memory CRUD + prompt generation
│   ├── tool_executor.dart          # Executor for 5 tools
│   ├── model_service.dart          # Fetch and filter model list from /v1/models
│   ├── database_service.dart       # sqflite database (v9, 14 tables) + backup & restore
│   ├── encryption_service.dart     # AES-CBC encryption of API keys
│   ├── notification_service.dart   # Local notifications (planned messages + proactive care)
│   ├── plan_service.dart           # Planned message scheduling
│   ├── locale_service.dart         # IP language detection + preference persistence
│   ├── group_service.dart          # Group chat and shared memory CRUD
│   ├── agent_export_service.dart   # Agent JSON import/export (avatar/background as base64)
│   └── plugin_manager.dart         # Plugin system manager (experimental)
├── providers/
│   ├── chat_provider.dart          # Chat state, tool loop, system prompt, token accumulation
│   ├── settings_provider.dart      # Provider CRUD, theme color, token accumulation, config serialization
│   ├── memory_provider.dart        # Riverpod state for long-term/base/shared memory
│   ├── group_provider.dart         # Group, member, and group message state
│   ├── plan_provider.dart          # Riverpod state for planned messages
│   └── agent_provider.dart         # Riverpod state for agents (used by the sidebar)
├── models/
│   ├── agent.dart                  # Agent (includes opening_line, avatar, chat_background)
│   ├── ai_agent.dart               # Legacy AI Agent (retained for compatibility)
│   ├── chat_message.dart           # Chat message (lightweight model)
│   ├── long_term_memory.dart       # Long-term memory (9 fields + agent_id + group_id)
│   ├── base_memory.dart            # Base memory (setting/event + agent_id + group_id)
│   ├── short_term_message.dart     # Short-term message (agent_id + group_id)
│   ├── planned_message.dart        # Planned message (agent_id + group_id)
│   ├── provider_config.dart        # Provider configuration
│   ├── group_chat.dart             # Group chat (name, description, persona, speech mode)
│   ├── group_member.dart           # Group member (role, presence)
│   ├── group_message.dart          # Group message (sender, tool call data)
│   └── group_shared_memory.dart    # Group shared memory (by field)
└── screens/
    ├── chat_screen.dart            # Main chat screen + debug log page
    ├── settings_screen.dart        # Settings (providers/theme/language/import-export)
    ├── memory_screen.dart          # Memory management (long-term/base/shared/planned)
    ├── plan_screen.dart            # Planned messages screen
    ├── token_usage_screen.dart     # Token usage chart screen
    ├── plugin_screen.dart          # Plugin management screen (experimental)
    ├── agent_list_screen.dart      # Agent sidebar list
    ├── agent_create_screen.dart    # Agent create/edit screen
    ├── group_list_screen.dart      # Group list
    ├── group_create_screen.dart    # Group creation screen
    ├── group_manage_screen.dart    # Group management (members/persona/mode)
    └── group_chat_screen.dart      # Group chat conversation screen
```

### Theme & Design System

`lib/theme/app_theme.dart` centrally manages all visual tokens:

- **Spacing**: `space1`~`space10` (4/8/12/16/20/24/32/40)
- **Radii**: `radiusSm`~`radiusXl`, `radiusFull` (8/12/16/20/999)
- **Shadows**: `shadowSm` / `shadowMd` / `shadowLg`
- **Animation durations**: `durationFast` / `durationNormal` / `durationSlow` (150/220/320ms)
- **Full ThemeData**: `light(primary)` / `dark(primary)` overrides for Card, Dialog, BottomSheet, Input, Button, Chip, ListTile, SnackBar, TabBar, Switch, Slider, etc.

The main entry enables the theme via `theme: AppTheme.light(primary), darkTheme: AppTheme.dark(primary)`.

---

## Tool System

Tools are defined through the OpenAI-compatible API's `tools` parameter. `ApiService.getToolDefinitions(isGroupChat: ...)` returns **two different tool sets** depending on the scenario.

### Private Chat Tools (4)

Private chat (with a single agent) uses the following 4 tools. Tool calls follow the `tool_choice: "required"` mandatory mode (DeepSeek models additionally receive `thinking: {type: "disabled"}` to disable thinking).

#### 1. remember — Create/Update Memory

**Purpose**: Persist personal information disclosed by the user into long-term or base memory.

**Parameter definition**:

```dart
{
  "type": "function",
  "function": {
    "name": "remember",
    "description": "Remember a current state or past event.",
    "parameters": {
      "type": "object",
      "properties": {
        "memory_type": {
          "type": "string",
          "enum": ["long_term", "base"],
          "description": "long_term = long-term memory; base = base memory (append historical event)"
        },
        "action": {
          "type": "string",
          "enum": ["create", "update"],
          "description": "create new, or update existing (requires target_id)"
        },
        "target_id": {
          "type": "string",
          "description": "Required when action=update, target entry ID (e.g. L003)"
        },
        "field": {
          "type": "string",
          "enum": ["time", "location", "current_events", "characters", "relationships", "goals", "thoughts", "status", "to_do"],
          "description": "Long-term memory field name; not needed for base type"
        },
        "content": {
          "type": "string",
          "description": "Memory content (full new content for update)"
        }
      },
      "required": ["memory_type", "action"]
    }
  }
}
```

#### 2. forget — Delete Memory

```dart
{
  "type": "function",
  "function": {
    "name": "forget",
    "description": "Delete entries that are no longer useful. Setting entries cannot be deleted.",
    "parameters": {
      "type": "object",
      "properties": {
        "target_ids": {
          "type": "array",
          "items": {"type": "string"},
          "description": "List of entry IDs, e.g. ['L003', 'B007']"
        }
      },
      "required": ["target_ids"]
    }
  }
}
```

#### 3. chat — Reply to User

```dart
{
  "type": "function",
  "function": {
    "name": "chat",
    "description": "Send a natural language reply to the user. Use this as the final reply after all memory operations.",
    "parameters": {
      "type": "object",
      "properties": {
        "message": {"type": "string", "description": "The text to send to the user"}
      },
      "required": ["message"]
    }
  }
}
```

#### 4. plan — Schedule a Planned Message

```dart
{
  "type": "function",
  "function": {
    "name": "plan",
    "description": "Schedule a message to be sent in the future.",
    "parameters": {
      "type": "object",
      "properties": {
        "send_time": {
          "type": "string",
          "description": "Relative time like '30m', '2h', or an ISO 8601 absolute time"
        },
        "message": {"type": "string", "description": "The message to send at the scheduled time"}
      },
      "required": ["send_time", "message"]
    }
  }
}
```

### Group Chat Tools (4)

Group chat uses a different tool set. **The key difference is the introduction of `group_scope` / `memory_source` to distinguish personal vs group-shared memory.**

| Tool | Private | Group | Difference |
|------|---------|-------|------------|
| remember | `_rememberTool` | `_rememberGroupTool` | Group version adds `group_scope: personal \| shared` |
| forget | `_forgetTool` | `_forgetGroupTool` | Group version adds `memory_source: personal \| shared` |
| chat | `_chatTool` | — | Private-only |
| chatgroup | — | `_chatgroupTool` | Group-only (sends into the group) |
| plan | `_planTool` | `_planGroupTool` | Group version targets group messages |

The LLM is called once per turn, but memory writes are routed by `group_scope` / `memory_source`:
- `long_term_memories` / `base_memories` (`agent_id = current Agent, group_id = NULL`)
- `group_shared_memories` (`group_id = current group`)

---

## System Prompt

The system prompt is the core of the memory system's operation. Through multi-layered instructions, it compels the AI to call memory tools before replying.

### Full Structure

```text
【Current Actual Time】2026-06-04 22:30 (Saturday)

{{PERSONA}}                             ← From base memory setting entries (or Agent.persona)

## Memory System (Internal)
1. Short-term memory: Original text of the last 20 conversation turns, managed automatically by the system
2. Long-term memory: Stores real-time information that still holds true (9 fields)
3. Base memory: Settings (setting) + Historical events (event)

## Memory Operation Principles
- Remember (remember): User reveals personal info → immediately create/update
- Let go (forget): Information becomes outdated → delete + optional archive

## Available Tools (Background)
remember / forget / chat / plan            ← Private
remember / forget / chatgroup / plan       ← Group

## Tool Call Iron Rules
- When names/relationships/traits are mentioned → remember
- When status/health/mood/thoughts are mentioned → remember
- When location/event/goal is mentioned → remember
- When past experiences/history is mentioned → remember(base)
- Outdated info → forget → remember → chat

【Highest Priority: Tool Call Rules】
- Before replying, must judge whether memory is needed
- When uncertain, better to record than to miss
- Example: "I have a friend named Lao Zhang" → must first remember

## Conversation Style
Strictly follow the persona while speaking, integrate memory information, never use robotic expressions

====

【Current Long-term Memory】（Organized by field, with serial numbers）
L001 [relationships] The user has a friend named Lao Zhang

【Current Base Memory】（Settings and significant events, with serial numbers）
B001 [setting] You are the user's personal AI companion named Xiaoyan...
```

### Opening Line

Each Agent carries an optional opening line in `agent.openingLine`. When a new conversation is opened (short-term memory is empty), `ChatProvider` inserts the opening line as the AI's first message at the top of the conversation — the AI's "first impression."

### Build Code (`chat_provider.dart`)

```dart
Future<String> _buildSystemPrompt() async {
  final now = DateTime.now();
  final timeStr = DateFormat('yyyy-MM-dd HH:mm').format(now);
  final weekStr = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'][now.weekday % 7];

  final baseMemories = _ref.read(baseProvider).memories;
  final personaLines = baseMemories.where((m) => m.isSetting).map((m) => m.content).join('\n');
  final persona = personaLines.isNotEmpty ? personaLines : defaultSystemPersona;

  final longTermPrompt = await _memoryService.buildLongTermPrompt();
  final basePrompt = await _memoryService.buildBasePrompt();

  var prompt = '''【Current Actual Time】$timeStr ($weekStr)

$persona

## Memory System (Internal)...
## Memory Operation Principles...
## Available Tools (Background)...
## Tool Call Iron Rules...
【Highest Priority: Tool Call Rules】...
## Conversation Style...
====

【Current Long-term Memory】
$longTermPrompt

【Current Base Memory】
$basePrompt''';

  // Proactive care: if user has been silent too long
  if (extraProactiveHint != null) {
    prompt += '\n\nThe user has been silent for $extraProactiveHint hours. Please proactively send a caring message.';
  }

  return prompt;
}
```

---

## Three-tier Memory System

### Short-term Memory

| Attribute | Value |
|-----------|-------|
| **Storage Table** | `short_term_messages` (private), `group_short_term` (group) |
| **ID Format** | `S001` ~ `S999` |
| **Capacity** | Default 20 turns (configurable) |
| **Content** | Original text of recent conversations (role + content + timestamp) |
| **Management** | Circular overwrite: oldest entries deleted when capacity exceeded |
| **Usage** | Directly injected into the API request `messages` array to provide conversation context |

### Long-term Memory

| Attribute | Value |
|-----------|-------|
| **Storage Table** | `long_term_memories` |
| **ID Format** | `L001` ~ `L999` |
| **Capacity** | Recommended ≤ 15 entries |
| **Fields** | `time`, `location`, `current_events`, `characters`, `relationships`, `goals`, `thoughts`, `status`, `to_do` |
| **Deduplication Logic** | If content exists for the same field → overwrite update; or `action=update` with `target_id` |

**SQL Schema**:

```sql
CREATE TABLE long_term_memories (
  id         TEXT PRIMARY KEY,
  field      TEXT NOT NULL,
  content    TEXT NOT NULL,
  agent_id   TEXT,
  group_id   TEXT,
  updated_at INTEGER NOT NULL,
  created_at INTEGER NOT NULL
);
```

### Base Memory

| Attribute | Value |
|-----------|-------|
| **Storage Table** | `base_memories` |
| **ID Format** | `B001` ~ `B999` |
| **Types** | `setting` (settings/persona), `event` (historical events) |
| **Characteristics** | `setting` entries are permanent and cannot be deleted; `event` used to archive outdated long-term memories |

```sql
CREATE TABLE base_memories (
  id         TEXT PRIMARY KEY,
  type       TEXT NOT NULL,     -- 'setting' or 'event'
  content    TEXT NOT NULL,
  agent_id   TEXT,
  group_id   TEXT,
  updated_at INTEGER NOT NULL,
  created_at INTEGER NOT NULL
);
```

### Scope Identifiers (agent_id / group_id)

All long-term/base memory tables carry `agent_id` and `group_id` (both nullable):
- `agent_id != null, group_id == null`: private chat memory
- `group_id != null`: group chat memory (`agent_id` can distinguish which Agent's personal entry within the group)

---

## Group Chat System

Group chat is a first-class peer to private chat, with its own conversation, memory, and tool set.

### Data Models

#### `group_chats`

```sql
CREATE TABLE group_chats (
  id            TEXT PRIMARY KEY,
  name          TEXT NOT NULL,
  description   TEXT DEFAULT '',
  avatar_color  INTEGER,
  group_persona TEXT,                    -- Group persona (overrides Agent's individual persona)
  speech_mode   TEXT DEFAULT 'free',     -- 'free' (everyone speaks) / 'round' (take turns)
  created_at    INTEGER NOT NULL,
  updated_at    INTEGER NOT NULL
);
```

#### `group_members`

```sql
CREATE TABLE group_members (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  group_id   TEXT NOT NULL,
  agent_id   TEXT NOT NULL,
  role       TEXT DEFAULT 'member',   -- 'owner' | 'moderator' | 'member'
  is_present INTEGER DEFAULT 1,        -- Whether present (affects @all broadcasts)
  joined_at  INTEGER
);
```

#### `group_messages`

```sql
CREATE TABLE group_messages (
  id             INTEGER PRIMARY KEY AUTOINCREMENT,
  group_id       TEXT NOT NULL,
  sender_type    TEXT NOT NULL,        -- 'user' | 'agent' | 'system'
  sender_id      TEXT,                 -- Agent.id (when agent)
  sender_name    TEXT,
  content        TEXT NOT NULL,
  timestamp      INTEGER,
  tool_call_data TEXT                  -- Raw tool call JSON (debug)
);
```

#### `group_shared_memories`

```sql
CREATE TABLE group_shared_memories (
  id         TEXT PRIMARY KEY,
  group_id   TEXT NOT NULL,
  field      TEXT NOT NULL,            -- One of the 9 long-term memory fields
  content    TEXT NOT NULL,
  updated_at INTEGER
);
```

### Group Message Flow

```
User input ──> GroupProvider
                │
                ├── Write group_messages (sender_type=user)
                ├── Read group_short_term into context
                ├── For each present Agent, serially call the API (private tool set + chatgroup)
                ├── Tool calls:
                │     remember(group_scope=shared) ─> group_shared_memories
                │     remember(group_scope=personal) ─> long_term_memories (agent_id=current)
                │     forget(memory_source=shared) ─> group_shared_memories
                │     chatgroup ─> write group_messages (sender_type=agent)
                └── After all complete, refresh UI
```

### Group Management

- **Group List** (`group_list_screen`): all group cards; tap to enter conversation, long-press to manage.
- **Create Group** (`group_create_screen`): pick Agent members (multi-select), color, persona (optional), speech mode.
- **Group Management** (`group_manage_screen`): edit name/description, adjust members (add/remove/role), edit persona, delete group.
- **Group Chat** (`group_chat_screen`): multi-bubble UI, @mentions, memory panel, stop generation.

### Speech Mode

- `free` (free speech): every Agent responds to each user input.
- `round` (turn-taking): Agents respond in `joined_at` order (UI supported in this version, logic controlled by `GroupProvider`).

---

## API Service Layer

### Tool Set Selection (`api_service.dart:319`)

```dart
static List<Map<String, dynamic>> getToolDefinitions({bool isGroupChat = false}) {
  if (isGroupChat) return _getGroupToolDefinitions();
  return _getPrivateToolDefinitions();
}
```

### Request Construction (Private)

```dart
Future<Map<String, dynamic>> chatCompletion({
  required List<Map<String, dynamic>> messages,
  required List<Map<String, dynamic>> tools,
}) async {
  final url = _baseUrl.endsWith('/v1')
      ? '$_baseUrl/chat/completions'
      : '$_baseUrl/v1/chat/completions';

  final bodyJson = <String, dynamic>{
    'model': _model,
    'messages': messages,
    'tools': tools,
    'tool_choice': 'required',
  };

  // Force disable thinking mode for DeepSeek models
  if (_model.contains('deepseek')) {
    bodyJson['thinking'] = {'type': 'disabled'};
  }

  // Send request...
}
```

### Request Body Example (deepseek-chat)

```json
{
  "model": "deepseek-chat",
  "messages": [...],
  "tools": [...],
  "tool_choice": "required",
  "thinking": {"type": "disabled"}
}
```

### Vision API (`chatVision`)

Some providers support multimodal: `chatVision(messages, imagePath)` attaches the image as base64 into the `image_url` field of the `messages`.

### Error Handling Chain

```
SocketException    → "Network connection failed, please check if Base URL is reachable"
TimeoutException   → "Request timed out, please check network or server status"
FormatException    → "Response format abnormal, server returned non-JSON data"
HTTP 401           → "Invalid or expired API Key"
HTTP 403           → "Access denied, please check API Key permissions"
HTTP 404           → "Incorrect Base URL or model does not exist"
HTTP 429           → "Too many requests, please try again later"
HTTP 5xx           → "Server error"
200 + error field  → Extract error.message
200 + no choices   → "Server returned an empty response"

tool_choice rejected → Remove parameter and auto-retry
thinking rejected    → Remove parameter and auto-retry
```

### Model List Filtering (`model_service.dart`)

```dart
.where((id) =>
    !id.contains('instruct') &&
    !id.contains('embedding') &&
    !id.contains('reasoner') &&
    !id.contains('thinking') &&
    !id.contains('r1'))
```

---

## Provider Management

### Preset Provider List

| Provider | API Base URL | Default Models |
|----------|-------------|----------------|
| DeepSeek | `https://api.deepseek.com` | `deepseek-chat`, `deepseek-reasoner` |
| Kimi (Moonshot) | `https://api.moonshot.cn/v1` | `kimi-k2.6`, `kimi-k2.6-thinking` |
| Tongyi Qianwen (Qwen) | `https://dashscope.aliyuncs.com/compatible-mode/v1` | `qwen-plus`, `qwen-max` |
| Zhipu GLM | `https://open.bigmodel.cn/api/paas/v4` | `glm-4-plus`, `glm-4` |
| OpenAI | `https://api.openai.com/v1` | `gpt-4o`, `gpt-4o-mini` |

### Data Model (`provider_config.dart`)

```dart
class ProviderConfig {
  final int? id;
  final String name;          // Provider name
  final String apiBaseUrl;    // API address
  final String apiKey;        // API Key (decrypted in memory, stored as AES encrypted in DB)
  final String selectedModel; // Currently selected model
  final int createdAt;

  String get maskedKey => '${apiKey.substring(0, 3)}****${apiKey.substring(apiKey.length - 4)}';
}
```

### API Key Encryption

- **Storage**: AES-CBC encrypted before writing to sqflite
- **Memory**: All keys decrypted into memory during `SettingsNotifier._init()`
- **Export**: Only `maskedKey` (redacted) is included, no full key

---

## Configuration Import & Export

### Provider Config Export (JSON)

```json
{
  "suppliers": [
    {
      "name": "DeepSeek",
      "baseUrl": "https://api.deepseek.com",
      "model": "deepseek-chat",
      "apiKey": "sk-****abcd"
    }
  ],
  "activeProviderName": "DeepSeek",
  "care_settings": {
    "proactiveEnabled": true,
    "silenceThresholdHours": 12.0,
    "dndPeriods": [{"start": {"hour": 22, "minute": 0}, "end": {"hour": 6, "minute": 0}}]
  },
  "memory_settings": {
    "maxShortTermRounds": 20
  },
  "export_time": "2026-06-04T22:30:00.000"
}
```

### Agent Export (`agent_export_service.dart`)

Each Agent can be individually exported as a JSON file for cross-device migration. Avatar and chat background images are inlined as base64:

```json
{
  "version": 1,
  "agent": {
    "name": "Xiaoyan",
    "gender": "Female",
    "description": "Gentle personal companion",
    "persona": "Your name is Xiaoyan...",
    "avatar_color": 4294901760,
    "avatar": "data:image/png;base64,iVBORw0KGgo...",
    "chat_background": "data:image/jpeg;base64,/9j/4AAQ..."
  }
}
```

On import, images are restored to `getApplicationDocumentsDirectory()`, preserving color and text fields.

### Full Database Backup

Directly copy the `aichat.db` file to the download directory. To restore, replace the database file and restart the application.

---

## Multilingual Support

| Mode | Description |
|------|-------------|
| **Auto** | On startup, detect country code via `ip-api.com/json`. CN/HK/TW/MO/SG → Chinese, others → English |
| **Manual** | User selects a language in the settings page, persisted to SharedPreferences (key `language_mode`) |

`lib/l10n/app_localizations.dart` contains a Chinese-English bilingual map of 120+ key-value pairs. All UI text is retrieved via `AppLocalizations.of(context)!.get('key')`.

---

## Core Code File Index

| File | Approx. Lines | Core Responsibility |
|------|--------------|---------------------|
| `lib/providers/chat_provider.dart` | 1430 | Chat state, `_runToolLoop` tool loop, system prompt, token recording, opening line |
| `lib/screens/chat_screen.dart` | 1370 | Chat UI: bubble animations, long-press menu, debug log, sidebar |
| `lib/screens/settings_screen.dart` | 1170 | Settings UI: providers, theme color, language, import/export, token stats |
| `lib/services/database_service.dart` | 740 | CRUD for 14 tables, backup/restore, upgrade migration |
| `lib/services/api_service.dart` | 490 | HTTP requests, tool definitions, vision API, error handling, model filter |
| `lib/services/memory_service.dart` | 200 | CRUD for short-term/long-term/base memory, prompt assembly |
| `lib/services/group_service.dart` | 285 | Group, member, group message, shared memory CRUD |
| `lib/services/plugin_manager.dart` | 240 | Plugin loading and lifecycle (experimental) |
| `lib/providers/settings_provider.dart` | 540 | Provider CRUD, theme color, token accumulation, config serialization |
| `lib/providers/group_provider.dart` | 380 | State and business flow for group, members, group messages |
| `lib/providers/memory_provider.dart` | 110 | Riverpod state for long-term/base memory |
| `lib/providers/plan_provider.dart` | 45 | Riverpod state for planned messages |
| `lib/providers/agent_provider.dart` | 100 | Riverpod state for agents |
| `lib/services/tool_executor.dart` | 220 | Execution logic for 5 tools, execution log recording |
| `lib/services/notification_service.dart` | 110 | Local notification scheduling |
| `lib/services/plan_service.dart` | 100 | Planned message persistence and triggering |
| `lib/services/model_service.dart` | 35 | Fetch and filter model list from API |
| `lib/services/encryption_service.dart` | 50 | AES-CBC encryption/decryption |
| `lib/services/locale_service.dart` | 50 | IP detection + language preference persistence |
| `lib/services/agent_export_service.dart` | 90 | Agent JSON import/export |
| `lib/l10n/app_localizations.dart` | 640 | Chinese-English bilingual localization map |
| `lib/screens/group_chat_screen.dart` | 445 | Group chat UI: multi-bubble, memory panel, stop generation |
| `lib/screens/group_manage_screen.dart` | 360 | Group member and persona management |
| `lib/screens/agent_create_screen.dart` | 470 | Agent create/edit form |
| `lib/screens/memory_screen.dart` | 485 | Long-term/base/shared/planned memory management |
| `lib/screens/group_create_screen.dart` | 335 | Group creation (multi-select Agents) |
| `lib/screens/agent_list_screen.dart` | 290 | Agent list (sidebar content) |
| `lib/screens/token_usage_screen.dart` | 195 | Token usage chart |
| `lib/screens/plugin_screen.dart` | 145 | Plugin management UI |
| `lib/screens/group_list_screen.dart` | 150 | Group list |
| `lib/screens/plan_screen.dart` | 90 | Planned message list |
| `lib/theme/app_theme.dart` | 360 | Material 3 design tokens and ThemeData |
| `lib/utils/responsive_layout.dart` | 65 | Responsive layout helpers |
| `lib/main.dart` | 165 | App entry, theme/locale/notification init, ProviderScope |

---

> **Version**: v2.0  
> **Generated**: 2026-06-04  
> **Tech Stack**: Flutter 3.x / Dart / Riverpod / sqflite / AES / Material 3 / OpenAI-compatible API
