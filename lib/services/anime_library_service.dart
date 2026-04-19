import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';

import 'package:anivault/services/logger_service.dart';

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
  final String title;
  final String sortTitle;
  final String? coverUrl;
  final bool isUnknown;
  final List<AnimeEpisodeGroup> episodes;

  const AnimeSeries({
    required this.id,
    required this.anidbId,
    required this.title,
    required this.sortTitle,
    required this.coverUrl,
    required this.isUnknown,
    required this.episodes,
  });

  int get fileCount =>
      episodes.fold(0, (sum, episode) => sum + episode.files.length);
}

class AniDbTitleEntry {
  final int aid;
  final String type;
  final String language;
  final String title;
  final String normalizedTitle;

  const AniDbTitleEntry({
    required this.aid,
    required this.type,
    required this.language,
    required this.title,
    required this.normalizedTitle,
  });
}

class AniDbAnimeDetails {
  final int aid;
  final Map<String, String> titlesByLanguage;
  final String? mainTitle;
  final String? picture;

  const AniDbAnimeDetails({
    required this.aid,
    required this.titlesByLanguage,
    required this.mainTitle,
    required this.picture,
  });

  String? titleFor(String languageCode) {
    return titlesByLanguage[languageCode] ??
        titlesByLanguage[_languageAlias(languageCode)] ??
        titlesByLanguage['en'] ??
        titlesByLanguage['zh-Hans'] ??
        mainTitle;
  }

  String? get coverUrl {
    if (picture == null || picture!.isEmpty) return null;
    return 'https://cdn-eu.anidb.net/images/main/$picture';
  }

  Map<String, dynamic> toJson() {
    return {
      'aid': aid,
      'titlesByLanguage': titlesByLanguage,
      'mainTitle': mainTitle,
      'picture': picture,
    };
  }

  factory AniDbAnimeDetails.fromJson(Map<String, dynamic> json) {
    final rawTitles = json['titlesByLanguage'];
    return AniDbAnimeDetails(
      aid: (json['aid'] as num?)?.toInt() ?? 0,
      titlesByLanguage: rawTitles is Map
          ? rawTitles.map((key, value) => MapEntry('$key', '$value'))
          : const {},
      mainTitle: json['mainTitle'] as String?,
      picture: json['picture'] as String?,
    );
  }
}

class AnimeLibraryService extends ChangeNotifier {
  static final AnimeLibraryService _instance = AnimeLibraryService._internal();
  factory AnimeLibraryService() => _instance;
  AnimeLibraryService._internal();

  static const _titleDumpUrl = 'https://anidb.net/api/anime-titles.xml.gz';
  static const _titleDumpFile = 'anime-titles.xml';
  static const _detailsCacheFile = 'anime-details-cache.json';
  static const _userAgent = 'AniVault/1.0';

  final _filenameParser = AnimeFilenameParser();
  final List<AniDbTitleEntry> _titles = [];
  final Map<int, AniDbAnimeDetails> _detailsCache = {};
  DateTime? _lastHttpApiRequest;

  bool _isReady = false;
  bool _isScanning = false;
  String? _lastError;
  List<AnimeSeries> _series = [];

  bool get isReady => _isReady;
  bool get isScanning => _isScanning;
  String? get lastError => _lastError;
  List<AnimeSeries> get series => List.unmodifiable(_series);

  Future<void> initialize() async {
    if (_isReady) return;
    await _loadDetailsCache();
    await _loadOrRefreshTitleDump();
    _isReady = true;
    notifyListeners();
  }

  Future<void> refreshLibrary(
    List<String> paths, {
    required String languageCode,
  }) async {
    _isScanning = true;
    _lastError = null;
    notifyListeners();

    try {
      await initialize();
      final parsedFiles = paths.map(_filenameParser.parse).toList();
      final knownBuckets = <int, List<ParsedAnimeFile>>{};
      final unknownFiles = <ParsedAnimeFile>[];

      for (final parsed in parsedFiles) {
        final match = _matchTitle(parsed.normalizedTitle);
        if (match == null) {
          unknownFiles.add(parsed);
          continue;
        }
        knownBuckets.putIfAbsent(match.aid, () => []).add(parsed);
      }

      final nextSeries = <AnimeSeries>[];

      for (final entry in knownBuckets.entries) {
        final aid = entry.key;
        final files = entry.value;
        final details = await _fetchAnimeDetails(aid);
        final fallbackTitle = _bestTitleFromDump(aid, languageCode);
        final title =
            details?.titleFor(languageCode) ??
            fallbackTitle ??
            files.first.title;

        nextSeries.add(
          AnimeSeries(
            id: 'anidb:$aid',
            anidbId: aid,
            title: title,
            sortTitle: _normalizeTitle(title),
            coverUrl: details?.coverUrl,
            isUnknown: false,
            episodes: _groupEpisodes(files),
          ),
        );
      }

      if (unknownFiles.isNotEmpty) {
        nextSeries.add(
          AnimeSeries(
            id: 'unknown',
            anidbId: null,
            title: 'Unknown',
            sortTitle: 'zzzz_unknown',
            coverUrl: null,
            isUnknown: true,
            episodes: _groupEpisodes(unknownFiles, keepParsedTitles: true),
          ),
        );
      }

      nextSeries.sort((a, b) => a.sortTitle.compareTo(b.sortTitle));
      _series = nextSeries;
    } catch (e) {
      _lastError = e.toString();
      LoggerService().log('[Library] Scrape failed: $e');
    } finally {
      _isScanning = false;
      notifyListeners();
    }
  }

