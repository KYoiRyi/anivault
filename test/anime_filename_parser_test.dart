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

  test('parses Chinese fansub filename with full-width brackets', () {
    final parsed = AnimeFilenameParser().parse(
      r'/media/【喵萌奶茶屋】&【千夏字幕组】[Girls Band Cry][01][1080p][简日内嵌].mkv',
    );

    expect(parsed.releaseGroup, '喵萌奶茶屋');
    expect(parsed.title, 'Girls Band Cry');
    expect(parsed.episodeNumber, 1);
    expect(parsed.resolution, '1080p');
  });

  test('strips music video suffix from unknown-episode movie filenames', () {
    final parsed = AnimeFilenameParser().parse(
      r'/media/[Nekomoe kissaten&LoliHouse] Chou Kaguya-hime! - ray MV v2 [WebRip 2160p HEVC-10bit AAC ASSx2].mkv',
    );

    expect(parsed.releaseGroup, 'Nekomoe kissaten&LoliHouse');
    expect(parsed.title, 'Chou Kaguya-hime!');
    expect(parsed.episodeNumber, isNull);
    expect(parsed.resolution, '2160p');
  });
}
