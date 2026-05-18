import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:colatranslate/main.dart';

void main() {
  testWidgets('renders cola translate tabs', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: ColaTranslateApp()));

    expect(find.text('文本翻译'), findsOneWidget);
    expect(find.text('对话模式'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
  });
}