  Future<void> _loadOrRefreshTitleDump() async {
    final cacheDir = await _metadataDirectory();
    final titleFile = File(p.join(cacheDir.path, _titleDumpFile));

    if (await titleFile.exists()) {
      final age = DateTime.now().difference(await titleFile.lastModified());
      if (age < const Duration(days: 1)) {
        await _loadTitleDump(titleFile);
        return;
      }
    }

    try {
      LoggerService().log('[AniDB] Updating title dump...');
      final request = await HttpClient().getUrl(Uri.parse(_titleDumpUrl));
      request.headers.set(HttpHeaders.userAgentHeader, _userAgent);
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('AniDB title dump HTTP ${response.statusCode}');
      }

      final compressed = await consolidateHttpClientResponseBytes(response);
      final xmlBytes = gzip.decode(compressed);
      await titleFile.writeAsBytes(xmlBytes, flush: true);
      await _loadTitleDump(titleFile);
    } catch (e) {
      if (await titleFile.exists()) {
        LoggerService().log('[AniDB] Using cached title dump after error: $e');
        await _loadTitleDump(titleFile);
      } else {
        _lastError = 'AniDB title dump unavailable: $e';
        LoggerService().log('[AniDB] Title dump unavailable: $e');
      }
    }
  }

  Future<void> _loadTitleDump(File titleFile) async {
    _titles.clear();
    final document = XmlDocument.parse(await titleFile.readAsString());
    for (final anime in document.findAllElements('anime')) {
      final aid = int.tryParse(anime.getAttribute('aid') ?? '');
      if (aid == null) continue;

      for (final titleNode in anime.findElements('title')) {
        final title = titleNode.innerText.trim();
        if (title.isEmpty) continue;
        final language =
            titleNode.getAttribute('xml:lang') ??
            titleNode.getAttribute('lang') ??
            '';
        _titles.add(
          AniDbTitleEntry(
            aid: aid,
            type: titleNode.getAttribute('type') ?? '',
            language: language,
            title: title,
            normalizedTitle: _normalizeTitle(title),
          ),
        );
      }
    }
    LoggerService().log('[AniDB] Loaded ${_titles.length} title aliases.');
  }

  AniDbTitleEntry? _matchTitle(String normalizedTitle) {
    if (normalizedTitle.isEmpty || _titles.isEmpty) return null;

    AniDbTitleEntry? best;
    var bestScore = 0.0;

    for (final title in _titles) {
      final score = _titleScore(normalizedTitle, title.normalizedTitle);
      if (score > bestScore) {
        bestScore = score;
        best = title;
      }
      if (score >= 1.0 && (title.type == 'main' || title.type == 'official')) {
        return title;
      }
    }

    return bestScore >= 0.86 ? best : null;
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

  String? _bestTitleFromDump(int aid, String languageCode) {
    final candidates = _titles.where((title) => title.aid == aid).toList();
    if (candidates.isEmpty) return null;

    String? pick(String language, String type) {
      for (final title in candidates) {
        if (title.language == language && title.type == type) {
          return title.title;
        }
      }
      return null;
    }

    final alias = _languageAlias(languageCode);
    return pick(languageCode, 'official') ??
        pick(alias, 'official') ??
        pick('en', 'official') ??
        pick(languageCode, 'main') ??
        pick(alias, 'main') ??
        pick('x-jat', 'main') ??
        candidates.first.title;
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
      if (aNum != null && bNum != null) return aNum.compareTo(bNum);
      if (aNum != null) return -1;
      if (bNum != null) return 1;
      return a.title.compareTo(b.title);
    });

    return groups;
  }

  String _episodeLabel(ParsedAnimeFile file) {
    if (file.episodeNumber == null) return 'Unknown episode';
    return 'Episode ${file.episodeNumber!.toString().padLeft(2, '0')}';
  }

  Future<AniDbAnimeDetails?> _fetchAnimeDetails(int aid) async {
    final cached = _detailsCache[aid];
    if (cached != null) return cached;

    final prefs = await SharedPreferences.getInstance();
    final client = prefs.getString('anidb_client') ?? '';
    final clientVer = prefs.getInt('anidb_clientver') ?? 1;
    if (client.trim().isEmpty) {
      return null;
    }

    try {
      final now = DateTime.now();
      final lastRequest = _lastHttpApiRequest;
      if (lastRequest != null) {
        final wait =
            const Duration(milliseconds: 2200) - now.difference(lastRequest);
        if (!wait.isNegative) await Future.delayed(wait);
      }
      _lastHttpApiRequest = DateTime.now();

      final uri = Uri.parse('http://api.anidb.net:9001/httpapi').replace(
        queryParameters: {
          'request': 'anime',
          'client': client,
          'clientver': '$clientVer',
          'protover': '1',
          'aid': '$aid',
        },
      );

      final request = await HttpClient().getUrl(uri);
      request.headers.set(HttpHeaders.userAgentHeader, _userAgent);
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('AniDB details HTTP ${response.statusCode}');
      }

      final body = utf8.decode(
        await consolidateHttpClientResponseBytes(response),
      );
      if (body.contains('<error>')) {
        throw FormatException(body.replaceAll(RegExp(r'\s+'), ' ').trim());
      }

      final details = _parseAnimeDetails(aid, body);
      _detailsCache[aid] = details;
      await _saveDetailsCache();
      return details;
    } catch (e) {
      LoggerService().log('[AniDB] Details unavailable for aid=$aid: $e');
      return null;
    }
  }

  AniDbAnimeDetails _parseAnimeDetails(int aid, String body) {
    final document = XmlDocument.parse(body);
    final anime = document.findAllElements('anime').first;
    final titlesByLanguage = <String, String>{};
    String? mainTitle;

    for (final titleNode in anime.findAllElements('title')) {
      final title = titleNode.innerText.trim();
      if (title.isEmpty) continue;
      final language =
          titleNode.getAttribute('xml:lang') ??
          titleNode.getAttribute('lang') ??
          '';
      final type = titleNode.getAttribute('type') ?? '';
      if (type == 'official') {
        titlesByLanguage.putIfAbsent(language, () => title);
      }
      if (type == 'main') {
        mainTitle ??= title;
      }
    }

    final picture = anime.findElements('picture').firstOrNull?.innerText.trim();
    return AniDbAnimeDetails(
      aid: aid,
      titlesByLanguage: titlesByLanguage,
      mainTitle: mainTitle,
      picture: picture == null || picture.isEmpty ? null : picture,
    );
  }

  Future<Directory> _metadataDirectory() async {
    final supportDir = await getApplicationSupportDirectory();
    final dir = Directory(p.join(supportDir.path, 'anidb'));
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
            final aid = int.tryParse('${entry.key}') ?? 0;
            return MapEntry(
              aid,
              AniDbAnimeDetails.fromJson(
                Map<String, dynamic>.from(entry.value as Map),
              ),
            );
          }),
        );
    } catch (e) {
      LoggerService().log('[AniDB] Failed to load details cache: $e');
    }
  }

  Future<void> _saveDetailsCache() async {
    final dir = await _metadataDirectory();
    final file = File(p.join(dir.path, _detailsCacheFile));
    final data = _detailsCache.map(
      (aid, details) => MapEntry('$aid', details.toJson()),
    );
    await file.writeAsString(jsonEncode(data), flush: true);
  }
}

