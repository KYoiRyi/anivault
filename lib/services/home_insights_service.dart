import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anivault/services/ai_agent_service.dart';
import 'package:anivault/services/anime_library_service.dart';
import 'package:anivault/services/logger_service.dart';
import 'package:anivault/services/watch_history_service.dart';

class SeasonalAnimeItem {
  final int id;
  final String title;
  final String? coverUrl;
  final String? description;
  final int? averageScore;
  final int? meanScore;
  final int? episodes;
  final int? nextEpisode;
  final DateTime? airingAt;
  final List<String> genres;
  final List<String> tags;
  final String reason;

  const SeasonalAnimeItem({
    required this.id,
    required this.title,
    this.coverUrl,
    this.description,
    this.averageScore,
    this.meanScore,
    this.episodes,
    this.nextEpisode,
    this.airingAt,
    this.genres = const [],
    this.tags = const [],
    this.reason = '',
  });

  SeasonalAnimeItem copyWith({String? reason}) {
    return SeasonalAnimeItem(
      id: id,
      title: title,
      coverUrl: coverUrl,
      description: description,
      averageScore: averageScore,
      meanScore: meanScore,
      episodes: episodes,
      nextEpisode: nextEpisode,
      airingAt: airingAt,
      genres: genres,
      tags: tags,
      reason: reason ?? this.reason,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'coverUrl': coverUrl,
    'description': description,
    'averageScore': averageScore,
    'meanScore': meanScore,
    'episodes': episodes,
    'nextEpisode': nextEpisode,
    'airingAt': airingAt?.millisecondsSinceEpoch,
    'genres': genres,
    'tags': tags,
    'reason': reason,
  };

  factory SeasonalAnimeItem.fromJson(Map<String, dynamic> json) {
    return SeasonalAnimeItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: json['title'] as String? ?? '',
      coverUrl: json['coverUrl'] as String?,
      description: json['description'] as String?,
      averageScore: (json['averageScore'] as num?)?.toInt(),
      meanScore: (json['meanScore'] as num?)?.toInt(),
      episodes: (json['episodes'] as num?)?.toInt(),
      nextEpisode: (json['nextEpisode'] as num?)?.toInt(),
      airingAt: json['airingAt'] is num
          ? DateTime.fromMillisecondsSinceEpoch(
              (json['airingAt'] as num).toInt(),
            )
          : null,
      genres:
          (json['genres'] as List?)?.whereType<String>().toList() ?? const [],
      tags: (json['tags'] as List?)?.whereType<String>().toList() ?? const [],
      reason: json['reason'] as String? ?? '',
    );
  }
}

class SeasonalProgressItem {
  final AnimeSeries series;
  final int watchedEpisodes;
  final int totalEpisodes;

  const SeasonalProgressItem({
    required this.series,
    required this.watchedEpisodes,
    required this.totalEpisodes,
  });

  double get progress => totalEpisodes == 0
      ? 0
      : (watchedEpisodes / totalEpisodes).clamp(0.0, 1.0);
}

class HomeInsightsService extends ChangeNotifier {
  static final HomeInsightsService _instance = HomeInsightsService._internal();
  factory HomeInsightsService() => _instance;
  HomeInsightsService._internal();

  static const _graphqlUrl = 'https://graphql.anilist.co';
  static const _userAgent = 'AniVault/1.0';
  static const _cacheKey = 'home_insights_cache_v1';

  bool _initialized = false;
  bool _refreshing = false;
  DateTime? _lastRefresh;
  List<SeasonalAnimeItem> _todayUpdates = const [];
  List<SeasonalAnimeItem> _recommendations = const [];
  List<SeasonalProgressItem> _seasonProgress = const [];
  String? _lastError;

