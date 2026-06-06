import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'services/notification_service.dart';
import 'services/database_service.dart';
import 'services/locale_service.dart';
import 'services/plugin_manager.dart';
import 'providers/chat_provider.dart';
import 'providers/agent_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/memory_provider.dart';
import 'l10n/app_localizations.dart';
import 'theme/app_theme.dart';
import 'screens/chat_screen.dart';
import 'screens/agent_create_screen.dart';

final localeProvider = StateProvider<Locale?>((ref) => null);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Phase 0 — minimal sync init: DB + locale + notification (fire-and-forget)
  final dbFuture = DatabaseService.migrateDefaultPersona(defaultSystemPersona);

  // Fire notification init in background; don't block first frame
  final notificationService = NotificationService();
  final notificationInitFuture = notificationService.initialize();

  // Plugin manager can init async as well
  PluginManager.instance.init(); // no await — not critical for first frame

  final initialLocale = await LocaleService.resolveLocale();

  // Ensure DB migration finishes before providers need it
  await dbFuture;

  runApp(
    ProviderScope(
      overrides: [
        notificationServiceProvider.overrideWithValue(notificationService),
        localeProvider.overrideWith((ref) => initialLocale),
      ],
      child: const AIApp(),
    ),
  );

  // Complete notification init after first frame (won't block UI)
  await notificationInitFuture;
}

class AIApp extends ConsumerWidget {
  const AIApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider) ?? const Locale('en');
    final settings = ref.watch(settingsProvider);
    final primary = Color(settings.primaryColor);

    ThemeMode themeMode;
    switch (settings.themeMode) {
      case 'light':
        themeMode = ThemeMode.light;
      case 'dark':
        themeMode = ThemeMode.dark;
      default:
        themeMode = ThemeMode.system;
    }

    return MaterialApp(
      title: 'AI Memory Chat',
      debugShowCheckedModeBanner: false,
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en'),
        Locale('zh'),
      ],
      theme: AppTheme.light(primary),
      darkTheme: AppTheme.dark(primary),
      themeMode: themeMode,
      // Keyboard shortcut for sending message with Ctrl+Enter
      shortcuts: {
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.enter):
            const ActivateIntent(),
      },
      home: const _AppShell(),
    );
  }
}

/// Shell that decides onboarding vs chat, and wraps keyboard shortcuts.
class _AppShell extends ConsumerWidget {
  const _AppShell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final agentState = ref.watch(agentProvider);

    if (agentState.agents.isEmpty) {
      return const OnboardingScreen();
    }
    return const ChatScreen();
  }
}

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    shape: BoxShape.circle,
                    boxShadow: AppTheme.shadowMd,
                  ),
                  child: Icon(Icons.person_add_alt,
                      size: 56, color: scheme.onPrimaryContainer),
                ),
                const SizedBox(height: 32),
                Text('Create your first agent',
                    style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface)),
                const SizedBox(height: 8),
                Text('Each AI is a unique companion',
                    style: TextStyle(
                        fontSize: 14, color: scheme.onSurfaceVariant)),
                const SizedBox(height: 40),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const AgentCreateScreen())),
                    icon: const Icon(Icons.add),
                    label: const Text('Create Agent'),
                  ),
                ),
              ]),
        ),
      ),
    );
  }
}
