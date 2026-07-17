import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:anivault/services/anime_library_service.dart';
import 'package:anivault/services/home_insights_service.dart';
import 'package:anivault/services/logger_service.dart';

class StartupAssetService {
  StartupAssetService._();

  static String? preferredBackgroundCoverUrl;

  static List<String> imageUrls() {
    final insights = HomeInsightsService();
    return uniqueUrls([
      ...AnimeLibraryService().series.map((series) => series.coverUrl),
      ...insights.todayUpdates.map((item) => item.coverUrl),
      ...insights.recommendations.map((item) => item.coverUrl),
      ...insights.seasonProgress.map((item) => item.series.coverUrl),
    ]);
  }

  @visibleForTesting
  static List<String> uniqueUrls(Iterable<String?> candidates) {
    return candidates
        .map((url) => url?.trim())
        .whereType<String>()
        .where((url) => url.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }

  static Future<void> precache(BuildContext context) async {
    final urls = imageUrls();
    if (urls.isEmpty) return;

    final libraryCovers = AnimeLibraryService().series
        .map((series) => series.coverUrl?.trim())
        .whereType<String>()
        .where((url) => url.isNotEmpty)
        .toList(growable: false);
    if (libraryCovers.isNotEmpty) {
      final daySeed = DateTime.now().difference(DateTime(2020)).inDays;
      preferredBackgroundCoverUrl =
          libraryCovers[daySeed % libraryCovers.length];
    }

    const concurrency = 4;
    for (var start = 0; start < urls.length; start += concurrency) {
      final end = math.min(start + concurrency, urls.length);
      await Future.wait(
        urls
            .sublist(start, end)
            .map((url) => _precacheUrl(context, url, width: 384)),
      );
    }

    final background = preferredBackgroundCoverUrl;
    if (background != null && context.mounted) {
      await _precacheUrl(context, background, width: 720);
    }
  }

  static Future<void> _precacheUrl(
    BuildContext context,
    String url, {
    required int width,
  }) async {
    if (!context.mounted) return;
    try {
      await precacheImage(
        ResizeImage(NetworkImage(url), width: width),
        context,
        onError: (error, stackTrace) {
          LoggerService().log(
            '[Startup] Image preload failed for $url: $error',
          );
        },
      );
    } catch (e) {
      LoggerService().log('[Startup] Image preload failed for $url: $e');
    }
  }
}
