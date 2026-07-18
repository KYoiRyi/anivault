import 'package:flutter_test/flutter_test.dart';

import 'package:anivault/services/dmhy_result_grouper.dart';
import 'package:anivault/services/dmhy_search_organizer.dart';
import 'package:anivault/services/dmhy_search_service.dart';

void main() {
  DmhySearchResult release(String title, String hash) => DmhySearchResult(
    title: title,
    category: '動畫',
    publishedAt: '2026/07/01 10:00',
    size: '500MB',
    publisher: 'Group',
    detailsUrl: Uri.parse('https://dmhy.org/topics/view/$hash.html'),
    magnetUri: 'magnet:?xt=urn:btih:$hash',
  );

  test('sends ambiguous aliases once and merges AI canonical titles', () async {
    final grouper = DmhyResultGrouper(
      parser: (title) => DmhyReleaseMetadata(
        animeTitle: title,
        normalizedTitle: title.toLowerCase(),
        seasonNumber: 1,
        episodeNumber: 1,
        releaseGroup: null,
        confidence: 0.4,
      ),
    );
    var calls = 0;
    final organizer = DmhySearchOrganizer(
      grouper: grouper,
      canonicalResolver: (groups) async {
        calls++;
        return {
          for (final group in groups)
            group.normalizedTitle: 'BanG Dream! YUME MITA',
        };
      },
    );
    final groups = await organizer.organize([
      release('YUME MITA', 'AAA'),
      release('YUME MITA Season', 'BBB'),
    ]);
    expect(calls, 1);
    expect(groups, hasLength(1));
    expect(groups.single.releaseCount, 2);
  });

  test('falls back to Anitomy groups when AI resolver fails', () async {
    final grouper = DmhyResultGrouper(
      parser: (title) => DmhyReleaseMetadata(
        animeTitle: title,
        normalizedTitle: title.toLowerCase(),
        seasonNumber: null,
        episodeNumber: null,
        releaseGroup: null,
        confidence: 0.4,
      ),
    );
    final organizer = DmhySearchOrganizer(
      grouper: grouper,
      canonicalResolver: (_) => Future.error(StateError('offline')),
    );
    final groups = await organizer.organize([
      release('Title A', 'AAA'),
      release('Title B', 'BBB'),
    ]);
    expect(groups, hasLength(2));
  });
}
