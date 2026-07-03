import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:anivault/services/anitomy_native.dart';
import 'package:anivault/services/ai_agent_service.dart';
import 'package:anivault/services/logger_service.dart';
import 'package:anivault/services/vfs_service.dart';

class ParsedAnimeFile {
  final String path;
  final String fileName;
  final String title;
  final String normalizedTitle;
  final int? episodeNumber;
  final String episodeKey;
  final String? releaseGroup;
  final String? resolution;

  const ParsedAnimeFile({
    required this.path,
    required this.fileName,
    required this.title,
    required this.normalizedTitle,
    required this.episodeNumber,
    required this.episodeKey,
    this.releaseGroup,
    this.resolution,
  });
}

class AnimeMediaFile {
  final String path;
  final String fileName;
  final String parsedTitle;
  final String? releaseGroup;
  final String? resolution;

  const AnimeMediaFile({
    required this.path,
    required this.fileName,
    required this.parsedTitle,
    this.releaseGroup,
    this.resolution,
  });
}

class AnimeEpisodeGroup {
  final String key;
  final int? number;
  final String title;
  final List<AnimeMediaFile> files;

  const AnimeEpisodeGroup({
    required this.key,
    required this.number,
    required this.title,
    required this.files,
  });
}

class AnimeSeries {
  final String id;
  final int? anidbId;
  final int? anilistId;
  final String title;
  final String sortTitle;
  final String? coverUrl;
  final String? description;
  final int? averageScore;
  final int? meanScore;
  final String? format;
  final String? status;
  final String? season;
  final int? startYear;
  final int? duration;
  final List<String> genres;
  final bool isUnknown;
  final bool isResolving;
  final List<AnimeEpisodeGroup> episodes;

  const AnimeSeries({
    required this.id,
    this.anidbId,
    required this.anilistId,
    required this.title,
    required this.sortTitle,
    required this.coverUrl,
    this.description,
    this.averageScore,
    this.meanScore,
    this.format,
    this.status,
    this.season,
    this.startYear,
    this.duration,
    this.genres = const [],
    required this.isUnknown,
    this.isResolving = false,
    required this.episodes,
  });

  int get fileCount =>
      episodes.fold(0, (sum, episode) => sum + episode.files.length);

  AnimeSeries copyWith({bool? isResolving}) {
    return AnimeSeries(
      id: id,
      anidbId: anidbId,
      anilistId: anilistId,
      title: title,
      sortTitle: sortTitle,
      coverUrl: coverUrl,
      description: description,
      averageScore: averageScore,
      meanScore: meanScore,
      format: format,
      status: status,
      season: season,
      startYear: startYear,
      duration: duration,
      genres: genres,
      isUnknown: isUnknown,
      isResolving: isResolving ?? this.isResolving,
      episodes: episodes,
    );
  }
}

class AniListSearchResult {
  static const currentCacheVersion = 2;

  final int id;
  final String title;
  final String? englishTitle;
  final String? nativeTitle;
  final String? coverUrl;
  final String? description;
  final int? averageScore;
  final int? meanScore;
  final String? format;
  final String? status;
  final String? season;
  final int? duration;
  final List<String> genres;
  final int? startYear;
  final int? episodes;
  final double score;
  final int cacheVersion;

  const AniListSearchResult({
    required this.id,
    required this.title,
    this.englishTitle,
    this.nativeTitle,
    this.coverUrl,
    this.description,
    this.averageScore,
    this.meanScore,
    this.format,
    this.status,
    this.season,
    this.duration,
    this.genres = const [],
    this.startYear,
    this.episodes,
    required this.score,
    this.cacheVersion = currentCacheVersion,
  });

