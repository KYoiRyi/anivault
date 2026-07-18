import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:langchain_core/chat_models.dart';
import 'package:langchain_core/prompts.dart';
import 'package:langchain_core/tools.dart';
import 'package:langchain_openai/langchain_openai.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anivault/services/anime_library_service.dart';
import 'package:anivault/services/logger_service.dart';
import 'package:anivault/services/dmhy_result_grouper.dart';

class AiAgentConfig {
  final bool enabled;
  final String baseUrl;
  final String apiKey;
  final String model;
  final List<String> models;

  const AiAgentConfig({
    this.enabled = false,
    this.baseUrl = 'https://api.openai.com/v1',
    this.apiKey = '',
    this.model = '',
    this.models = const [],
  });

  bool get isReady =>
      enabled &&
      baseUrl.trim().isNotEmpty &&
      apiKey.trim().isNotEmpty &&
      model.trim().isNotEmpty;

  AiAgentConfig copyWith({
    bool? enabled,
    String? baseUrl,
    String? apiKey,
    String? model,
    List<String>? models,
  }) {
    return AiAgentConfig(
      enabled: enabled ?? this.enabled,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      model: model ?? this.model,
      models: models ?? this.models,
    );
  }
}

class AiAgentService extends ChangeNotifier {
  static final AiAgentService _instance = AiAgentService._internal();
  factory AiAgentService() => _instance;
  AiAgentService._internal();

  static const _enabledKey = 'ai_agent_enabled';
  static const _baseUrlKey = 'ai_agent_base_url';
  static const _apiKeyKey = 'ai_agent_api_key';
  static const _modelKey = 'ai_agent_model';
  static const _modelsKey = 'ai_agent_models';

  AiAgentConfig _config = const AiAgentConfig();
  bool _isReady = false;
  bool _isFetchingModels = false;
  String? _lastError;

  AiAgentConfig get config => _config;
  bool get isReady => _isReady;
  bool get isFetchingModels => _isFetchingModels;
  String? get lastError => _lastError;

  Future<void> initialize() async {
    if (_isReady) return;
    final prefs = await SharedPreferences.getInstance();
    final modelsJson = prefs.getString(_modelsKey);
    final models = _decodeModels(modelsJson);
    _config = AiAgentConfig(
      enabled: prefs.getBool(_enabledKey) ?? false,
      baseUrl: prefs.getString(_baseUrlKey) ?? const AiAgentConfig().baseUrl,
      apiKey: prefs.getString(_apiKeyKey) ?? '',
      model: prefs.getString(_modelKey) ?? '',
      models: models,
    );
    _isReady = true;
    notifyListeners();
  }

  Future<void> saveConfig({
    bool? enabled,
    String? baseUrl,
    String? apiKey,
    String? model,
    List<String>? models,
  }) async {
    await initialize();
    _config = _config.copyWith(
      enabled: enabled,
      baseUrl: baseUrl == null ? null : _normalizeBaseUrl(baseUrl),
      apiKey: apiKey,
      model: model,
      models: models,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, _config.enabled);
    await prefs.setString(_baseUrlKey, _config.baseUrl);
    await prefs.setString(_apiKeyKey, _config.apiKey);
    await prefs.setString(_modelKey, _config.model);
    await prefs.setString(_modelsKey, jsonEncode(_config.models));
    notifyListeners();
  }

