import 'package:flutter_test/flutter_test.dart';

import 'package:anivault/services/startup_asset_service.dart';

void main() {
  test('startup image URLs are trimmed, filtered, and deduplicated', () {
    expect(
      StartupAssetService.uniqueUrls([
        null,
        '',
        '  ',
        ' https://cdn.example/cover.jpg ',
        'https://cdn.example/cover.jpg',
        'https://cdn.example/background.jpg',
      ]),
      ['https://cdn.example/cover.jpg', 'https://cdn.example/background.jpg'],
    );
  });
}