  String get displayTitle => englishTitle?.isNotEmpty == true
      ? englishTitle!
      : nativeTitle?.isNotEmpty == true
      ? nativeTitle!
      : title;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'englishTitle': englishTitle,
      'nativeTitle': nativeTitle,
      'coverUrl': coverUrl,
      'description': description,
      'averageScore': averageScore,
      'meanScore': meanScore,
      'format': format,
      'status': status,
      'season': season,
      'duration': duration,
      'genres': genres,
      'startYear': startYear,
      'episodes': episodes,
      'score': score,
      'cacheVersion': cacheVersion,
    };
  }

  factory AniListSearchResult.fromJson(Map<String, dynamic> json) {
    return AniListSearchResult(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: json['title'] as String? ?? '',
      englishTitle: json['englishTitle'] as String?,
      nativeTitle: json['nativeTitle'] as String?,
      coverUrl: json['coverUrl'] as String?,
      description: json['description'] as String?,
      averageScore: (json['averageScore'] as num?)?.toInt(),
      meanScore: (json['meanScore'] as num?)?.toInt(),
      format: json['format'] as String?,
      status: json['status'] as String?,
      season: json['season'] as String?,
      duration: (json['duration'] as num?)?.toInt(),
      genres:
          (json['genres'] as List?)?.whereType<String>().toList() ?? const [],
      startYear: (json['startYear'] as num?)?.toInt(),
      episodes: (json['episodes'] as num?)?.toInt(),
      score: (json['score'] as num?)?.toDouble() ?? 0,
      cacheVersion: (json['cacheVersion'] as num?)?.toInt() ?? 0,
    );
  }

  bool get hasCurrentMetadata => cacheVersion >= currentCacheVersion;
}

typedef AniListMatchResolver =
    Future<AniListSearchResult?> Function(
      String parsedTitle,
      List<AniListSearchResult> candidates,
    );

class AnimeLibraryService extends ChangeNotifier {
  static final AnimeLibraryService _instance = AnimeLibraryService._internal();
  factory AnimeLibraryService() => _instance;
  AnimeLibraryService._internal();

  static const _graphqlUrl = 'https://graphql.anilist.co';
  static const _detailsCacheFile = 'anilist-details-cache.json';
  static const _selectionCacheFile = 'anilist-selection-cache.json';
  static const _unresolvedCacheFile = 'anilist-unresolved-cache.json';
  static const _userAgent = 'AniVault/1.0';

  final _filenameParser = AnitomyFilenameParser();
  final Map<int, AniListSearchResult> _detailsCache = {};
  final Map<String, int> _selectionCache = {};
  final Map<String, String> _unresolvedCache = {};
  final Set<String> _resolvingKeys = {};
  DateTime? _lastGraphQlRequest;

  bool _isReady = false;
  bool _isScanning = false;
  bool _isResolvingUnresolved = false;
  String? _lastError;
  List<AnimeSeries> _series = [];
  List<String> _lastRefreshPaths = const [];
  String _lastLanguageCode = 'en';

  bool get isReady => _isReady;
  bool get isScanning => _isScanning;
  String? get lastError => _lastError;
  List<AnimeSeries> get series => List.unmodifiable(_series);

  Future<void> initialize() async {
    if (_isReady) return;
    await _loadDetailsCache();
    await _loadSelectionCache();
    await _loadUnresolvedCache();
    _isReady = true;
    notifyListeners();
  }

