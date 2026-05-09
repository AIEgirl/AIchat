import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aichat/main.dart';

void main() {
  testWidgets('App loads with chat screen', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: AIApp()),
    );
    await tester.pump();
    expect(find.text('AI 记忆聊天'), findsOneWidget);
    expect(find.text('开始对话吧'), findsOneWidget);
  });
}