  Future<List<String>> fetchModels({String? baseUrl, String? apiKey}) async {
    await initialize();
    _isFetchingModels = true;
    _lastError = null;
    notifyListeners();

    final effectiveBaseUrl = _normalizeBaseUrl(baseUrl ?? _config.baseUrl);
    final effectiveApiKey = (apiKey ?? _config.apiKey).trim();
    final client = HttpClient();

    try {
      final uri = Uri.parse('$effectiveBaseUrl/models');
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (effectiveApiKey.isNotEmpty) {
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer $effectiveApiKey',
        );
      }
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      final body = utf8.decode(
        await consolidateHttpClientResponseBytes(response),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('Models HTTP ${response.statusCode}: $body');
      }
      final decoded = jsonDecode(body);
      final rawModels = decoded is Map ? decoded['data'] : null;
      if (rawModels is! List) {
        throw const FormatException('Model list has no data array');
      }
      final models =
          rawModels
              .whereType<Map>()
              .map((item) => item['id'])
              .whereType<String>()
              .where((id) => id.trim().isNotEmpty)
              .toSet()
              .toList()
            ..sort();
      final selected = models.contains(_config.model)
          ? _config.model
          : _preferredModel(models);
      await saveConfig(
        baseUrl: effectiveBaseUrl,
        apiKey: effectiveApiKey,
        model: selected,
        models: models,
      );
      return models;
    } catch (e) {
      _lastError = e.toString();
      LoggerService().log('[AI Agent] Failed to fetch models: $e');
      notifyListeners();
      return const [];
    } finally {
      _isFetchingModels = false;
      client.close(force: true);
      notifyListeners();
    }
  }

  Future<String?> inferAnimeTitle(ParsedAnimeFile file) async {
    await initialize();
    if (!_config.isReady) return null;

    try {
      var title = await _inferAnimeTitleWithTool(file);
      title ??= await _inferAnimeTitlePlain(file);
      if (title == null) return null;
      LoggerService().log('[AI Agent] "$title" inferred from ${file.fileName}');
      return title;
    } catch (e) {
      LoggerService().log('[AI Agent] Title inference failed: $e');
      return null;
    }
  }

  Future<Map<String, String>> canonicalizeDmhyGroups(
    List<DmhyAnimeGroup> groups,
  ) async {
    await initialize();
    if (!_config.isReady || groups.isEmpty) return const {};
    try {
      final model = ChatOpenAI(
        apiKey: _config.apiKey.trim(),
        baseUrl: _normalizeBaseUrl(_config.baseUrl),
        defaultOptions: ChatOpenAIOptions(
          model: _config.model.trim(),
          temperature: 0,
          maxTokens: 1200,
          tools: const [_dmhyGroupingTool],
          toolChoice: ChatToolChoice.forced(name: _dmhyGroupingToolName),
        ),
      );
      final summary = groups
          .map(
            (group) => {
              'source_key': group.normalizedTitle,
              'parsed_title': group.title,
              'release_count': group.releaseCount,
              'seasons': group.seasons
                  .map((season) => season.seasonNumber)
                  .toList(),
              'episodes': group.seasons
                  .expand((season) => season.episodes)
                  .map((episode) => episode.episodeNumber)
                  .take(12)
                  .toList(),
              'release_titles': group.seasons
                  .expand((season) => season.episodes)
                  .expand((episode) => episode.releases)
                  .map((release) => release.title)
                  .take(8)
                  .toList(),
            },
          )
          .toList();
      final result = await model
          .invoke(
            PromptValue.chat([
              ChatMessage.system(
                'You are the canonical anime identity resolver for a DMHY '
                'search. Use release_titles as the strongest evidence. Merge '
                'English, Chinese, Japanese, romaji, kana, and fansub aliases '
                'when they refer to the same series (for example Yume Mita '
                'aliases). Merge only entries that are the same anime title '
                'and season franchise. '
                'Keep unrelated anime separate. Return every source_key '
                'through the tool with a concise canonical anime title.',
              ),
              ChatMessage.humanText(jsonEncode(summary)),
            ]),
          )
          .timeout(const Duration(seconds: 12));
      for (final toolCall in result.output.toolCalls) {
        if (toolCall.name != _dmhyGroupingToolName) continue;
        final rawGroups = toolCall.arguments['groups'];
        if (rawGroups is! List) continue;
        final allowedKeys = groups
            .map((group) => group.normalizedTitle)
            .toSet();
        final mapping = <String, String>{};
        for (final item in rawGroups.whereType<Map>()) {
          final sourceKey = item['source_key'] as String?;
          final canonicalTitle = _cleanTitle(
            item['canonical_title'] as String? ?? '',
          );
          if (sourceKey != null &&
              allowedKeys.contains(sourceKey) &&
              canonicalTitle != null) {
            mapping[sourceKey] = canonicalTitle;
          }
        }
        return mapping;
      }
    } catch (e) {
      LoggerService().log('[AI Agent] DMHY grouping failed: $e');
    }
    return const {};
  }

  Future<String?> recommendAnimeReason({
    required String title,
    required List<String> genres,
    required List<String> tags,
    required String? description,
    required int? averageScore,
  }) async {
    await initialize();
    if (!_config.isReady) return null;

    try {
      final model = ChatOpenAI(
        apiKey: _config.apiKey.trim(),
        baseUrl: _normalizeBaseUrl(_config.baseUrl),
        defaultOptions: ChatOpenAIOptions(
          model: _config.model.trim(),
          temperature: 0.45,
          maxTokens: 120,
        ),
      );
      final result = await model
          .invoke(
            PromptValue.chat([
              ChatMessage.system(
                '你是动画推荐助手。根据 AniList 的标题、标签、评分和简介，'
                '用中文输出一句 22 到 38 字的推荐理由。不要剧透，不要编号，'
                '不要提到 AniList，不要输出引号。',
              ),
              ChatMessage.humanText(
                [
                  '标题：$title',
                  if (genres.isNotEmpty) '类型：${genres.take(5).join('、')}',
                  if (tags.isNotEmpty) '标签：${tags.take(6).join('、')}',
                  if (averageScore != null) '评分：$averageScore/100',
                  if (description?.isNotEmpty == true)
                    '简介：${description!.replaceAll('\n', ' ')}',
                ].join('\n'),
              ),
            ]),
          )
          .timeout(const Duration(seconds: 10));
      final cleaned = result.output.contentAsString
          .replaceAll(
            RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false),
            '',
          )
          .replaceAll(RegExp(r'[\r\n]+'), ' ')
          .replaceAll(RegExp(r'''^["“”']+|["“”']+$'''), '')
          .trim();
      if (cleaned.isEmpty) return null;
      return cleaned.length > 56 ? '${cleaned.substring(0, 56)}…' : cleaned;
    } catch (e) {
      LoggerService().log('[AI Agent] Recommendation reason failed: $e');
      return null;
    }
  }

  Future<String?> _inferAnimeTitleWithTool(ParsedAnimeFile file) async {
    try {
      final model = ChatOpenAI(
        apiKey: _config.apiKey.trim(),
        baseUrl: _normalizeBaseUrl(_config.baseUrl),
        defaultOptions: ChatOpenAIOptions(
          model: _config.model.trim(),
          temperature: 0,
          maxTokens: 1600,
          tools: const [_libraryGroupTool],
          toolChoice: ChatToolChoice.forced(name: _libraryGroupToolName),
        ),
      );
      final result = await model
          .invoke(
            PromptValue.chat([
              ChatMessage.system(_toolSystemPrompt),
              ChatMessage.humanText(_userPrompt(file)),
            ]),
          )
          .timeout(const Duration(seconds: 10));
      for (final toolCall in result.output.toolCalls) {
        if (toolCall.name != _libraryGroupToolName) continue;
        final title = _cleanTitle(
          (toolCall.arguments['canonical_title'] as String?) ??
              _canonicalTitleFromRaw(toolCall.argumentsRaw) ??
              '',
        );
        if (title != null) return title;
      }
      return _cleanTitle(result.output.contentAsString);
    } catch (e) {
      LoggerService().log('[AI Agent] Tool title inference failed: $e');
      return null;
    }
  }

  Future<String?> _inferAnimeTitlePlain(ParsedAnimeFile file) async {
    try {
      final model = ChatOpenAI(
        apiKey: _config.apiKey.trim(),
        baseUrl: _normalizeBaseUrl(_config.baseUrl),
        defaultOptions: ChatOpenAIOptions(
          model: _config.model.trim(),
          temperature: 0,
          maxTokens: 1600,
        ),
      );
      final result = await model
          .invoke(
            PromptValue.chat([
              ChatMessage.system(_systemPrompt),
              ChatMessage.humanText(_userPrompt(file)),
            ]),
          )
          .timeout(const Duration(seconds: 10));
      return _cleanTitle(result.output.contentAsString);
    } catch (e) {
      LoggerService().log('[AI Agent] Plain title inference failed: $e');
      return null;
    }
  }

  static const _libraryGroupToolName = 'set_library_group_title';
  static const _dmhyGroupingToolName = 'consolidate_dmhy_groups';

  static const _dmhyGroupingTool = ToolSpec(
    name: _dmhyGroupingToolName,
    description: 'Assign a canonical anime title to each parsed DMHY group.',
    inputJsonSchema: {
      'type': 'object',
      'properties': {
        'groups': {
          'type': 'array',
          'items': {
            'type': 'object',
            'properties': {
              'source_key': {'type': 'string'},
              'canonical_title': {'type': 'string'},
            },
            'required': ['source_key', 'canonical_title'],
            'additionalProperties': false,
          },
        },
      },
      'required': ['groups'],
      'additionalProperties': false,
    },
  );

  static const _libraryGroupTool = ToolSpec(
    name: _libraryGroupToolName,
    description:
        'Set the canonical anime title that should be used to search AniList '
        'and merge files into one library group.',
    inputJsonSchema: {
      'type': 'object',
      'properties': {
        'canonical_title': {
          'type': 'string',
          'description':
              'The complete official anime series or movie title only.',
        },
        'confidence': {
          'type': 'number',
          'description': 'Confidence from 0 to 1.',
        },
        'reason': {
          'type': 'string',
          'description': 'Short private note for debugging.',
        },
      },
      'required': ['canonical_title'],
      'additionalProperties': false,
    },
  );

  static const _toolSystemPrompt =
      'You repair anime library grouping. Use the set_library_group_title tool '
      'with the complete official anime title only. Exclude release group, '
      'episode, version, resolution, source, audio, subtitle, and codec text. '
      'When a suffix looks like an insert song, MV, PV, trailer, or edition, '
      'return the parent anime title unless it is the official standalone '
      'AniList title.';

  static const _systemPrompt =
      'You identify anime titles from release filenames. '
      'Return only the complete official anime title, with no quotes, no JSON, '
      'no labels, no explanation, no reasoning, and no episode/version/'
      'resolution text.';

  String _userPrompt(ParsedAnimeFile file) {
    return [
      'Filename: ${file.fileName}',
      'Parsed title: ${file.title}',
      if (file.releaseGroup?.isNotEmpty == true)
        'Release group: ${file.releaseGroup}',
      if (file.resolution?.isNotEmpty == true) 'Resolution: ${file.resolution}',
      if (file.episodeNumber != null) 'Episode: ${file.episodeNumber}',
      'Output the anime series/movie title only on the final line.',
    ].join('\n');
  }

  String? _cleanTitle(String value) {
    var cleaned = value.replaceAll(
      RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false),
      ' ',
    );
    cleaned = cleaned
        .replaceAll(RegExp(r'```[a-zA-Z]*'), '')
        .replaceAll('```', '')
        .replaceAll(
          RegExp(r'^\s*(title|anime|name)\s*:\s*', caseSensitive: false),
          '',
        )
        .replaceAll(RegExp(r'[\r\n]+'), ' ')
        .trim();
    if (cleaned.isEmpty && value.contains('</think>')) {
      cleaned = value.split('</think>').last.trim();
    }
    final quoted = RegExp(r'"([^"]{2,120})"').allMatches(cleaned).toList();
    if (quoted.isNotEmpty) {
      cleaned = quoted.last.group(1)!.trim();
    } else {
      final sentences = cleaned
          .split(RegExp(r'(?<=[.!?。！？])\s+'))
          .map((part) => part.trim())
          .where((part) => part.isNotEmpty)
          .toList();
      if (sentences.length > 1) cleaned = sentences.last;
    }
    if ((cleaned.startsWith('"') && cleaned.endsWith('"')) ||
        (cleaned.startsWith("'") && cleaned.endsWith("'"))) {
      cleaned = cleaned.substring(1, cleaned.length - 1).trim();
    }
    if (cleaned.isEmpty || cleaned.length > 120) return null;
    return cleaned;
  }

  String? _canonicalTitleFromRaw(String value) {
    if (value.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map) return decoded['canonical_title'] as String?;
    } catch (_) {
      return null;
    }
    return null;
  }

  String _preferredModel(List<String> models) {
    if (models.isEmpty) return '';
    final highspeed = models.where(
      (model) => model.toLowerCase().contains('highspeed'),
    );
    if (highspeed.isNotEmpty) return highspeed.first;
    final nonReasoning = models.where((model) {
      final lower = model.toLowerCase();
      return !lower.contains('m3') && !lower.contains('reason');
    });
    return nonReasoning.isNotEmpty ? nonReasoning.first : models.first;
  }

  String _normalizeBaseUrl(String value) {
    var url = value.trim();
    if (url.isEmpty) return const AiAgentConfig().baseUrl;
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  List<String> _decodeModels(String? value) {
    if (value == null || value.isEmpty) return const [];
    try {
      final decoded = jsonDecode(value);
      return decoded is List ? decoded.whereType<String>().toList() : const [];
    } catch (_) {
      return const [];
    }
  }
}