  Future<void> refreshLibrary(
    List<String> paths, {
    required String languageCode,
    AniListMatchResolver? resolveAmbiguousMatch,
  }) async {
    _lastRefreshPaths = List.unmodifiable(paths);
    _lastLanguageCode = languageCode;
    _isScanning = true;
    _lastError = null;
    notifyListeners();

    try {
      await initialize();
      final parsedFiles = paths.map(_filenameParser.parse).toList();
      final titleBuckets = <String, List<ParsedAnimeFile>>{};
      for (final parsed in parsedFiles) {
        titleBuckets.putIfAbsent(parsed.normalizedTitle, () => []).add(parsed);
      }
      _series = _buildUnknownSeries(titleBuckets);
      notifyListeners();

      final knownBuckets = <int, List<ParsedAnimeFile>>{};
      final unmatchedBuckets = <String, List<ParsedAnimeFile>>{};

      for (final entry in titleBuckets.entries) {
        final titleFiles = entry.value;
        final parsedTitle = titleFiles.first.title;
        final match = await _resolveTitle(
          parsedTitle,
          entry.key,
          resolveAmbiguousMatch,
        );
        if (match == null) {
          _unresolvedCache[entry.key] = titleFiles.first.path;
          unmatchedBuckets.putIfAbsent(entry.key, () => []).addAll(titleFiles);
          continue;
        }
        _unresolvedCache.remove(entry.key);
        knownBuckets.putIfAbsent(match.id, () => []).addAll(titleFiles);
      }
      await _saveUnresolvedCache();

      final nextSeries = <AnimeSeries>[];

      for (final entry in knownBuckets.entries) {
        final details = _detailsCache[entry.key];
        final files = entry.value;
        final title = _titleFor(details, languageCode) ?? files.first.title;
        nextSeries.add(
          AnimeSeries(
            id: 'anilist:${entry.key}',
            anidbId: null,
            anilistId: entry.key,
            title: title,
            sortTitle: _normalizeTitle(title),
            coverUrl: details?.coverUrl,
            description: details?.description,
            averageScore: details?.averageScore,
            meanScore: details?.meanScore,
            format: details?.format,
            status: details?.status,
            season: details?.season,
            startYear: details?.startYear,
            duration: details?.duration,
            genres: details?.genres ?? const [],
            isUnknown: false,
            isResolving: false,
            episodes: _groupEpisodes(files),
          ),
        );
      }

      for (final entry in unmatchedBuckets.entries) {
        final files = entry.value;
        final title = files.first.title;
        nextSeries.add(
          AnimeSeries(
            id: 'scraped:${entry.key}',
            anidbId: null,
            anilistId: null,
            title: title,
            sortTitle: 'zzzz_${_normalizeTitle(title)}',
            coverUrl: null,
            description: null,
            averageScore: null,
            meanScore: null,
            format: null,
            status: null,
            season: null,
            startYear: null,
            duration: null,
            genres: const [],
            isUnknown: true,
            isResolving: _resolvingKeys.contains(entry.key),
            episodes: _groupEpisodes(files),
          ),
        );
      }

      nextSeries.sort((a, b) => a.sortTitle.compareTo(b.sortTitle));
      _series = nextSeries;
    } catch (e) {
      _lastError = e.toString();
      LoggerService().log('[Library] AniList scrape failed: $e');
    } finally {
      _isScanning = false;
      notifyListeners();
      unawaited(retryUnresolvedQueue(paths: paths, languageCode: languageCode));
    }
  }

  Future<void> retryUnresolvedQueue({
    List<String>? paths,
    String? languageCode,
  }) async {
    final effectivePaths = paths ?? _lastRefreshPaths;
    if (effectivePaths.isNotEmpty) {
      _lastRefreshPaths = List.unmodifiable(effectivePaths);
    }
    if (languageCode != null && languageCode.isNotEmpty) {
      _lastLanguageCode = languageCode;
    }
    await _resolveUnresolvedInBackground(
      effectivePaths,
      languageCode ?? _lastLanguageCode,
    );
  }

  Future<AniListSearchResult?> _resolveTitle(
    String parsedTitle,
    String normalizedTitle,
    AniListMatchResolver? resolver,
  ) async {
    final cachedId = _selectionCache[normalizedTitle];
    if (cachedId != null) {
      final cached = await _fetchAnimeById(cachedId);
      if (cached != null) return cached;
    }

    final candidates = await _searchAnime(parsedTitle, normalizedTitle);
    if (candidates.isEmpty) return null;

    return _selectAndCacheCandidate(
      parsedTitle,
      normalizedTitle,
      candidates,
      resolver,
    );
  }

