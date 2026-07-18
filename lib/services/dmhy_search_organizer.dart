import 'package:anivault/services/dmhy_result_grouper.dart';
import 'package:anivault/services/dmhy_search_service.dart';

typedef DmhyCanonicalResolver =
    Future<Map<String, String>> Function(List<DmhyAnimeGroup> groups);

class DmhySearchOrganizer {
  final DmhyResultGrouper grouper;
  final DmhyCanonicalResolver? canonicalResolver;

  DmhySearchOrganizer({DmhyResultGrouper? grouper, this.canonicalResolver})
    : grouper = grouper ?? DmhyResultGrouper();

  Future<List<DmhyAnimeGroup>> organize(
    Iterable<DmhySearchResult> results,
  ) async {
    final grouped = grouper.group(results);
    return refine(grouped);
  }

  Future<List<DmhyAnimeGroup>> refine(
    Iterable<DmhyAnimeGroup> grouped,
  ) async {
    final source = grouped.toList(growable: false);
    final resolver = canonicalResolver;
    if (resolver == null || source.length < 2) return source;
    // Different scripts have no token overlap; send every machine cluster.
    final candidates = source;
    try {
      final canonicalTitles = await resolver(candidates);
      if (canonicalTitles.isEmpty) return source;
      return grouper.mergeCanonical(source, canonicalTitles);
    } catch (_) {
      return source;
    }
  }

  static List<DmhyAnimeGroup> ambiguousGroups(List<DmhyAnimeGroup> groups) {
    final keys = <String>{
      for (final group in groups)
        if (group.confidence < 0.8) group.normalizedTitle,
    };
    for (var i = 0; i < groups.length; i++) {
      for (var j = i + 1; j < groups.length; j++) {
        if (_tokenSimilarity(
              groups[i].normalizedTitle,
              groups[j].normalizedTitle,
            ) >=
            0.5) {
          keys
            ..add(groups[i].normalizedTitle)
            ..add(groups[j].normalizedTitle);
        }
      }
    }
    return groups
        .where((group) => keys.contains(group.normalizedTitle))
        .toList(growable: false);
  }

  static double _tokenSimilarity(String a, String b) {
    final aTokens = a.split(' ').where((token) => token.length > 1).toSet();
    final bTokens = b.split(' ').where((token) => token.length > 1).toSet();
    if (aTokens.isEmpty || bTokens.isEmpty) return 0;
    final intersection = aTokens.intersection(bTokens).length;
    final union = aTokens.union(bTokens).length;
    return intersection / union;
  }
}