class AnimeFilenameParser {
  static final _videoExtPattern = RegExp(
    r'\.(mkv|mp4|avi|mov|webm|m4v)$',
    caseSensitive: false,
  );
  static final _resolutionPattern = RegExp(
    r'(480p|576p|720p|1080p|1440p|2160p|4k|8k)',
    caseSensitive: false,
  );
  static final _episodePatterns = [
    RegExp(
      r'(?:^|[\s._-])(?:s\d{1,2}e)(\d{1,4})(?:v\d+)?\b',
      caseSensitive: false,
    ),
    RegExp(
      r'(?:^|[\s._-])(?:ep|episode)[\s._-]*(\d{1,4})(?:v\d+)?\b',
      caseSensitive: false,
    ),
    RegExp(r'(?:^|[\s._-])(\d{1,4})(?:v\d+)?(?:[\s._-]|$)'),
  ];

  ParsedAnimeFile parse(String path) {
    final fileName = p.basename(path);
    final nameWithoutExtension = fileName.replaceFirst(_videoExtPattern, '');
    final bracketTokens = RegExp(r'[\[【(]([^\]】)]+)[\]】)]')
        .allMatches(nameWithoutExtension)
        .map((match) => match.group(1)!.trim())
        .where((token) => token.isNotEmpty)
        .toList();

    final releaseGroup = _releaseGroup(nameWithoutExtension, bracketTokens);
    final resolution = _findResolution(nameWithoutExtension, bracketTokens);
    final episode = _findEpisode(nameWithoutExtension, bracketTokens);
    final title = _findTitle(nameWithoutExtension, bracketTokens, episode);

    return ParsedAnimeFile(
      path: path,
      fileName: fileName,
      title: title.isEmpty ? fileName : title,
      normalizedTitle: _normalizeTitle(title.isEmpty ? fileName : title),
      episodeNumber: episode,
      episodeKey: episode == null ? 'unknown:$fileName' : 'ep:$episode',
      releaseGroup: releaseGroup,
      resolution: resolution,
    );
  }

