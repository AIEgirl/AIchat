# AGENTS.md — AI Chat (Flutter)

## Quick reference

```bash
flutter analyze          # lint + typecheck (zero tolerance — must pass)
flutter run              # launch on connected device/emulator
flutter clean && flutter pub get && flutter run   # clean rebuild
```

## Cross-drive Kotlin (critical)

Pub cache is on `C:` but the project is on `D:`. Kotlin incremental compilation fails across drives with `IllegalArgumentException: this and base files have different roots`.

`android/gradle.properties` already disables incremental compilation for this reason:
```properties
kotlin.incremental=false
kotlin.incremental.useClasspathSnapshot=false
kotlin.compiler.execution.strategy=in-process
```
**Never re-enable these** unless both pub cache and project move to the same drive.

## Architecture

```
lib/
├── main.dart                     # entrypoint, Provider setup, light theme
├── models/
│   ├── ai_agent.dart             # AIAgent model (JSON serializable, copyWith)
│   └── chat_message.dart         # ChatMessage model
├── providers/
│   └── agent_provider.dart       # ChangeNotifier: agents, messages, persistence
├── pages/
│   ├── home_page.dart            # Scaffold + left Drawer + ChatPanel + settings strip
│   └── create_agent_page.dart    # Create/edit form (reused for both modes)
└── widgets/
    ├── agent_list_panel.dart     # Left drawer content: agent list + create button
    └── chat_panel.dart           # Message bubbles + input bar + empty state
```

## State management

- Single `AgentProvider` (ChangeNotifier) wraps the entire app via `main.dart`.
- `AgentProvider.init()` is async — loads agents from `shared_preferences` (JSON). It's called in the `create:` callback but the provider exposes data immediately; first frame may show empty state.
- Agent selection, message sending, and persistence all go through the provider. Never mutate agent state directly.
- Messages are **in-memory only** (not persisted). Lost on app restart.

## Persistence

- Agent list stored in `shared_preferences` under key `'agents'` as JSON array.
- Selected index stored under `'selectedAgentIndex'`.
- `_save()` writes both atomically after every mutation.
- API keys are stored in plaintext inside agent JSON — **not secure for production use**.

## UI conventions

- **Theme**: light, white background (`#F5F5F7`), primary blue `#4A6CF7`.
- **Drawer**: left-side `drawer` (not `endDrawer`). The drawer body is a `Row` of `[AgentListPanel (78% width), transparent spacer (tap-to-dismiss)]`. Menu icon is on the **right** side of the AppBar.
- **Create from empty area**: `AgentListPanel` wraps the list content in a `GestureDetector` — tapping any empty area navigates to `CreateAgentPage`.
- **Settings**: `HomePage` shows a small "设置" button strip below the AppBar when an agent is selected. It navigates to `CreateAgentPage(editAgent: agent)`.
- **API Key field**: visible on the create/edit form, toggle visibility with eye icon, stored in `AIAgent.apiKey`.
- **`withOpacity` is deprecated** in Flutter 3.41. Use `withValues(alpha: ...)` instead in new code (existing code uses the deprecated form but compiles).
- `shared_preferences` returns `Future` — all mutations must be awaited. The provider's `_save()` handles this.

## Models

- `AIAgent.availableModels`: `['Claude', 'Gemini', 'DeepSeek', 'Kimi', 'MiniMax', 'ChatGPT', 'Doubao', 'GLM', 'Custom']`
- `AIAgent.copyWith()` supports `clearBackgroundImage: true` to explicitly null the image path.
- `ChatMessage` has no JSON serialization (never persisted).

## Chat simulation

AI replies are generated locally in `AgentProvider._generateReply()` with hardcoded response templates based on agent name/model/relationship. No real API calls exist yet. Memory rounds trim messages to `memoryRounds * 2` entries after each response.