  Future<void> _resolveUnresolvedInBackground(
    List<String> paths,
    String languageCode,
  ) async {
    await initialize();
    if (_isResolvingUnresolved || _unresolvedCache.isEmpty) return;
    await AiAgentService().initialize();
    if (!AiAgentService().config.isReady) {
      _clearResolvingState();
      return;
    }

    _isResolvingUnresolved = true;
    var changed = false;
    try {
      final availablePaths = paths.toSet();
      final entries = Map<String, String>.from(_unresolvedCache).entries;
      for (final entry in entries) {
        final normalizedTitle = entry.key;
        final path = entry.value;
        _setResolving(normalizedTitle, true);
        if ((availablePaths.isNotEmpty && !availablePaths.contains(path)) ||
            !VFSService().existsSync(path)) {
          _unresolvedCache.remove(normalizedTitle);
          _setResolving(normalizedTitle, false);
          changed = true;
          continue;
        }

        final parsed = _filenameParser.parse(path);
        final inferredTitle = await AiAgentService().inferAnimeTitle(parsed);
        if (inferredTitle == null) {
          _setResolving(normalizedTitle, false);
          continue;
        }
        final inferredNormalizedTitle = _normalizeTitle(inferredTitle);
        final candidates = await _searchAnime(
          inferredTitle,
          inferredNormalizedTitle,
        );
        if (candidates.isEmpty) {
          _setResolving(normalizedTitle, false);
          continue;
        }

        final confident =
            candidates.first.score >= 0.82 ||
            (candidates.length == 1 && candidates.first.score >= 0.55);
        if (!confident) {
          _setResolving(normalizedTitle, false);
          continue;
        }

        final selected = candidates.first;
        _detailsCache[selected.id] = selected;
        _selectionCache[normalizedTitle] = selected.id;
        _selectionCache[inferredNormalizedTitle] = selected.id;
        _unresolvedCache.remove(normalizedTitle);
        _setResolving(normalizedTitle, false);
        changed = true;
        LoggerService().log(
          '[AI Agent] "${parsed.title}" resolved as "${selected.displayTitle}"',
        );
      }

      if (changed) {
        await _saveDetailsCache();
        await _saveSelectionCache();
        await _saveUnresolvedCache();
        if (paths.isNotEmpty) {
          await refreshLibrary(paths, languageCode: languageCode);
        }
      }
    } catch (e) {
      LoggerService().log('[AI Agent] Background unresolved retry failed: $e');
    } finally {
      _clearResolvingState(notify: false);
      _isResolvingUnresolved = false;
      notifyListeners();
    }
  }

  Future<AniListSearchResult?> _selectAndCacheCandidate(
    String parsedTitle,
    String normalizedTitle,
    List<AniListSearchResult> candidates,
    AniListMatchResolver? resolver,
  ) async {
    final selected = await _selectCandidate(parsedTitle, candidates, resolver);
    if (selected == null) return null;

    _detailsCache[selected.id] = selected;
    _selectionCache[normalizedTitle] = selected.id;
    await _saveDetailsCache();
    await _saveSelectionCache();
    return selected;
  }

  Future<AniListSearchResult?> _selectCandidate(
    String parsedTitle,
    List<AniListSearchResult> candidates,
    AniListMatchResolver? resolver,
  ) async {
    final confident =
        candidates.first.score >= 0.92 ||
        (candidates.length == 1 && candidates.first.score >= 0.72);
    return confident
        ? candidates.first
        : await resolver?.call(parsedTitle, candidates.take(6).toList());
  }

  List<AnimeSeries> _buildUnknownSeries(
    Map<String, List<ParsedAnimeFile>> titleBuckets,
  ) {
    final nextSeries = <AnimeSeries>[];
    for (final entry in titleBuckets.entries) {
      final files = entry.value;
      final title = files.first.title;
      nextSeries.add(
        AnimeSeries(
          id: 'scraped:${entry.key}',
          anidbId: null,
          anilistId: null,
          title: title,
          sortTitle: 'zzzz_${_normalizeTitle(title)}',
          coverUrl: null,
          description: null,
          averageScore: null,
          meanScore: null,
          format: null,
          status: null,
          season: null,
          startYear: null,
          duration: null,
          genres: const [],
          isUnknown: true,
          isResolving: _resolvingKeys.contains(entry.key),
          episodes: _groupEpisodes(files),
        ),
      );
    }
    nextSeries.sort((a, b) => a.sortTitle.compareTo(b.sortTitle));
    return nextSeries;
  }

  void _setResolving(String normalizedTitle, bool isResolving) {
    if (isResolving) {
      _resolvingKeys.add(normalizedTitle);
    } else {
      _resolvingKeys.remove(normalizedTitle);
    }
    final id = 'scraped:$normalizedTitle';
    _series = [
      for (final series in _series)
        series.id == id ? series.copyWith(isResolving: isResolving) : series,
    ];
    notifyListeners();
  }

  void _clearResolvingState({bool notify = true}) {
    _resolvingKeys.clear();
    _series = [
      for (final series in _series)
        series.isResolving ? series.copyWith(isResolving: false) : series,
    ];
    if (notify) notifyListeners();
  }