  String? _releaseGroup(String name, List<String> bracketTokens) {
    final firstBracket = RegExp(r'^[\[【(]([^\]】)]+)[\]】)]').firstMatch(name);
    if (firstBracket != null) return firstBracket.group(1)?.trim();
    return bracketTokens.isNotEmpty ? bracketTokens.first : null;
  }

  String? _findResolution(String name, List<String> bracketTokens) {
    for (final token in [name, ...bracketTokens]) {
      final match = _resolutionPattern.firstMatch(token);
      if (match != null) return match.group(1);
    }
    return null;
  }

  int? _findEpisode(String name, List<String> bracketTokens) {
    for (final token in bracketTokens.reversed) {
      final cleaned = token.trim();
      final exact = RegExp(
        r'^(\d{1,4})(?:v\d+)?$',
        caseSensitive: false,
      ).firstMatch(cleaned);
      if (exact != null && !_looksLikeYearOrResolution(cleaned)) {
        return int.tryParse(exact.group(1)!);
      }
    }

    for (final pattern in _episodePatterns) {
      final matches = pattern.allMatches(name).toList().reversed;
      for (final match in matches) {
        final raw = match.group(1);
        if (raw == null || _looksLikeYearOrResolution(raw)) continue;
        return int.tryParse(raw);
      }
    }
    return null;
  }

  String _findTitle(String name, List<String> bracketTokens, int? episode) {
    final usefulBracketTokens = bracketTokens.where((token) {
      if (_resolutionPattern.hasMatch(token)) return false;
      if (_looksLikeTechToken(token)) return false;
      if (episode != null &&
          RegExp(
            '^0*$episode(?:v\\d+)?\$',
            caseSensitive: false,
          ).hasMatch(token)) {
        return false;
      }
      return true;
    }).toList();

    if (usefulBracketTokens.length >= 2) {
      return _cleanTitle(usefulBracketTokens[1]);
    }

    var title = name.replaceAll(RegExp(r'^[\[【(][^\]】)]+[\]】)]\s*'), '');
    title = title.replaceAll(RegExp(r'[\[【(][^\]】)]+[\]】)]'), ' ');
    if (episode != null) {
      title = title.replaceAll(
        RegExp(
          r'[-_\s]*(?:s\d{1,2}e|ep|episode)?\s*0*'
          '$episode'
          r'(?:v\d+)?\b.*$',
          caseSensitive: false,
        ),
        '',
      );
    }
    return _cleanTitle(title);
  }

  String _cleanTitle(String value) {
    return value
        .replaceAll(RegExp(r'[._]+'), ' ')
        .replaceAll(RegExp(r'\s+-\s+$'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  bool _looksLikeTechToken(String value) {
    final lower = value.toLowerCase();
    const techWords = [
      'x264',
      'x265',
      'h264',
      'h265',
      'hevc',
      'avc',
      'aac',
      'flac',
      'web-dl',
      'webrip',
      'bdrip',
      'bluray',
      'jpsc',
      'ma10p',
    ];
    return techWords.any(lower.contains) ||
        RegExp(r'^[a-f0-9]{8}$', caseSensitive: false).hasMatch(value);
  }

  bool _looksLikeYearOrResolution(String value) {
    final number = int.tryParse(value.replaceAll(RegExp(r'\D'), ''));
    if (number == null) return false;
    if (number >= 1900 && number <= 2100) return true;
    return number == 480 ||
        number == 576 ||
        number == 720 ||
        number == 1080 ||
        number == 2160;
  }
}

String _normalizeTitle(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[\[\]\(\)【】「」『』]'), ' ')
      .replaceAll(RegExp(r'[^a-z0-9\u3040-\u30ff\u3400-\u9fff]+'), ' ')
      .replaceAll(RegExp(r'\b(the|a|an|season|part)\b'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String _languageAlias(String languageCode) {
  return switch (languageCode) {
    'zh' => 'zh-Hans',
    'cn' => 'zh-Hans',
    'tw' => 'zh-Hant',
    _ => languageCode,
  };
}

extension _FirstOrNullExtension<E> on Iterable<E> {
  E? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
