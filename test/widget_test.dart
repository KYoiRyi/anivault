import 'package:flutter_test/flutter_test.dart';

import 'package:anivault/main.dart';

void main() {
  testWidgets('shows the premium library shell', (tester) async {
    await tester.pumpWidget(const AniVaultApp());

    expect(find.text('Home'), findsWidgets);
    expect(find.text('Library'), findsWidgets);
    expect(find.text('Settings'), findsWidgets);
    expect(find.text('开始您的漫游之旅'), findsOneWidget);

    // Switch to Library tab
    await tester.tap(find.text('Library').first);
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('No media imported'), findsOneWidget);
  });
}
