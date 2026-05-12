import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'services/notification_service.dart';
import 'services/database_service.dart';
import 'services/locale_service.dart';
import 'services/plugin_manager.dart';
import 'providers/chat_provider.dart';
import 'providers/agent_provider.dart';
import 'providers/settings_provider.dart';
import 'l10n/app_localizations.dart';
import 'screens/chat_screen.dart';
import 'screens/agent_create_screen.dart';

final localeProvider = StateProvider<Locale?>((ref) => null);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final notificationService = NotificationService();
  await notificationService.initialize();

  await DatabaseService.migrateDefaultPersona(defaultSystemPersona);

  await PluginManager.instance.init();

  final initialLocale = await LocaleService.resolveLocale();

  runApp(
    ProviderScope(
      overrides: [
        notificationServiceProvider.overrideWithValue(notificationService),
        localeProvider.overrideWith((ref) => initialLocale),
      ],
      child: const AIApp(),
    ),
  );
}

class AIApp extends ConsumerWidget {
  const AIApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider) ?? const Locale('en');
    final agentState = ref.watch(agentProvider);
    final settings = ref.watch(settingsProvider);
    final primary = Color(settings.primaryColor);

    ThemeMode themeMode;
    switch (settings.themeMode) {
      case 'light': themeMode = ThemeMode.light; break;
      case 'dark': themeMode = ThemeMode.dark; break;
      default: themeMode = ThemeMode.system;
    }

    return MaterialApp(
      title: 'AI 记忆聊天',
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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: primary, brightness: Brightness.light),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: primary, brightness: Brightness.dark),
        useMaterial3: true,
      ),
      themeMode: themeMode,
      home: agentState.agents.isEmpty ? const OnboardingScreen() : const ChatScreen(),
    );
  }
}

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.person_add_alt, size: 80, color: Colors.indigo.shade300),
            const SizedBox(height: 24),
            const Text('创建你的第一个智能体', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('每个人工智能都是一个独特的伙伴', style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AgentCreateScreen())),
                icon: const Icon(Icons.add),
                label: const Text('创建智能体'),
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
