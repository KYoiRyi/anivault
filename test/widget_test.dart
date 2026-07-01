import 'package:flutter_test/flutter_test.dart';

import 'package:anivault/main.dart';

void main() {
  testWidgets('shows the premium library shell', (tester) async {
    await tester.pumpWidget(const AniVaultApp());

    expect(find.text('Library'), findsWidgets);
    expect(find.text('Network'), findsNothing);
    expect(find.text('Downloads'), findsNothing);
    expect(find.text('No media imported'), findsOneWidget);
  });
}