  Future<List<AniListSearchResult>> _searchAnime(
    String title,
    String normalizedTitle,
  ) async {
    if (title.trim().isEmpty) return const [];
    final data = await _postGraphQl(
      r'''
query ($search: String!, $perPage: Int) {
  Page(page: 1, perPage: $perPage) {
    media(search: $search, type: ANIME, isAdult: false) {
      id
      title { romaji english native userPreferred }
      description(asHtml: false)
      coverImage { large extraLarge }
      startDate { year }
      episodes
      duration
      averageScore
      meanScore
      format
      status
      season
      genres
    }
  }
}
''',
      {'search': title, 'perPage': 8},
    ).timeout(const Duration(seconds: 10));

    final page = data['Page'];
    final media = page is Map ? page['media'] : null;
    if (media is! List) return const [];

    final results = media
        .whereType<Map>()
        .map((raw) => _parseSearchResult(raw, normalizedTitle))
        .where((result) => result.title.isNotEmpty)
        .toList();
    results.sort((a, b) => b.score.compareTo(a.score));
    return results.where((result) => result.score >= 0.34).toList();
  }

  Future<AniListSearchResult?> _fetchAnimeById(int id) async {
    final cached = _detailsCache[id];
    if (cached != null && cached.hasCurrentMetadata) return cached;

    Map<String, dynamic> data;
    try {
      data = await _postGraphQl(
        r'''
query ($id: Int!) {
  Media(id: $id, type: ANIME) {
    id
    title { romaji english native userPreferred }
    description(asHtml: false)
    coverImage { large extraLarge }
    startDate { year }
    episodes
    duration
    averageScore
    meanScore
    format
    status
    season
    genres
  }
}
''',
        {'id': id},
      ).timeout(const Duration(seconds: 10));
    } catch (e) {
      if (cached != null) {
        LoggerService().log('[AniList] Using stale metadata for id=$id: $e');
        return cached;
      }
      rethrow;
    }

    final raw = data['Media'];
    if (raw is! Map) return null;
    final result = _parseSearchResult(raw, '');
    _detailsCache[id] = result;
    await _saveDetailsCache();
    return result;
  }

  AniListSearchResult _parseSearchResult(Map raw, String normalizedQuery) {
    final titleMap = raw['title'] is Map ? raw['title'] as Map : const {};
    final coverMap = raw['coverImage'] is Map
        ? raw['coverImage'] as Map
        : const {};
    final startDate = raw['startDate'] is Map
        ? raw['startDate'] as Map
        : const {};
    final romaji = titleMap['romaji'] as String?;
    final english = titleMap['english'] as String?;
    final native = titleMap['native'] as String?;
    final preferred = titleMap['userPreferred'] as String?;
    final titles = [
      preferred,
      romaji,
      english,
      native,
    ].whereType<String>().where((value) => value.trim().isNotEmpty).toList();
    final score = normalizedQuery.isEmpty
        ? 1.0
        : titles
              .map(
                (value) => _titleScore(normalizedQuery, _normalizeTitle(value)),
              )
              .fold<double>(0, (best, score) => score > best ? score : best);

    return AniListSearchResult(
      id: (raw['id'] as num?)?.toInt() ?? 0,
      title: preferred ?? romaji ?? english ?? native ?? '',
      englishTitle: english,
      nativeTitle: native,
      coverUrl:
          coverMap['extraLarge'] as String? ?? coverMap['large'] as String?,
      description: _cleanDescription(raw['description'] as String?),
      averageScore: (raw['averageScore'] as num?)?.toInt(),
      meanScore: (raw['meanScore'] as num?)?.toInt(),
      format: raw['format'] as String?,
      status: raw['status'] as String?,
      season: raw['season'] as String?,
      duration: (raw['duration'] as num?)?.toInt(),
      genres:
          (raw['genres'] as List?)?.whereType<String>().toList() ?? const [],
      startYear: (startDate['year'] as num?)?.toInt(),
      episodes: (raw['episodes'] as num?)?.toInt(),
      score: score,
    );
  }

  String? _cleanDescription(String? value) {
    if (value == null) return null;
    final cleaned = value
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&')
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
    return cleaned.isEmpty ? null : cleaned;
  }

