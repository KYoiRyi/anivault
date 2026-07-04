import 'package:flutter_test/flutter_test.dart';

import 'package:anivault/services/torrent_service.dart';

void main() {
  test('collapses repeated iOS LiveContainer document sandbox prefixes', () {
    PathResolver.configureForTesting(
      docDirPath: '/var/mobile/Containers/Data/Application/CURRENT/Documents',
      exeDirPath: '/app',
    );

    final resolved = PathResolver.resolve(
      '/var/mobile/Containers/Data/Application/CURRENT/Documents/'
      'Data/Application/OLD/Documents/'
      'Data/Application/OLD/Documents/'
      '[ANi] BanG Dream！YUME∞MITA - 01.mp4',
    );

    expect(
      resolved.replaceAll('\\', '/'),
      '/var/mobile/Containers/Data/Application/CURRENT/Documents/'
      'Data/Application/OLD/Documents/'
      '[ANi] BanG Dream！YUME∞MITA - 01.mp4',
    );
  });
}
