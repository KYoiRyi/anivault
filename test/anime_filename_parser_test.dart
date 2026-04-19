import 'package:flutter_test/flutter_test.dart';

import 'package:anivault/services/anime_library_service.dart';

void main() {
  test('parses bracketed fansub filename', () {
    final parsed = AnimeFilenameParser().parse(
      r'/media/[Nekomoe kissaten][Sasayaku You ni Koi wo Utau][01][1080p][JPSC].mp4',
    );

    expect(parsed.releaseGroup, 'Nekomoe kissaten');
    expect(parsed.title, 'Sasayaku You ni Koi wo Utau');
    expect(parsed.episodeNumber, 1);
    expect(parsed.resolution, '1080p');
  });

  test('parses VCB style filename', () {
    final parsed = AnimeFilenameParser().parse(
      r'/media/[VCB-Studio] Haikyuu!! 2nd Season [01][Ma10p_1080p][x265_flac].mkv',
    );

    expect(parsed.releaseGroup, 'VCB-Studio');
    expect(parsed.title, 'Haikyuu!! 2nd Season');
    expect(parsed.episodeNumber, 1);
    expect(parsed.resolution, '1080p');
  });
}
