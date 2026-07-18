import 'package:flutter_test/flutter_test.dart';

import 'package:anivault/services/dmhy_result_grouper.dart';
import 'package:anivault/services/dmhy_search_service.dart';

void main() {
  DmhySearchResult release(String title, String hash, String date) {
    return DmhySearchResult(
      title: title,
      category: '動畫',
      publishedAt: date,
      size: '500MB',
      publisher: 'Group',
      detailsUrl: Uri.parse('https://dmhy.org/topics/view/$hash.html'),
      magnetUri: 'magnet:?xt=urn:btih:$hash&tr=https://tracker.example',
    );
  }

  DmhyReleaseMetadata parse(String title) {
    final episode = int.parse(RegExp(r'EP(\d+)').firstMatch(title)!.group(1)!);
    final season = int.parse(RegExp(r'S(\d+)').firstMatch(title)!.group(1)!);
    return DmhyReleaseMetadata(
      animeTitle: 'BanG Dream! YUME MITA',
      normalizedTitle: 'bang dream yume mita',
      seasonNumber: season,
      episodeNumber: episode,
      releaseGroup: null,
      confidence: 1,
    );
  }

  test('groups releases by anime, season, and episode', () {
    final grouper = DmhyResultGrouper(parser: parse);
    final groups = grouper.group([
      release('S1 EP2 version A', 'AAA', '2026/07/02 10:00'),
      release('S1 EP2 version B', 'BBB', '2026/07/03 10:00'),
      release('S1 EP1 version A', 'CCC', '2026/07/01 10:00'),
      release('S2 EP1 version A', 'DDD', '2026/07/04 10:00'),
    ]);

    expect(groups, hasLength(1));
    expect(groups.single.releaseCount, 4);
    expect(groups.single.seasons.map((item) => item.seasonNumber), [1, 2]);
    expect(
      groups.single.seasons.first.episodes.map((item) => item.episodeNumber),
      [2, 1],
    );
    expect(
      groups.single.seasons.first.episodes.first.releases.first.title,
      'S1 EP2 version B',
    );
  });

  test('deduplicates identical infohashes before grouping', () {
    final groups = DmhyResultGrouper(parser: parse).group([
      release('S1 EP1 version A', 'SAME', '2026/07/01 10:00'),
      release('S1 EP1 duplicate row', 'SAME', '2026/07/02 10:00'),
    ]);
    expect(groups.single.releaseCount, 1);
  });

  test('merges Anitomy aliases using canonical AI titles', () {
    final grouper = DmhyResultGrouper(
      parser: (title) {
        final alias = title.startsWith('A') ? 'YUME MITA' : 'YUME Mita!';
        return DmhyReleaseMetadata(
          animeTitle: alias,
          normalizedTitle: alias.toLowerCase().replaceAll('!', ''),
          seasonNumber: 1,
          episodeNumber: 1,
          releaseGroup: null,
          confidence: 0.6,
        );
      },
    );
    final grouped = grouper.group([
      release('A release', 'AAA', '2026/07/01 10:00'),
      release('B release', 'BBB', '2026/07/02 10:00'),
    ]);
    final merged = grouper.mergeCanonical(grouped, {
      for (final group in grouped)
        group.normalizedTitle: 'BanG Dream! YUME MITA',
    });
    expect(merged, hasLength(1));
    expect(merged.single.releaseCount, 2);
  });
}