  Future<Map<String, dynamic>> _postGraphQl(
    String query,
    Map<String, Object?> variables,
  ) async {
    final now = DateTime.now();
    final lastRequest = _lastGraphQlRequest;
    if (lastRequest != null) {
      final wait =
          const Duration(milliseconds: 650) - now.difference(lastRequest);
      if (!wait.isNegative) await Future.delayed(wait);
    }
    _lastGraphQlRequest = DateTime.now();

    final client = HttpClient();
    try {
      final request = await client.postUrl(Uri.parse(_graphqlUrl));
      request.headers.set(HttpHeaders.userAgentHeader, _userAgent);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({'query': query, 'variables': variables}));
      final response = await request.close();
      final body = utf8.decode(
        await consolidateHttpClientResponseBytes(response),
      );
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('AniList HTTP ${response.statusCode}: $body');
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map) {
        throw const FormatException('Invalid AniList response');
      }
      if (decoded['errors'] != null) {
        throw FormatException('AniList GraphQL errors: ${decoded['errors']}');
      }
      final data = decoded['data'];
      if (data is! Map) {
        throw const FormatException('AniList response has no data');
      }
      return Map<String, dynamic>.from(data);
    } finally {
      client.close(force: true);
    }
  }

  String? _titleFor(AniListSearchResult? details, String languageCode) {
    if (details == null) return null;
    final wantsNative = const {'zh', 'ja', 'ko'}.contains(languageCode);
    if (wantsNative && details.nativeTitle?.isNotEmpty == true) {
      return details.nativeTitle;
    }
    return details.englishTitle?.isNotEmpty == true
        ? details.englishTitle
        : details.title;
  }

  double _titleScore(String left, String right) {
    if (left == right) return 1;
    if (left.isEmpty || right.isEmpty) return 0;
    if (left.contains(right) || right.contains(left)) {
      final shorter = left.length < right.length ? left.length : right.length;
      final longer = left.length > right.length ? left.length : right.length;
      return shorter / longer;
    }

    final leftTokens = left
        .split(' ')
        .where((token) => token.length > 1)
        .toSet();
    final rightTokens = right
        .split(' ')
        .where((token) => token.length > 1)
        .toSet();
    if (leftTokens.isEmpty || rightTokens.isEmpty) return 0;
    final overlap = leftTokens.intersection(rightTokens).length;
    final union = leftTokens.union(rightTokens).length;
    return overlap / union;
  }

  List<AnimeEpisodeGroup> _groupEpisodes(
    List<ParsedAnimeFile> files, {
    bool keepParsedTitles = false,
  }) {
    final buckets = <String, List<ParsedAnimeFile>>{};
    for (final file in files) {
      final key = keepParsedTitles
          ? '${file.normalizedTitle}:${file.episodeKey}'
          : file.episodeKey;
      buckets.putIfAbsent(key, () => []).add(file);
    }

    final groups = buckets.entries.map((entry) {
      final files = entry.value;
      files.sort((a, b) => a.fileName.compareTo(b.fileName));
      final first = files.first;
      final title = keepParsedTitles
          ? '${first.title} - ${_episodeLabel(first)}'
          : _episodeLabel(first);

      return AnimeEpisodeGroup(
        key: entry.key,
        number: first.episodeNumber,
        title: title,
        files: files
            .map(
              (file) => AnimeMediaFile(
                path: file.path,
                fileName: file.fileName,
                parsedTitle: file.title,
                releaseGroup: file.releaseGroup,
                resolution: file.resolution,
              ),
            )
            .toList(),
      );
    }).toList();

    groups.sort((a, b) {
      final aNum = a.number;
      final bNum = b.number;
      if (aNum != null && bNum != null) {
        return aNum.compareTo(bNum);
      }
      if (aNum != null) {
        return -1;
      }
      if (bNum != null) {
        return 1;
      }
      return a.title.compareTo(b.title);
    });

    return groups;
  }

  String _episodeLabel(ParsedAnimeFile file) {
    if (file.episodeNumber == null) return 'Unknown episode';
    return 'Episode ${file.episodeNumber!.toString().padLeft(2, '0')}';
  }

  Future<Directory> _metadataDirectory() async {
    final supportDir = await getApplicationSupportDirectory();
    final dir = Directory(p.join(supportDir.path, 'anilist'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<void> _loadDetailsCache() async {
    try {
      final dir = await _metadataDirectory();
      final file = File(p.join(dir.path, _detailsCacheFile));
      if (!await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return;
      _detailsCache
        ..clear()
        ..addEntries(
          decoded.entries.map((entry) {
            final id = int.tryParse('${entry.key}') ?? 0;
            return MapEntry(
              id,
              AniListSearchResult.fromJson(
                Map<String, dynamic>.from(entry.value as Map),
              ),
            );
          }),
        );
    } catch (e) {
      LoggerService().log('[AniList] Failed to load details cache: $e');
    }
  }

  Future<void> _saveDetailsCache() async {
    final dir = await _metadataDirectory();
    final file = File(p.join(dir.path, _detailsCacheFile));
    final data = _detailsCache.map(
      (id, details) => MapEntry('$id', details.toJson()),
    );
    await file.writeAsString(jsonEncode(data), flush: true);
  }

  Future<void> _loadSelectionCache() async {
    try {
      final dir = await _metadataDirectory();
      final file = File(p.join(dir.path, _selectionCacheFile));
      if (!await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return;
      _selectionCache
        ..clear()
        ..addEntries(
          decoded.entries.map(
            (entry) => MapEntry('${entry.key}', (entry.value as num).toInt()),
          ),
        );
    } catch (e) {
      LoggerService().log('[AniList] Failed to load selection cache: $e');
    }
  }

  Future<void> _saveSelectionCache() async {
    final dir = await _metadataDirectory();
    final file = File(p.join(dir.path, _selectionCacheFile));
    await file.writeAsString(jsonEncode(_selectionCache), flush: true);
  }

  Future<void> _loadUnresolvedCache() async {
    try {
      final dir = await _metadataDirectory();
      final file = File(p.join(dir.path, _unresolvedCacheFile));
      if (!await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return;
      _unresolvedCache
        ..clear()
        ..addEntries(
          decoded.entries.map(
            (entry) => MapEntry('${entry.key}', '${entry.value}'),
          ),
        );
    } catch (e) {
      LoggerService().log('[AniList] Failed to load unresolved cache: $e');
    }
  }

  Future<void> _saveUnresolvedCache() async {
    final dir = await _metadataDirectory();
    final file = File(p.join(dir.path, _unresolvedCacheFile));
    await file.writeAsString(jsonEncode(_unresolvedCache), flush: true);
  }
}

class AnitomyFilenameParser {
  ParsedAnimeFile parse(String path) {
    final fileName = p.basename(path);
    Map<String, dynamic> decoded;
    try {
      decoded = AnitomyNative().parse(fileName);
    } catch (e) {
      LoggerService().log('[Anitomy] Native parser unavailable: $e');
      decoded = const {};
    }
    final title = _stringValue(decoded['title']);
    final episode = _episodeNumber(_stringValue(decoded['episode']));
    final parsedTitle = title ?? fileName;
    return ParsedAnimeFile(
      path: path,
      fileName: fileName,
      title: parsedTitle,
      normalizedTitle: _normalizeTitle(parsedTitle),
      episodeNumber: episode,
      episodeKey: episode == null ? 'unknown:$fileName' : 'ep:$episode',
      releaseGroup: _stringValue(decoded['release_group']),
      resolution: _stringValue(decoded['video_resolution']),
    );
  }

  String? _stringValue(Object? value) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return null;
  }

  int? _episodeNumber(String? value) {
    if (value == null) return null;
    return int.tryParse(value.replaceFirst(RegExp(r'^0+'), ''));
  }
}

String _normalizeTitle(String value) {
  return value
      .toLowerCase()
      .replaceAll(
        RegExp(r'[\[\]\(\)\u3010\u3011\u300c\u300d\u300e\u300f\u300a\u300b]'),
        ' ',
      )
      .replaceAll(RegExp(r'[^a-z0-9\u3040-\u30ff\u3400-\u9fff]+'), ' ')
      .replaceAll(RegExp(r'\b(the|a|an|season|part)\b'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
