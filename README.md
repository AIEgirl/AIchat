# AI 记忆聊天 — 项目文档


中文/[English](ENGLISH.md).

> 一个基于 Flutter 的 OpenAI 兼容 AI 聊天应用，具备三层记忆系统、多智能体群聊、统一的智能体侧边栏、Material 3 主题，以及严格的工具调用机制。

> [!WARNING]
> 这是一个AI编程辅助出来的软件，AI编程过敏者请不要使用

---

## 目录

1. [项目概述](#项目概述)
2. [架构概览](#架构概览)
3. [工具系统](#工具系统)
4. [系统提示词](#系统提示词)
5. [三层记忆系统](#三层记忆系统)
6. [群聊系统](#群聊系统)
7. [API 服务层](#api-服务层)
8. [供应商管理](#供应商管理)
9. [配置导入导出](#配置导入导出)
10. [多语言支持](#多语言支持)
11. [核心代码文件索引](#核心代码文件索引)

---

## 项目概述

**技术栈**：Flutter 3.x + Dart + Riverpod + sqflite + shared_preferences + AES 加密 + Material 3  
**目标平台**：Android / iOS  
**核心能力**：
- OpenAI 兼容 API 调用（聊天 + 视觉）
- 强制工具调用（`tool_choice: required`）
- 三层记忆 + 群聊共享记忆
- 多智能体（Agent）与群聊（Group Chat）
- 每个 Agent 可配置开场白（opening line）
- 统一侧边栏管理所有会话对象（智能体 / 群聊）
- 主动关心、计划消息、本地通知
- 多供应商切换、Token 用量统计与图表
- 插件系统（实验性）
- 中英双语本地化（120+ 键值对）
- Material 3 设计主题（`AppTheme`）

---

## 架构概览

```
lib/
├── main.dart                       # 入口：MaterialApp、ProviderScope、初始化主题/多语言/通知
├── theme/
│   └── app_theme.dart              # Material 3 设计令牌：间距、圆角、阴影、ThemeData
├── l10n/
│   └── app_localizations.dart      # 中英双语本地化（120+ 键值对）
├── utils/
│   └── responsive_layout.dart      # 响应式布局辅助（断点、缩放）
├── services/
│   ├── api_service.dart            # HTTP 请求、工具定义、视觉 API、错误处理
│   ├── memory_service.dart         # 三层记忆 CRUD + 提示词生成
│   ├── tool_executor.dart          # 5 工具的执行器
│   ├── model_service.dart          # 从 /v1/models 获取并过滤模型列表
│   ├── database_service.dart       # sqflite 数据库（v9，14 张表）+ 备份恢复
│   ├── encryption_service.dart     # AES-CBC 加密 API Key
│   ├── notification_service.dart   # 本地通知（计划消息 + 主动关心）
│   ├── plan_service.dart           # 计划消息调度
│   ├── locale_service.dart         # IP 语言检测 + 偏好持久化
│   ├── group_service.dart          # 群聊与共享记忆 CRUD
│   ├── agent_export_service.dart   # 智能体 JSON 导入导出（含头像/背景 base64）
│   └── plugin_manager.dart         # 插件系统管理（实验性）
├── providers/
│   ├── chat_provider.dart          # 聊天状态、工具循环、系统提示词、Token 累计
│   ├── settings_provider.dart      # 供应商 CRUD、主题色、Token 累计、配置序列化
│   ├── memory_provider.dart        # 长期/基础/共享记忆的 Riverpod 状态
│   ├── group_provider.dart         # 群聊、成员、群消息的状态
│   ├── plan_provider.dart          # 计划消息的状态
│   └── agent_provider.dart         # 智能体的状态（侧边栏使用）
├── models/
│   ├── agent.dart                  # 智能体（含 opening_line、avatar、chat_background）
│   ├── ai_agent.dart               # 旧版 AI Agent（兼容性保留）
│   ├── chat_message.dart           # 聊天消息（轻量模型）
│   ├── long_term_memory.dart       # 长期记忆（9 字段 + agent_id + group_id）
│   ├── base_memory.dart            # 基础记忆（setting/event + agent_id + group_id）
│   ├── short_term_message.dart     # 短期消息（agent_id + group_id）
│   ├── planned_message.dart        # 计划消息（agent_id + group_id）
│   ├── provider_config.dart        # 供应商配置
│   ├── group_chat.dart             # 群聊（名称、描述、人设、发言模式）
│   ├── group_member.dart           # 群成员（角色、是否在场）
│   ├── group_message.dart          # 群消息（发送者、工具调用）
│   └── group_shared_memory.dart    # 群共享记忆（按字段）
└── screens/
    ├── chat_screen.dart            # 聊天主页面 + 调试日志页
    ├── settings_screen.dart        # 设置页（供应商/主题/语言/导入导出）
    ├── memory_screen.dart          # 记忆管理页（长期/基础/共享/计划）
    ├── plan_screen.dart            # 计划消息页
    ├── token_usage_screen.dart     # Token 用量图表页
    ├── plugin_screen.dart          # 插件管理页（实验性）
    ├── agent_list_screen.dart      # 智能体侧边栏列表
    ├── agent_create_screen.dart    # 智能体创建/编辑页
    ├── group_list_screen.dart      # 群聊列表
    ├── group_create_screen.dart    # 群聊创建页
    ├── group_manage_screen.dart    # 群聊管理页（成员、人设、模式）
    └── group_chat_screen.dart      # 群聊对话页
```

### 主题与设计系统

`lib/theme/app_theme.dart` 集中管理所有视觉令牌：

- **间距**：`space1`~`space10`（4/8/12/16/20/24/32/40）
- **圆角**：`radiusSm`~`radiusXl`、`radiusFull`（8/12/16/20/999）
- **阴影**：`shadowSm` / `shadowMd` / `shadowLg`
- **动画时长**：`durationFast` / `durationNormal` / `durationSlow`（150/220/320ms）
- **完整 ThemeData**：`light(primary)` / `dark(primary)`，覆盖 Card、Dialog、BottomSheet、Input、Button、Chip、ListTile、SnackBar、TabBar、Switch、Slider 等组件

主入口通过 `theme: AppTheme.light(primary), darkTheme: AppTheme.dark(primary)` 启用。

---

## 工具系统

AI 通过 OpenAI 兼容 API 的 `tools` 参数定义工具。`ApiService.getToolDefinitions(isGroupChat: ...)` 根据场景返回**两组不同**的工具集。

### 私聊工具（4 个）

私聊（与单个智能体）使用以下 4 个工具。调用遵循 `tool_choice: "required"` 强制模式（DeepSeek 模型另加 `thinking: {type: "disabled"}` 关闭思考）。

#### 1. remember — 创建/更新记忆

**内涵**：将用户透露的个人信息持久化存储到长期记忆或基础记忆中。

**参数定义**：

```dart
{
  "type": "function",
  "function": {
    "name": "remember",
    "description": "记住一条当前状态或过去的事件。",
    "parameters": {
      "type": "object",
      "properties": {
        "memory_type": {
          "type": "string",
          "enum": ["long_term", "base"],
          "description": "long_term = 长期记忆；base = 基础记忆（追加历史事件）"
        },
        "action": {
          "type": "string",
          "enum": ["create", "update"],
          "description": "create 新建，update 更新（需 target_id）"
        },
        "target_id": {
          "type": "string",
          "description": "更新时必填，目标条目序号（如 L003）"
        },
        "field": {
          "type": "string",
          "enum": ["time", "location", "current_events", "characters", "relationships", "goals", "thoughts", "status", "to_do"],
          "description": "长期记忆字段名；base 类型无需此参数"
        },
        "content": {
          "type": "string",
          "description": "记忆内容（更新时提供完整新内容）"
        }
      },
      "required": ["memory_type", "action"]
    }
  }
}
```

#### 2. forget — 删除记忆

```dart
{
  "type": "function",
  "function": {
    "name": "forget",
    "description": "删除不再有用的条目。设定条目不可删除。",
    "parameters": {
      "type": "object",
      "properties": {
        "target_ids": {
          "type": "array",
          "items": {"type": "string"},
          "description": "条目序号列表，如 ['L003', 'B007']"
        }
      },
      "required": ["target_ids"]
    }
  }
}
```

#### 3. chat — 向用户回复

```dart
{
  "type": "function",
  "function": {
    "name": "chat",
    "description": "向用户发送自然语言回复。记忆操作完成后用它来最终回复。",
    "parameters": {
      "type": "object",
      "properties": {
        "message": {"type": "string", "description": "回复给用户的文本"}
      },
      "required": ["message"]
    }
  }
}
```

#### 4. plan — 安排计划消息

```dart
{
  "type": "function",
  "function": {
    "name": "plan",
    "description": "安排一条未来发送的消息。",
    "parameters": {
      "type": "object",
      "properties": {
        "send_time": {
          "type": "string",
          "description": "相对时间如 '30m'、'2h'，或 ISO 8601 具体时间"
        },
        "message": {"type": "string", "description": "到时间后要发送的消息"}
      },
      "required": ["send_time", "message"]
    }
  }
}
```

### 群聊工具（4 个）

群聊场景下使用不同的工具集，**关键区别是引入了 `group_scope` / `memory_source`** 用于区分个人与群共享记忆。

| 工具 | 私聊版本 | 群聊版本 | 差异 |
|------|---------|---------|------|
| remember | `_rememberTool` | `_rememberGroupTool` | 群版新增 `group_scope: personal \| shared` |
| forget | `_forgetTool` | `_forgetGroupTool` | 群版新增 `memory_source: personal \| shared` |
| chat | `_chatTool` | — | 私聊专用 |
| chatgroup | — | `_chatgroupTool` | 群聊专用（向群内发送） |
| plan | `_planTool` | `_planGroupTool` | 群版消息内容指向群 |

工具调用方始终是单次 LLM，但记忆的写入会按 `group_scope` / `memory_source` 路由到：
- `long_term_memories` / `base_memories`（`agent_id = 当前 Agent, group_id = NULL`）
- `group_shared_memories`（`group_id = 当前群`）

---

## 系统提示词

系统提示词是记忆系统运作的核心，通过多层指令强制 AI 在回复前调用记忆工具。

### 完整结构

```text
【当前真实时间】2026-06-04 22:30（星期六）

{{PERSONA}}                             ← 来自基础记忆 setting 条目（或 Agent.persona）

## 记忆系统（内部）
1. 短期记忆：最近20轮对话原文，系统自动管理
2. 长期记忆：保存目前仍成立的实时信息（9 字段）
3. 基础记忆：设定(setting) + 历史事件(event)

## 记忆运作原则
- 心上（remember）：用户透露个人信息 → 立即创建/更新
- 翻篇（forget）：信息过时 → 删除 + 可选归档

## 可用工具（后台）
remember / forget / chat / plan            ← 私聊
remember / forget / chatgroup / plan       ← 群聊

## 工具调用铁律
- 提到人名/关系/特征 → remember
- 提到状态/健康/情绪/想法 → remember
- 提到地点/事件/目标 → remember
- 提到已结束经历/历史 → remember(base)
- 过时信息 → forget → remember → chat

【最高优先级：工具调用规则】
- 在回复前必须判断是否需要记忆
- 不确定时宁可多记不能遗漏
- 示例："我有个朋友叫老张" → 必须先 remember

## 对话风格
严格按照设定说话，融入记忆信息，绝不使用机械表达

====

【当前长期记忆】（按字段组织，带序号）
L001 [relationships] 用户有一个朋友叫老张

【当前基础记忆】（设定与重大事件，带序号）
B001 [setting] 你是用户的私人AI伴侣，名字叫小言...
```

### 开场白（Opening Line）

每个 Agent 在 `agent.openingLine` 字段携带可选的开场白。新会话首次打开时（短期记忆为空），`ChatProvider` 会将开场白作为 AI 消息插入到对话顶部，作为 AI 的"第一印象"。

### 构建代码（`chat_provider.dart`）

```dart
Future<String> _buildSystemPrompt() async {
  final now = DateTime.now();
  final timeStr = DateDateFormat('yyyy-MM-dd HH:mm').format(now);
  final weekStr = ['日','一','二','三','四','五','六'][now.weekday % 7];

  final baseMemories = _ref.read(baseProvider).memories;
  final personaLines = baseMemories.where((m) => m.isSetting).map((m) => m.content).join('\n');
  final persona = personaLines.isNotEmpty ? personaLines : defaultSystemPersona;

  final longTermPrompt = await _memoryService.buildLongTermPrompt();
  final basePrompt = await _memoryService.buildBasePrompt();

  var prompt = '''【当前真实时间】$timeStr（星期$weekStr）

$persona

## 记忆系统（内部）...
## 记忆运作原则...
## 可用工具（后台）...
## 工具调用铁律...
【最高优先级：工具调用规则】...
## 对话风格...
====

【当前长期记忆】
$longTermPrompt

【当前基础记忆】
$basePrompt''';

  // 主动关心：超时未说话
  if (extraProactiveHint != null) {
    prompt += '\n\n用户已经 $extraProactiveHint 小时没有说话，请主动发送关心消息。';
  }

  return prompt;
}
```

---

## 三层记忆系统

### 短期记忆（Short-term）

| 属性 | 值 |
|------|-----|
| **存储表** | `short_term_messages`（私聊）、`group_short_term`（群聊） |
| **ID 格式** | `S001` ~ `S999` |
| **容量** | 默认 20 轮（可配置） |
| **内容** | 最近对话的原文（role + content + timestamp） |
| **管理** | 环形覆盖：超过容量时删除最旧条目 |
| **用途** | 直接注入 API 请求的 `messages` 数组，提供对话上下文 |

### 长期记忆（Long-term）

| 属性 | 值 |
|------|-----|
| **存储表** | `long_term_memories` |
| **ID 格式** | `L001` ~ `L999` |
| **容量** | 建议 ≤ 15 条 |
| **字段** | `time`, `location`, `current_events`, `characters`, `relationships`, `goals`, `thoughts`, `status`, `to_do` |
| **去重逻辑** | 同 field 存在内容 → 覆盖更新；或 `action=update` 指定 `target_id` |

**SQL 表结构**：

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

### 基础记忆（Base）

| 属性 | 值 |
|------|-----|
| **存储表** | `base_memories` |
| **ID 格式** | `B001` ~ `B999` |
| **类型** | `setting`（设定/人设）、`event`（历史事件） |
| **特点** | setting 永久保留不可删除；event 用于归档过时长期记忆 |

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

### 范围标识（agent_id / group_id）

所有长期/基础记忆表都带有 `agent_id` 和 `group_id`（可空）：
- `agent_id != null, group_id == null`：私聊记忆
- `group_id != null`：群聊记忆（agent_id 可用于在群内区分具体 Agent 的个人条目）

---

## 群聊系统

群聊是相对私聊的一等公民，拥有独立的对话、记忆、工具集。

### 数据模型

#### `group_chats`

```sql
CREATE TABLE group_chats (
  id            TEXT PRIMARY KEY,
  name          TEXT NOT NULL,
  description   TEXT DEFAULT '',
  avatar_color  INTEGER,
  group_persona TEXT,                    -- 群聊人设（覆盖 Agent 个人人设）
  speech_mode   TEXT DEFAULT 'free',     -- 'free' 自由发言 / 'round' 轮流发言
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
  is_present INTEGER DEFAULT 1,        -- 是否在场（影响 @all 广播）
  joined_at  INTEGER
);
```

#### `group_messages`

```sql
CREATE TABLE group_messages (
  id             INTEGER PRIMARY KEY AUTOINCREMENT,
  group_id       TEXT NOT NULL,
  sender_type    TEXT NOT NULL,        -- 'user' | 'agent' | 'system'
  sender_id      TEXT,                 -- Agent.id（agent 时）
  sender_name    TEXT,
  content        TEXT NOT NULL,
  timestamp      INTEGER,
  tool_call_data TEXT                  -- 工具调用原始 JSON（调试用）
);
```

#### `group_shared_memories`

```sql
CREATE TABLE group_shared_memories (
  id         TEXT PRIMARY KEY,
  group_id   TEXT NOT NULL,
  field      TEXT NOT NULL,            -- 长期记忆的 9 字段
  content    TEXT NOT NULL,
  updated_at INTEGER
);
```

### 群聊消息流

```
用户输入 ──> GroupProvider
              │
              ├── 写入 group_messages (sender_type=user)
              ├── 读取 group_short_term 注入上下文
              ├── 为每个在场 Agent 串行调用 API（私聊工具集 + chatgroup）
              ├── 工具调用：
              │     remember(group_scope=shared) ─> group_shared_memories
              │     remember(group_scope=personal) ─> long_term_memories (agent_id=当前)
              │     forget(memory_source=shared) ─> group_shared_memories
              │     chatgroup ─> 写入 group_messages (sender_type=agent)
              └── 全部结束后刷新 UI
```

### 群组管理

- **群组列表**（`group_list_screen`）：所有群聊卡片，点击进入对话，长按管理。
- **创建群组**（`group_create_screen`）：选择 Agent 成员（多选）、颜色、人设（可选）、发言模式。
- **群组管理**（`group_manage_screen`）：编辑名称/描述、调整成员（添加/移除/角色）、修改人设、删除群。
- **群聊对话**（`group_chat_screen`）：多气泡界面、@提及、记忆面板、停止生成。

### 发言模式

- `free`（自由发言）：每个 Agent 在每次用户输入后都会响应。
- `round`（轮流发言）：Agent 按 `joined_at` 顺序轮流响应（本版本 UI 已支持，逻辑由 `GroupProvider` 控制）。

---

## API 服务层

### 工具集选择（`api_service.dart:319`）

```dart
static List<Map<String, dynamic>> getToolDefinitions({bool isGroupChat = false}) {
  if (isGroupChat) return _getGroupToolDefinitions();
  return _getPrivateToolDefinitions();
}
```

### 请求构建（私聊）

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

  // DeepSeek 模型强制关闭思考模式
  if (_model.contains('deepseek')) {
    bodyJson['thinking'] = {'type': 'disabled'};
  }

  // 发送请求...
}
```

### 请求体示例（deepseek-chat）

```json
{
  "model": "deepseek-chat",
  "messages": [...],
  "tools": [...],
  "tool_choice": "required",
  "thinking": {"type": "disabled"}
}
```

### 视觉 API（`chatVision`）

部分供应商支持多模态：`chatVision(messages, imagePath)` 将图片以 base64 形式附加到 `messages` 的 `image_url` 字段。

### 错误处理链

```
SocketException    → "网络连接失败，请检查 Base URL 是否可达"
TimeoutException   → "请求超时，请检查网络或服务端状态"
FormatException    → "响应格式异常，服务端返回了非 JSON 数据"
HTTP 401           → "API Key 无效或已过期"
HTTP 403           → "无权访问，请检查 API Key 权限"
HTTP 404           → "Base URL 不正确或模型不存在"
HTTP 429           → "请求过于频繁，请稍后重试"
HTTP 5xx           → "服务端错误"
200 + error field  → 提取 error.message
200 + 无 choices   → "服务端返回了空响应"

tool_choice 被拒   → 移除参数后自动重试
thinking 被拒      → 移除参数后自动重试
```

### 模型列表过滤（`model_service.dart`）

```dart
.where((id) =>
    !id.contains('instruct') &&
    !id.contains('embedding') &&
    !id.contains('reasoner') &&
    !id.contains('thinking') &&
    !id.contains('r1'))
```

---

## 供应商管理

### 预设供应商列表

| 供应商 | API Base URL | 默认模型 |
|--------|-------------|---------|
| DeepSeek | `https://api.deepseek.com` | `deepseek-chat`, `deepseek-reasoner` |
| Kimi (Moonshot) | `https://api.moonshot.cn/v1` | `kimi-k2.6`, `kimi-k2.6-thinking` |
| 通义千问 (Qwen) | `https://dashscope.aliyuncs.com/compatible-mode/v1` | `qwen-plus`, `qwen-max` |
| 智谱 GLM | `https://open.bigmodel.cn/api/paas/v4` | `glm-4-plus`, `glm-4` |
| OpenAI | `https://api.openai.com/v1` | `gpt-4o`, `gpt-4o-mini` |

### 数据模型（`provider_config.dart`）

```dart
class ProviderConfig {
  final int? id;
  final String name;          // 供应商名称
  final String apiBaseUrl;    // API 地址
  final String apiKey;        // API Key（内存中解密，库中 AES 加密）
  final String selectedModel; // 当前选中模型
  final int createdAt;

  String get maskedKey => '${apiKey.substring(0, 3)}****${apiKey.substring(apiKey.length - 4)}';
}
```

### API Key 加密

- **存储**：AES-CBC 加密后写入 sqflite
- **内存**：`SettingsNotifier._init()` 时全部解密到内存
- **导出**：仅包含 `maskedKey`（脱敏），不包含完整 Key

---

## 配置导入导出

### 供应商配置导出（JSON）

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

### 智能体导出（`agent_export_service.dart`）

每个 Agent 可单独导出为 JSON 文件，便于跨设备迁移。头像和聊天背景会内联为 base64：

```json
{
  "version": 1,
  "agent": {
    "name": "小言",
    "gender": "女",
    "description": "温柔的私人伴侣",
    "persona": "你叫小言...",
    "avatar_color": 4294901760,
    "avatar": "data:image/png;base64,iVBORw0KGgo...",
    "chat_background": "data:image/jpeg;base64,/9j/4AAQ..."
  }
}
```

导入时还原图片到 `getApplicationDocumentsDirectory()`，并保留颜色与文本字段。

### 完整数据库备份

直接复制 `aichat.db` 文件到下载目录。恢复时替换数据库文件并重启应用。

---

## 多语言支持

| 模式 | 说明 |
|------|------|
| **自动** | 启动时调用 `ip-api.com/json` 检测国家码，CN/HK/TW/MO/SG → 中文，其他 → 英文 |
| **手动** | 用户在设置页选择后持久化到 SharedPreferences（键 `language_mode`） |

`lib/l10n/app_localizations.dart` 包含 120+ 键值对的中英双语 Map，所有 UI 文本通过 `AppLocalizations.of(context)!.get('key')` 获取。

---

## 核心代码文件索引

| 文件 | 行数（约） | 核心职责 |
|------|----------|---------|
| `lib/providers/chat_provider.dart` | 1430 | 聊天状态、`_runToolLoop` 工具循环、系统提示词、Token 记录、开场白 |
| `lib/screens/chat_screen.dart` | 1370 | 聊天 UI：气泡动画、长按菜单、调试日志、侧边栏 |
| `lib/screens/settings_screen.dart` | 1170 | 设置 UI：供应商、主题色、语言、导入导出、Token 统计 |
| `lib/services/database_service.dart` | 740 | 14 张表的 CRUD、备份恢复、升级迁移 |
| `lib/services/api_service.dart` | 490 | HTTP 请求、工具定义、视觉 API、错误处理、模型过滤 |
| `lib/services/memory_service.dart` | 200 | 短期/长期/基础记忆的 CRUD、提示词组装 |
| `lib/services/group_service.dart` | 285 | 群聊、成员、群消息、共享记忆 CRUD |
| `lib/services/plugin_manager.dart` | 240 | 插件加载与生命周期（实验性） |
| `lib/providers/settings_provider.dart` | 540 | 供应商 CRUD、主题色、Token 累计、配置序列化 |
| `lib/providers/group_provider.dart` | 380 | 群聊、成员、群消息的状态与业务流 |
| `lib/providers/memory_provider.dart` | 110 | 长期/基础记忆的 Riverpod 状态 |
| `lib/providers/plan_provider.dart` | 45 | 计划消息的 Riverpod 状态 |
| `lib/providers/agent_provider.dart` | 100 | 智能体的 Riverpod 状态 |
| `lib/services/tool_executor.dart` | 220 | 5 工具的执行逻辑、执行日志记录 |
| `lib/services/notification_service.dart` | 110 | 本地通知调度 |
| `lib/services/plan_service.dart` | 100 | 计划消息持久化与触发 |
| `lib/services/model_service.dart` | 35 | 从 API 获取模型列表并过滤 |
| `lib/services/encryption_service.dart` | 50 | AES-CBC 加解密 |
| `lib/services/locale_service.dart` | 50 | IP 检测 + 语言偏好持久化 |
| `lib/services/agent_export_service.dart` | 90 | 智能体 JSON 导入导出 |
| `lib/l10n/app_localizations.dart` | 640 | 中英双语本地化 Map |
| `lib/screens/group_chat_screen.dart` | 445 | 群聊对话 UI：多气泡、记忆面板、停止生成 |
| `lib/screens/group_manage_screen.dart` | 360 | 群聊成员与人设管理 |
| `lib/screens/agent_create_screen.dart` | 470 | 智能体创建/编辑表单 |
| `lib/screens/memory_screen.dart` | 485 | 长期/基础/共享/计划记忆管理 |
| `lib/screens/group_create_screen.dart` | 335 | 群聊创建（多选 Agent） |
| `lib/screens/agent_list_screen.dart` | 290 | 智能体列表（侧边栏内容） |
| `lib/screens/token_usage_screen.dart` | 195 | Token 用量图表 |
| `lib/screens/plugin_screen.dart` | 145 | 插件管理 UI |
| `lib/screens/group_list_screen.dart` | 150 | 群聊列表 |
| `lib/screens/plan_screen.dart` | 90 | 计划消息列表 |
| `lib/theme/app_theme.dart` | 360 | Material 3 设计令牌与 ThemeData |
| `lib/utils/responsive_layout.dart` | 65 | 响应式布局辅助 |
| `lib/main.dart` | 165 | 应用入口、主题/多语言/通知初始化、ProviderScope |

---

> **版本**：v2.0  
> **生成时间**：2026-06-04  
> **技术栈**：Flutter 3.x / Dart / Riverpod / sqflite / AES / Material 3 / OpenAI-compatible API
