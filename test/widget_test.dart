import 'package:flutter_test/flutter_test.dart';

import 'package:anivault/main.dart';

void main() {
  testWidgets('shows the main navigation sections', (tester) async {
    await tester.pumpWidget(const AniVaultApp());

    expect(find.text('Library'), findsWidgets);
    expect(find.text('Network'), findsOneWidget);
    expect(find.text('Downloads'), findsOneWidget);

    await tester.tap(find.text('Downloads'));
    await tester.pumpAndSettle();
    expect(find.text('No downloads yet.'), findsOneWidget);

    await tester.tap(find.text('Network'));
    await tester.pumpAndSettle();
    expect(
      find.text('Connect to a network share to browse files.'),
      findsOneWidget,
    );
  });
}
