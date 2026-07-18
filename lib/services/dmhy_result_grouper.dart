import 'package:anivault/services/anime_library_service.dart';
import 'package:anivault/services/dmhy_search_service.dart';

class DmhyReleaseMetadata {
  final String animeTitle;
  final String normalizedTitle;
  final int? seasonNumber;
  final int? episodeNumber;
  final String? releaseGroup;
  final double confidence;

  const DmhyReleaseMetadata({
    required this.animeTitle,
    required this.normalizedTitle,
    required this.seasonNumber,
    required this.episodeNumber,
    required this.releaseGroup,
    required this.confidence,
  });
}

class DmhyEpisodeGroup {
  final int? episodeNumber;
  final List<DmhySearchResult> releases;

  const DmhyEpisodeGroup({required this.episodeNumber, required this.releases});
}

class DmhySeasonGroup {
  final int? seasonNumber;
  final List<DmhyEpisodeGroup> episodes;

  const DmhySeasonGroup({required this.seasonNumber, required this.episodes});
}

class DmhyAnimeGroup {
  final String title;
  final String normalizedTitle;
  final double confidence;
  final List<DmhySeasonGroup> seasons;

  const DmhyAnimeGroup({
    required this.title,
    required this.normalizedTitle,
    required this.confidence,
    required this.seasons,
  });

  int get releaseCount => seasons.fold(
    0,
    (sum, season) =>
        sum +
        season.episodes.fold(
          0,
          (sum, episode) => sum + episode.releases.length,
        ),
  );
}

typedef DmhyMetadataParser = DmhyReleaseMetadata Function(String title);

class DmhyResultGrouper {
  final DmhyMetadataParser _parser;

  DmhyResultGrouper({DmhyMetadataParser? parser})
    : _parser = parser ?? _parseWithAnitomy;

  List<DmhyAnimeGroup> group(Iterable<DmhySearchResult> source) {
    final unique = <String, DmhySearchResult>{};
    for (final result in source) {
      unique.putIfAbsent(_magnetIdentity(result.magnetUri), () => result);
    }

    final animeBuckets = <String, _AnimeBucket>{};
    for (final result in unique.values) {
      final metadata = _parser(result.title);
      final key = metadata.normalizedTitle.isEmpty
          ? _fallbackNormalize(metadata.animeTitle)
          : metadata.normalizedTitle;
      final bucket = animeBuckets.putIfAbsent(
        key,
        () => _AnimeBucket(
          title: metadata.animeTitle,
          normalizedTitle: key,
          confidence: metadata.confidence,
        ),
      );
      bucket.confidence = bucket.confidence < metadata.confidence
          ? bucket.confidence
          : metadata.confidence;
      final season = bucket.seasons.putIfAbsent(
        metadata.seasonNumber,
        () => <int?, List<DmhySearchResult>>{},
      );
      season.putIfAbsent(metadata.episodeNumber, () => []).add(result);
    }

    final groups =
        animeBuckets.values.map((bucket) {
          final seasons =
              bucket.seasons.entries.map((seasonEntry) {
                final episodes =
                    seasonEntry.value.entries.map((episodeEntry) {
                      final releases = [
                        ...episodeEntry.value,
                      ]..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
                      return DmhyEpisodeGroup(
                        episodeNumber: episodeEntry.key,
                        releases: releases,
                      );
                    }).toList()..sort(
                      (a, b) => _compareNullableNumberDesc(
                        a.episodeNumber,
                        b.episodeNumber,
                      ),
                    );
                return DmhySeasonGroup(
                  seasonNumber: seasonEntry.key,
                  episodes: episodes,
                );
              }).toList()..sort(
                (a, b) =>
                    _compareNullableNumberAsc(a.seasonNumber, b.seasonNumber),
              );
          return DmhyAnimeGroup(
            title: bucket.title,
            normalizedTitle: bucket.normalizedTitle,
            confidence: bucket.confidence,
            seasons: seasons,
          );
        }).toList()..sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
    return groups;
  }

  static DmhyReleaseMetadata _parseWithAnitomy(String title) {
    final parsed = AnitomyFilenameParser().parse(title);
    final normalized = parsed.normalizedTitle;
    final extracted = parsed.title.trim();
    final confidence =
        normalized.isNotEmpty &&
            extracted.length >= 3 &&
            extracted.toLowerCase() != title.trim().toLowerCase()
        ? 1.0
        : 0.45;
    return DmhyReleaseMetadata(
      animeTitle: extracted.isEmpty ? title.trim() : extracted,
      normalizedTitle: normalized,
      seasonNumber: parsed.seasonNumber,
      episodeNumber: parsed.episodeNumber,
      releaseGroup: parsed.releaseGroup,
      confidence: confidence,
    );
  }

  static String _magnetIdentity(String magnet) {
    try {
      final xt = Uri.parse(magnet).queryParameters['xt'];
      if (xt != null && xt.trim().isNotEmpty) return xt.toLowerCase();
    } catch (_) {}
    return magnet.trim().toLowerCase();
  }

  static String _fallbackNormalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\u3040-\u30ff\u3400-\u9fff]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static int _compareNullableNumberAsc(int? a, int? b) {
    if (a == null) return b == null ? 0 : 1;
    if (b == null) return -1;
    return a.compareTo(b);
  }

  static int _compareNullableNumberDesc(int? a, int? b) {
    if (a == null) return b == null ? 0 : 1;
    if (b == null) return -1;
    return b.compareTo(a);
  }
}

class _AnimeBucket {
  final String title;
  final String normalizedTitle;
  double confidence;
  final Map<int?, Map<int?, List<DmhySearchResult>>> seasons = {};

  _AnimeBucket({
    required this.title,
    required this.normalizedTitle,
    required this.confidence,
  });
}
