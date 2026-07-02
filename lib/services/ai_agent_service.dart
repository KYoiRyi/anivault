import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:langchain_core/chat_models.dart';
import 'package:langchain_core/prompts.dart';
import 'package:langchain_openai/langchain_openai.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anivault/services/anime_library_service.dart';
import 'package:anivault/services/logger_service.dart';

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
      final model = ChatOpenAI(
        apiKey: _config.apiKey.trim(),
        baseUrl: _normalizeBaseUrl(_config.baseUrl),
        defaultOptions: ChatOpenAIOptions(
          model: _config.model.trim(),
          temperature: 0,
          maxTokens: 1200,
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
      final title = _cleanTitle(result.output.contentAsString);
      if (title == null) return null;
      LoggerService().log('[AI Agent] "$title" inferred from ${file.fileName}');
      return title;
    } catch (e) {
      LoggerService().log('[AI Agent] Title inference failed: $e');
      return null;
    }
  }

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
