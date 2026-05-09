# AI Memory Chat — Project Documentation

ENGLISH/[中文](README.md).

> A Flutter-based OpenAI-compatible AI chat application featuring a three-tier memory system and strict tool calling mechanisms.

> [!WARNING]
> This software was developed with AI programming assistance. If you are allergic to AI programming, please do not use it.

---

## Table of Contents

1. [Project Overview](#project-overview)
2. [Architecture Overview](#architecture-overview)
3. [Tool System](#tool-system)
4. [System Prompt](#system-prompt)
5. [Three-tier Memory System](#three-tier-memory-system)
6. [API Service Layer](#api-service-layer)
7. [Provider Management](#provider-management)
8. [Configuration Import & Export](#configuration-import--export)
9. [Multilingual Support](#multilingual-support)
10. [Core Code File Index](#core-code-file-index)

---

## Project Overview

**Tech Stack**: Flutter 3.x + Dart + Riverpod + sqflite + shared_preferences + AES encryption  
**Target Platforms**: Android / iOS  
**Core Capabilities**: OpenAI-compatible API calls, mandatory tool calls, three-tier memory management, proactive care, multi-provider switching, token usage statistics  

---

## Architecture Overview

```
lib/
├── main.dart                    # Entry point, MaterialApp + multi-language/notification initialization
├── l10n/
│   └── app_localizations.dart   # Chinese-English bilingual localization (70+ key-value pairs)
├── services/
│   ├── api_service.dart         # HTTP request + error handling + tool selection strategy
│   ├── memory_service.dart      # Three-tier memory CRUD + prompt generation
│   ├── tool_executor.dart       # Tool call executor
│   ├── model_service.dart       # Fetch model list from /v1/models
│   ├── database_service.dart    # sqflite database (v3) + backup & restore
│   ├── encryption_service.dart  # AES encryption of API keys
│   ├── notification_service.dart# Local notifications (planned messages + proactive care)
│   ├── plan_service.dart        # Planned message scheduling
│   └── locale_service.dart      # IP language detection + preference persistence
├── providers/
│   ├── chat_provider.dart       # Chat state + tool loop + system prompt construction
│   ├── settings_provider.dart   # Provider CRUD + token accumulation + config export/import
│   └── memory_provider.dart     # Riverpod state for long-term/base memories
├── models/
│   ├── long_term_memory.dart    # Long-term memory model (9 fields)
│   ├── base_memory.dart         # Base memory model (setting/event)
│   ├── short_term_message.dart  # Short-term message model
│   ├── planned_message.dart     # Planned message model
│   └── provider_config.dart     # Provider configuration model
└── screens/
    ├── chat_screen.dart         # Main chat screen + debug log page
    ├── settings_screen.dart     # Settings (providers/models/persona/import-export/language)
    ├── memory_screen.dart       # Memory management screen
    ├── plan_screen.dart         # Planned messages screen
    └── token_usage_screen.dart  # Token usage chart screen
```

---

## Tool System

The AI has **4 background tools** defined via the OpenAI-compatible API `tools` parameter. Tool calls follow the `tool_choice: "required"` mandatory mode (for DeepSeek models, `thinking: {type: "disabled"}` is also added to disable thinking).

### 1. remember — Create/Update Memory

**Purpose**: Persistently store personal information disclosed by the user into long-term or base memory.

**Parameter definition**:

```dart
{
  "type": "function",
  "function": {
    "name": "remember",
    "description": "Create or update a memory. Call this when the user reveals personal information, status, relationships, goals, thoughts, current activities, or character traits.",
    "parameters": {
      "type": "object",
      "properties": {
        "memory_type": {
          "type": "string",
          "enum": ["long_term", "base"],
          "description": "Memory type: long_term = long-term memory (information that still holds true), base = base memory (fixed settings or concluded events)"
        },
        "field": {
          "type": "string",
          "enum": ["time", "location", "current_events", "characters", "relationships", "goals", "thoughts", "status", "to_do"],
          "description": "Used only for long_term, specifies the memory field"
        },
        "content": {
          "type": "string",
          "description": "Memory content"
        }
      },
      "required": ["memory_type", "content"]
    }
  }
}
```

**Code implementation** (`tool_executor.dart`):

```dart
case 'remember':
  final memType = args['memory_type'] as String? ?? 'long_term';
  final field = args['field'] as String?;
  final content = args['content'] as String? ?? '';

  if (memType == 'long_term') {
    // Generate L001~L999 ID, update if same field content already exists
    memoryService.upsertLongTerm(field: field ?? 'status', content: content);
    return 'long_term_memory_updated';
  } else {
    // Generate B001~B999 ID, write as base event
    memoryService.addBaseMemory(type: 'event', content: content);
    return 'base_memory_added';
  }
```

### 2. forget — Delete Memory

**Purpose**: Delete outdated long-term memory entries, optionally archive important parts to base memory.

**Parameter definition**:

```dart
{
  "type": "function",
  "function": {
    "name": "forget",
    "description": "Delete one or more memories. Call when information becomes outdated (status change, relationship ends, goal achieved, etc.).",
    "parameters": {
      "type": "object",
      "properties": {
        "ids": {
          "type": "array",
          "items": {"type": "string"},
          "description": "List of memory IDs to delete, e.g., ['L003', 'L007']"
        }
      },
      "required": ["ids"]
    }
  }
}
```

**Code implementation**:

```dart
case 'forget':
  final ids = (args['ids'] as List?)?.cast<String>() ?? [];
  for (final id in ids) {
    await DatabaseService.deleteLongTermMemory(id);
  }
  return 'forgotten: ${ids.length} items';
```

### 3. chat — Reply to User

**Purpose**: The AI sends a natural language message to the user through this tool. This is the **only allowed output channel**; direct plain text output is prohibited.

**Parameter definition**:

```dart
{
  "type": "function",
  "function": {
    "name": "chat",
    "description": "Send a natural language reply to the user. This is the only way you communicate with the user.",
    "parameters": {
      "type": "object",
      "properties": {
        "message": {
          "type": "string",
          "description": "The message you speak to the user. Tone should be natural and warm, like a true companion."
        }
      },
      "required": ["message"]
    }
  }
}
```

**Code implementation**:

```dart
case 'chat':
  // When chat tool is detected, extract the message and return directly, no additional API call
  chatContent = args['message'] as String? ?? '';
  // Returned to _runToolLoop and delivered straight to UI
```

### 4. plan — Schedule a Planned Message

**Purpose**: Proactively send a message to the user at a future time (e.g., reminder, little surprise).

**Parameter definition**:

```dart
{
  "type": "function",
  "function": {
    "name": "plan",
    "description": "Schedule a future proactive message (reminder, care, surprise, etc.).",
    "parameters": {
      "type": "object",
      "properties": {
        "message": {"type": "string", "description": "The message content to be sent"},
        "delay_minutes": {"type": "integer", "description": "Delay in minutes from now"}
      },
      "required": ["message", "delay_minutes"]
    }
  }
}
```

---

## System Prompt

The system prompt is the core of the memory system's operation. Through multi-layered instructions, it compels the AI to call memory tools before replying.

### Full Structure

```text
【Current Actual Time】2026-05-09 22:30 (Saturday)

{{PERSONA}}                             ← Derived from base memory setting entries

## Memory System (Internal)
1. Short-term memory: Original text of the last 20 conversation turns, managed automatically by the system
2. Long-term memory: Stores real-time information that still holds true (9 fields)
3. Base memory: Settings (setting) + Historical events (event)

## Memory Operation Principles
- Remember (remember): User reveals personal info → immediately update
- Let go (forget): Information becomes outdated → delete + optional archive

## Available Tools (Background)
remember / forget / chat / plan

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

### Build Code (`chat_provider.dart:600`)

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
| **Storage Table** | `short_term_messages` |
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
| **Deduplication Logic** | If content exists for the same field → overwrite update |

**SQL Schema**:

```sql
CREATE TABLE long_term_memories (
  id         TEXT PRIMARY KEY,
  field      TEXT NOT NULL,
  content    TEXT NOT NULL,
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

**SQL Schema**:

```sql
CREATE TABLE base_memories (
  id         TEXT PRIMARY KEY,
  type       TEXT NOT NULL,     -- 'setting' or 'event'
  content    TEXT NOT NULL,
  updated_at INTEGER NOT NULL,
  created_at INTEGER NOT NULL
);
```

---

## API Service Layer

### Request Construction (`api_service.dart:48`)

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

### Export File Format (JSON)

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
  "export_time": "2026-05-09T22:30:00.000"
}
```

### Full Database Backup

Directly copy the `aichat.db` file to the download directory. To restore, replace the database file and restart the application.

---

## Multilingual Support

| Mode | Description |
|------|-------------|
| **Auto** | On startup, detect country code via `ip-api.com/json`. CN/HK/TW/MO/SG → Chinese, others → English |
| **Manual** | User selects a language in the settings page, persisted to SharedPreferences (key `language_mode`) |

`lib/l10n/app_localizations.dart` contains a Chinese-English bilingual map of 70+ key-value pairs. All UI text is retrieved via `AppLocalizations.of(context)!.get('key')`.

---

## Core Code File Index

| File | Approx. Lines | Core Responsibility |
|------|--------------|---------------------|
| `lib/providers/chat_provider.dart` | 730 | Chat state management, `_runToolLoop` tool loop, system prompt construction, token recording |
| `lib/screens/chat_screen.dart` | 590 | Chat UI: bubble animations, long-press menu, bounce loading, debug log |
| `lib/screens/settings_screen.dart` | 720 | Settings UI: provider management, model selection, persona editing, config import/export, language switch |
| `lib/services/api_service.dart` | 300 | HTTP request sending, error handling, diagnostic logging, tool selection strategy |
| `lib/services/database_service.dart` | 310 | CRUD for 8 tables, database backup/restore, persona migration |
| `lib/providers/settings_provider.dart` | 260 | Provider CRUD, token accumulation, config serialization/deserialization |
| `lib/services/tool_executor.dart` | 170 | Execution logic for 4 tools, execution log recording |
| `lib/services/memory_service.dart` | ~200 | Short-term/long-term/base memory CRUD, prompt assembly |
| `lib/services/model_service.dart` | 35 | Fetch and filter model list from API |
| `lib/l10n/app_localizations.dart` | 175 | Chinese-English bilingual localization map |
| `lib/services/locale_service.dart` | 45 | IP detection + language preference persistence |
| `lib/main.dart` | 70 | App entry point, multi-language initialization, SQLite migration |

---

> **Version**: v1.0  
> **Generated**: 2026-05-09  
> **Tech Stack**: Flutter 3.x / Dart / Riverpod / sqflite / AES / OpenAI-compatible API