  bool get refreshing => _refreshing;
  DateTime? get lastRefresh => _lastRefresh;
  List<SeasonalAnimeItem> get todayUpdates => List.unmodifiable(_todayUpdates);
  List<SeasonalAnimeItem> get recommendations =>
      List.unmodifiable(_recommendations);
  List<SeasonalProgressItem> get seasonProgress =>
      List.unmodifiable(_seasonProgress);
  String? get lastError => _lastError;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    await _loadCache();
    _rebuildSeasonProgress();
    AnimeLibraryService().addListener(_rebuildSeasonProgress);
    WatchHistoryService().addListener(_rebuildSeasonProgress);
    notifyListeners();
    unawaited(refresh(silent: true));
  }

  Future<void> refresh({bool silent = false}) async {
    if (_refreshing) return;
    _refreshing = true;
    _lastError = null;
    if (!silent) notifyListeners();

    try {
      final season = _currentSeason();
      final year = DateTime.now().year;
      final fetched = await Future.wait([
        _fetchTodayUpdates(),
        _fetchSeasonRecommendations(season, year),
      ]);
      _todayUpdates = fetched[0].take(10).toList();
      var recommendations = fetched[1].take(8).toList();
      recommendations = await _enrichRecommendationReasons(recommendations);
      _recommendations = recommendations;
      _lastRefresh = DateTime.now();
      _rebuildSeasonProgress(notify: false);
      await _saveCache();
      LoggerService().log('[Home] AniList home insights refreshed');
    } catch (e) {
      _lastError = e.toString();
      LoggerService().log('[Home] AniList home insights failed: $e');
    } finally {
      _refreshing = false;
      notifyListeners();
    }
  }

  void _rebuildSeasonProgress({bool notify = true}) {
    final season = _currentSeason();
    final year = DateTime.now().year;
    final records = WatchHistoryService().records;
    _seasonProgress =
        AnimeLibraryService().series
            .where(
              (series) =>
                  !series.isUnknown &&
                  series.season == season &&
                  series.startYear == year,
            )
            .map((series) {
              final watched = <String>{};
              for (final record in records) {
                if (record.seriesId != series.id ||
                    record.progressRatio < 0.9) {
                  continue;
                }
                watched.add(
                  record.episodeNumber?.toString() ?? record.videoPath,
                );
              }
              final total = series.episodes.isNotEmpty
                  ? series.episodes.length
                  : (series.anilistId == null ? 0 : series.episodes.length);
              return SeasonalProgressItem(
                series: series,
                watchedEpisodes: watched.length,
                totalEpisodes: total == 0 ? series.episodes.length : total,
              );
            })
            .toList()
          ..sort((a, b) => b.progress.compareTo(a.progress));
    if (notify) notifyListeners();
  }

  Future<List<SeasonalAnimeItem>> _fetchTodayUpdates() async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 1));
    final data = await _postGraphQl(
      r'''
query ($start: Int!, $end: Int!) {
  Page(page: 1, perPage: 20) {
    airingSchedules(
      airingAt_greater: $start,
      airingAt_lesser: $end,
      sort: TIME
    ) {
      airingAt
      episode
      media {
        id
        title { romaji english native userPreferred }
        description(asHtml: false)
        coverImage { large extraLarge }
        episodes
        averageScore
        meanScore
        genres
        tags { name rank isMediaSpoiler isGeneralSpoiler }
      }
    }
  }
}
''',
      {
        'start': start.millisecondsSinceEpoch ~/ 1000,
        'end': end.millisecondsSinceEpoch ~/ 1000,
      },
    ).timeout(const Duration(seconds: 12));

    final schedules = (data['Page'] as Map?)?['airingSchedules'];
    if (schedules is! List) return const [];
    return schedules
        .whereType<Map>()
        .map((raw) {
          final media = raw['media'] is Map ? raw['media'] as Map : const {};
          return _parseMedia(
            media,
            nextEpisode: (raw['episode'] as num?)?.toInt(),
            airingAt: raw['airingAt'] is num
                ? DateTime.fromMillisecondsSinceEpoch(
                    (raw['airingAt'] as num).toInt() * 1000,
                  )
                : null,
          );
        })
        .where((item) => item.title.isNotEmpty)
        .toList();
  }

  Future<List<SeasonalAnimeItem>> _fetchSeasonRecommendations(
    String season,
    int year,
  ) async {
    final data = await _postGraphQl(
      r'''
query ($season: MediaSeason!, $year: Int!) {
  Page(page: 1, perPage: 16) {
    media(
      type: ANIME,
      season: $season,
      seasonYear: $year,
      isAdult: false,
      sort: [TRENDING_DESC, POPULARITY_DESC]
    ) {
      id
      title { romaji english native userPreferred }
      description(asHtml: false)
      coverImage { large extraLarge }
      episodes
      averageScore
      meanScore
      genres
      tags { name rank isMediaSpoiler isGeneralSpoiler }
    }
  }
}
''',
      {'season': season, 'year': year},
    ).timeout(const Duration(seconds: 12));

    final media = (data['Page'] as Map?)?['media'];
    if (media is! List) return const [];
    return media.whereType<Map>().map(_parseMedia).toList();
  }

  Future<List<SeasonalAnimeItem>> _enrichRecommendationReasons(
    List<SeasonalAnimeItem> items,
  ) async {
    await AiAgentService().initialize();
    final result = <SeasonalAnimeItem>[];
    for (final item in items) {
      var reason = item.reason;
      if (AiAgentService().config.isReady) {
        reason =
            await AiAgentService().recommendAnimeReason(
              title: item.title,
              genres: item.genres,
              tags: item.tags,
              description: item.description,
              averageScore: item.averageScore,
            ) ??
            reason;
      }
      if (reason.trim().isEmpty) {
        reason = _fallbackReason(item);
      }
      result.add(item.copyWith(reason: reason));
    }
    return result;
  }

  SeasonalAnimeItem _parseMedia(
    Map raw, {
    int? nextEpisode,
    DateTime? airingAt,
  }) {
    final titleMap = raw['title'] is Map ? raw['title'] as Map : const {};
    final coverMap = raw['coverImage'] is Map
        ? raw['coverImage'] as Map
        : const {};
    final tags =
        (raw['tags'] as List?)
            ?.whereType<Map>()
            .where((tag) {
              final rank = (tag['rank'] as num?)?.toInt() ?? 0;
              return rank >= 55 &&
                  tag['isMediaSpoiler'] != true &&
                  tag['isGeneralSpoiler'] != true;
            })
            .map((tag) => tag['name'])
            .whereType<String>()
            .take(6)
            .toList() ??
        const [];
    final item = SeasonalAnimeItem(
      id: (raw['id'] as num?)?.toInt() ?? 0,
      title:
          titleMap['userPreferred'] as String? ??
          titleMap['english'] as String? ??
          titleMap['romaji'] as String? ??
          titleMap['native'] as String? ??
          '',
      coverUrl:
          coverMap['extraLarge'] as String? ?? coverMap['large'] as String?,
      description: _cleanDescription(raw['description'] as String?),
      averageScore: (raw['averageScore'] as num?)?.toInt(),
      meanScore: (raw['meanScore'] as num?)?.toInt(),
      episodes: (raw['episodes'] as num?)?.toInt(),
      nextEpisode: nextEpisode,
      airingAt: airingAt,
      genres:
          (raw['genres'] as List?)?.whereType<String>().toList() ?? const [],
      tags: tags,
    );
    return item.copyWith(reason: _fallbackReason(item));
  }

  String _fallbackReason(SeasonalAnimeItem item) {
    final labels = _displayTags(item);
    final score = item.averageScore ?? item.meanScore;
    if (labels.isNotEmpty && score != null) {
      return '${labels.take(2).join('、')}气质鲜明，AniList 均分 $score，适合放进本季片单。';
    }
    if (labels.isNotEmpty) {
      return '${labels.take(2).join('、')}元素突出，适合想补一部本季新番时尝试。';
    }
    if (score != null) {
      return '本季热度靠前，AniList 均分 $score，适合先看一集判断电波。';
    }
    return '本季讨论度较高，适合加入候选片单慢慢试。';
  }

  List<String> _displayTags(SeasonalAnimeItem item) {
    return [...item.genres, ...item.tags]
        .where((value) {
          final lower = value.toLowerCase();
          return !lower.contains('female') &&
              !lower.contains('male') &&
              !lower.contains('cast');
        })
        .take(4)
        .toList();
  }

  Future<Map<String, dynamic>> _postGraphQl(
    String query,
    Map<String, Object?> variables,
  ) async {
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
      if (decoded is! Map || decoded['data'] is! Map) {
        throw const FormatException('Invalid AniList response');
      }
      if (decoded['errors'] != null) {
        throw FormatException('AniList GraphQL errors: ${decoded['errors']}');
      }
      return Map<String, dynamic>.from(decoded['data'] as Map);
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _loadCache() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      _todayUpdates =
          (decoded['todayUpdates'] as List?)
              ?.whereType<Map>()
              .map(
                (item) =>
                    SeasonalAnimeItem.fromJson(Map<String, dynamic>.from(item)),
              )
              .toList() ??
          const [];
      _recommendations =
          (decoded['recommendations'] as List?)
              ?.whereType<Map>()
              .map(
                (item) =>
                    SeasonalAnimeItem.fromJson(Map<String, dynamic>.from(item)),
              )
              .toList() ??
          const [];
      _lastRefresh = decoded['lastRefresh'] is num
          ? DateTime.fromMillisecondsSinceEpoch(
              (decoded['lastRefresh'] as num).toInt(),
            )
          : null;
    } catch (e) {
      LoggerService().log('[Home] Failed to load insights cache: $e');
    }
  }

  Future<void> _saveCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _cacheKey,
      jsonEncode({
        'lastRefresh': _lastRefresh?.millisecondsSinceEpoch,
        'todayUpdates': _todayUpdates.map((item) => item.toJson()).toList(),
        'recommendations': _recommendations
            .map((item) => item.toJson())
            .toList(),
      }),
    );
  }

  String _currentSeason() {
    final month = DateTime.now().month;
    if (month <= 3) return 'WINTER';
    if (month <= 6) return 'SPRING';
    if (month <= 9) return 'SUMMER';
    return 'FALL';
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
}
