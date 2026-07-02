import 'package:flutter_test/flutter_test.dart';

import 'package:anivault/services/anime_library_service.dart';

void main() {
  test('parses bracketed fansub filename through native Anitomy', () {
    final parsed = AnitomyFilenameParser().parse(
      r'/media/[Nekomoe kissaten][Sasayaku You ni Koi wo Utau][01][1080p][JPSC].mp4',
    );

    expect(parsed.releaseGroup, 'Nekomoe kissaten');
    expect(parsed.title, 'Sasayaku You ni Koi wo Utau');
    expect(parsed.episodeNumber, 1);
    expect(parsed.resolution, '1080p');
  });

  test('keeps native Anitomy season handling', () {
    final parsed = AnitomyFilenameParser().parse(
      r'/media/[VCB-Studio] Haikyuu!! 2nd Season [01][Ma10p_1080p][x265_flac].mkv',
    );

    expect(parsed.releaseGroup, 'VCB-Studio');
    expect(parsed.title, 'Haikyuu!!');
    expect(parsed.episodeNumber, 1);
    expect(parsed.resolution, '1080p');
  });

  test('parses multi-group filename through native Anitomy', () {
    final parsed = AnitomyFilenameParser().parse(
      '/media/\u3010Nekomoe kissaten\u3011&\u3010LoliHouse\u3011[Girls Band Cry][01][1080p][CHS].mkv',
    );

    expect(parsed.releaseGroup, 'Nekomoe kissaten');
    expect(parsed.title, 'LoliHouse');
    expect(parsed.episodeNumber, 1);
    expect(parsed.resolution, '1080p');
  });

  test('keeps native Anitomy title for movie extras', () {
    final parsed = AnitomyFilenameParser().parse(
      r'/media/[Nekomoe kissaten&LoliHouse] Chou Kaguya-hime! - ray MV v2 [WebRip 2160p HEVC-10bit AAC ASSx2].mkv',
    );

    expect(parsed.releaseGroup, 'Nekomoe kissaten&LoliHouse');
    expect(parsed.title, 'Chou Kaguya-hime! - ray MV');
    expect(parsed.episodeNumber, isNull);
    expect(parsed.resolution, '2160p');
  });

  test('preserves unicode title through native FFI', () {
    final parsed = AnitomyFilenameParser().parse(
      '/media/[ANi] BanG Dream\uFF01YUME\u221EMITA - 01 [1080P][Baha][WEB-DL][AAC AVC][CHT].mp4',
    );

    expect(parsed.releaseGroup, 'ANi');
    expect(parsed.title, 'BanG Dream\uFF01YUME\u221EMITA');
    expect(parsed.episodeNumber, 1);
    expect(parsed.resolution, '1080P');
  });
}
