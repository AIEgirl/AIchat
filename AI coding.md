# AI 记忆聊天 — 项目文档

> 一个基于 Flutter 的 OpenAI 兼容 AI 聊天应用，具备三层记忆系统和严格的工具调用机制。

---

## 目录

1. [项目概述](#项目概述)
2. [架构概览](#架构概览)
3. [工具系统](#工具系统)
4. [系统提示词](#系统提示词)
5. [三层记忆系统](#三层记忆系统)
6. [API 服务层](#api-服务层)
7. [供应商管理](#供应商管理)
8. [配置导入导出](#配置导入导出)
9. [多语言支持](#多语言支持)
10. [核心代码文件索引](#核心代码文件索引)

---

## 项目概述

**技术栈**：Flutter 3.x + Dart + Riverpod + sqflite + shared_preferences + AES 加密  
**目标平台**：Android / iOS  
**核心能力**：OpenAI 兼容 API 调用、强制工具调用、三层记忆管理、主动关心、多供应商切换、Token 用量统计  

---

## 架构概览

```
lib/
├── main.dart                    # 入口，MaterialApp + 多语言/通知初始化
├── l10n/
│   └── app_localizations.dart   # 中英双语本地化（70+ 键值对）
├── services/
│   ├── api_service.dart         # HTTP 请求 + 错误处理 + 工具选择策略
│   ├── memory_service.dart      # 三层记忆 CRUD + 提示词生成
│   ├── tool_executor.dart       # 工具调用执行器
│   ├── model_service.dart       # 从 /v1/models 获取模型列表
│   ├── database_service.dart    # sqflite 数据库（v3）+ 备份恢复
│   ├── encryption_service.dart  # AES 加密 API Key
│   ├── notification_service.dart# 本地通知（计划消息 + 主动关心）
│   ├── plan_service.dart        # 计划消息调度
│   └── locale_service.dart      # IP 语言检测 + 偏好持久化
├── providers/
│   ├── chat_provider.dart       # 聊天状态 + 工具循环 + 系统提示词构建
│   ├── settings_provider.dart   # 供应商 CRUD + Token 累计 + 配置导出导入
│   └── memory_provider.dart     # 长期/基础记忆的 Riverpod 状态
├── models/
│   ├── long_term_memory.dart    # 长期记忆模型（9字段）
│   ├── base_memory.dart         # 基础记忆模型（setting/event）
│   ├── short_term_message.dart  # 短期消息模型
│   ├── planned_message.dart     # 计划消息模型
│   └── provider_config.dart     # 供应商配置模型
└── screens/
    ├── chat_screen.dart         # 聊天主页面 + 调试日志页
    ├── settings_screen.dart     # 设置页（供应商/模型/人设/导入导出/语言）
    ├── memory_screen.dart       # 记忆管理页
    ├── plan_screen.dart         # 计划消息页
    └── token_usage_screen.dart  # Token 用量图表页
```

---

## 工具系统

AI 拥有 **4 个后台工具**，通过 OpenAI 兼容 API 的 `tools` 参数定义。工具调用遵循 `tool_choice: "required"` 强制模式（DeepSeek 模型另加 `thinking: {type: "disabled"}` 关闭思考）。

### 1. remember — 创建/更新记忆

**内涵**：将用户透露的个人信息持久化存储到长期记忆或基础记忆中。

**参数定义**：

```dart
{
  "type": "function",
  "function": {
    "name": "remember",
    "description": "创建或更新一条记忆。当用户透露个人信息、状态、关系、目标、想法、正在做的事、人物特征时调用。",
    "parameters": {
      "type": "object",
      "properties": {
        "memory_type": {
          "type": "string",
          "enum": ["long_term", "base"],
          "description": "记忆类型：long_term=长期记忆(仍在成立的信息)，base=基础记忆(已固定的设定或已完结的事件)"
        },
        "field": {
          "type": "string",
          "enum": ["time", "location", "current_events", "characters", "relationships", "goals", "thoughts", "status", "to_do"],
          "description": "仅 long_term 使用，指定记忆字段"
        },
        "content": {
          "type": "string",
          "description": "记忆内容"
        }
      },
      "required": ["memory_type", "content"]
    }
  }
}
```

**代码实现**（`tool_executor.dart`）：

```dart
case 'remember':
  final memType = args['memory_type'] as String? ?? 'long_term';
  final field = args['field'] as String?;
  final content = args['content'] as String? ?? '';

  if (memType == 'long_term') {
    // 生成 L001~L999 ID，同 field 内容去重后更新
    memoryService.upsertLongTerm(field: field ?? 'status', content: content);
    return 'long_term_memory_updated';
  } else {
    // 生成 B001~B999 ID，作为 base event 写入
    memoryService.addBaseMemory(type: 'event', content: content);
    return 'base_memory_added';
  }
```

### 2. forget — 删除记忆

**内涵**：删除过时的长期记忆条目，可选择将重要部分归档到基础记忆。

**参数定义**：

```dart
{
  "type": "function",
  "function": {
    "name": "forget",
    "description": "删除一条或多条记忆。当信息过时（状态改变、关系结束、目标完成等）时调用。",
    "parameters": {
      "type": "object",
      "properties": {
        "ids": {
          "type": "array",
          "items": {"type": "string"},
          "description": "要删除的记忆 ID 列表，如 ['L003', 'L007']"
        }
      },
      "required": ["ids"]
    }
  }
}
```

**代码实现**：

```dart
case 'forget':
  final ids = (args['ids'] as List?)?.cast<String>() ?? [];
  for (final id in ids) {
    await DatabaseService.deleteLongTermMemory(id);
  }
  return 'forgotten: ${ids.length} items';
```

### 3. chat — 向用户回复

**内涵**：AI 通过此工具向用户发送自然语言消息。这是 **唯一允许的输出通道**，禁止直接输出纯文本。

**参数定义**：

```dart
{
  "type": "function",
  "function": {
    "name": "chat",
    "description": "向用户发送自然语言回复。这是你与用户沟通的唯一方式。",
    "parameters": {
      "type": "object",
      "properties": {
        "message": {
          "type": "string",
          "description": "你向用户说的话，语气自然温暖，像真正的恋人"
        }
      },
      "required": ["message"]
    }
  }
}
```

**代码实现**：

```dart
case 'chat':
  // chat 工具被检测到时，直接提取 message 并返回，不再调用 API
  chatContent = args['message'] as String? ?? '';
  // 返回后由 _runToolLoop 直接交付给 UI
```

### 4. plan — 安排计划消息

**内涵**：在未来某个时间点主动向用户发送消息（如提醒、小惊喜）。

**参数定义**：

```dart
{
  "type": "function",
  "function": {
    "name": "plan",
    "description": "安排一条未来发送的主动消息（提醒、关心、小惊喜等）。",
    "parameters": {
      "type": "object",
      "properties": {
        "message": {"type": "string", "description": "要发送的消息内容"},
        "delay_minutes": {"type": "integer", "description": "延迟分钟数（距现在的分钟数）"}
      },
      "required": ["message", "delay_minutes"]
    }
  }
}
```

---

## 系统提示词

系统提示词是记忆系统运作的核心，通过多层指令强制 AI 在回复前调用记忆工具。

### 完整结构

```text
【当前真实时间】2026-05-09 22:30（星期六）

{{PERSONA}}                             ← 来自基础记忆 setting 条目

## 记忆系统（内部）
1. 短期记忆：最近20轮对话原文，系统自动管理
2. 长期记忆：保存目前仍成立的实时信息（9字段）
3. 基础记忆：设定(setting) + 历史事件(event)

## 记忆运作原则
- 心上（remember）：用户透露个人信息 → 立即更新
- 翻篇（forget）：信息过时 → 删除 + 可选归档

## 可用工具（后台）
remember / forget / chat / plan

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

### 构建代码（`chat_provider.dart:600`）

```dart
Future<String> _buildSystemPrompt() async {
  final now = DateTime.now();
  final timeStr = DateFormat('yyyy-MM-dd HH:mm').format(now);
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
| **存储表** | `short_term_messages` |
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
| **去重逻辑** | 同 field 存在内容 → 覆盖更新 |

**SQL 表结构**：

```sql
CREATE TABLE long_term_memories (
  id         TEXT PRIMARY KEY,
  field      TEXT NOT NULL,
  content    TEXT NOT NULL,
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

**SQL 表结构**：

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

## API 服务层

### 请求构建（`api_service.dart:48`）

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

### 导出文件格式（JSON）

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

### 完整数据库备份

直接复制 `aichat.db` 文件到下载目录。恢复时替换数据库文件并重启应用。

---

## 多语言支持

| 模式 | 说明 |
|------|------|
| **自动** | 启动时调用 `ip-api.com/json` 检测国家码，CN/HK/TW/MO/SG → 中文，其他 → 英文 |
| **手动** | 用户在设置页选择后持久化到 SharedPreferences（键 `language_mode`） |

`lib/l10n/app_localizations.dart` 包含 70+ 键值对的中英双语 Map，所有 UI 文本通过 `AppLocalizations.of(context)!.get('key')` 获取。

---

## 核心代码文件索引

| 文件 | 行数（约） | 核心职责 |
|------|----------|---------|
| `lib/providers/chat_provider.dart` | 730 | 聊天状态管理、`_runToolLoop` 工具循环、系统提示词构建、Token 记录 |
| `lib/screens/chat_screen.dart` | 590 | 聊天 UI：气泡动画、长按菜单、弹跳加载、调试日志 |
| `lib/screens/settings_screen.dart` | 720 | 设置 UI：供应商管理、模型选择、人设编辑、配置导入导出、语言切换 |
| `lib/services/api_service.dart` | 300 | HTTP 请求发送、错误处理、诊断日志、工具选择策略 |
| `lib/services/database_service.dart` | 310 | 8 张表的 CRUD、数据库备份恢复、人设迁移 |
| `lib/providers/settings_provider.dart` | 260 | 供应商 CRUD、Token 累计、配置序列化/反序列化 |
| `lib/services/tool_executor.dart` | 170 | 4 工具的执行逻辑、执行日志记录 |
| `lib/services/memory_service.dart` | ~200 | 短期/长期/基础记忆的增删查、提示词组装 |
| `lib/services/model_service.dart` | 35 | 从 API 获取模型列表并过滤 |
| `lib/l10n/app_localizations.dart` | 175 | 中英双语本地化 Map |
| `lib/services/locale_service.dart` | 45 | IP 检测 + 语言偏好持久化 |
| `lib/main.dart` | 70 | 应用入口、多语言初始化、SQLite 迁移 |

---

> **版本**：v1.0  
> **生成时间**：2026-05-09  
> **技术栈**：Flutter 3.x / Dart / Riverpod / sqflite / AES / OpenAI-compatible API
