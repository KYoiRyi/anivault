import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:anivault/services/anime_library_service.dart';
import 'package:anivault/services/torrent_service.dart';

class WatchRecord {
  final String videoPath;
  final String seriesId;
  final int? episodeNumber;
  final String episodeTitle;
  final int timestamp; // ms since epoch
  final int secondsWatched;
  final int progressMs;
  final int durationMs;

  WatchRecord({
    required this.videoPath,
    required this.seriesId,
    this.episodeNumber,
    required this.episodeTitle,
    required this.timestamp,
    required this.secondsWatched,
    required this.progressMs,
    required this.durationMs,
  });

  Map<String, dynamic> toJson() => {
    'videoPath': videoPath,
    'seriesId': seriesId,
    'episodeNumber': episodeNumber,
    'episodeTitle': episodeTitle,
    'timestamp': timestamp,
    'secondsWatched': secondsWatched,
    'progressMs': progressMs,
    'durationMs': durationMs,
  };

  factory WatchRecord.fromJson(Map<String, dynamic> json) => WatchRecord(
    videoPath: PathResolver.resolve(json['videoPath'] as String),
    seriesId: json['seriesId'] as String,
    episodeNumber: json['episodeNumber'] as int?,
    episodeTitle: json['episodeTitle'] as String? ?? '',
    timestamp: json['timestamp'] as int,
    secondsWatched: json['secondsWatched'] as int? ?? 0,
    progressMs: json['progressMs'] as int? ?? 0,
    durationMs: json['durationMs'] as int? ?? 0,
  );

  double get progressRatio => durationMs > 0 ? progressMs / durationMs : 0.0;
}

class WatchWeeklyStats {
  final int episodesWatched;
  final Duration watchDuration;
  final int consecutiveDays;
  final int completedSeriesCount;
  final double changePercentage;
  final String narrative;

  WatchWeeklyStats({
    required this.episodesWatched,
    required this.watchDuration,
    required this.consecutiveDays,
    required this.completedSeriesCount,
    required this.changePercentage,
    required this.narrative,
  });
}

class WatchHistoryService extends ChangeNotifier {
  static final WatchHistoryService _instance = WatchHistoryService._internal();
  factory WatchHistoryService() => _instance;
  WatchHistoryService._internal();

  static const _historyKey = 'watch_history_records_v1';
  List<WatchRecord> _records = [];
  bool _initialized = false;

  List<WatchRecord> get records => List.unmodifiable(_records);

  Future<void> initialize() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_historyKey);
    if (jsonStr != null) {
      try {
        final list = json.decode(jsonStr) as List;
        _records = list
            .map((item) => WatchRecord.fromJson(item as Map<String, dynamic>))
            .toList();
      } catch (e) {
        _records = [];
      }
    }
    _initialized = true;
    notifyListeners();
  }

  Future<void> saveWatchProgress({
    required String videoPath,
    required int progressMs,
    required int durationMs,
    required int secondsWatched,
  }) async {
    await initialize();

    // Try to find the series and episode from AnimeLibraryService
    String seriesId = 'unknown';
    int? episodeNumber;
    String episodeTitle = '';

    for (final series in AnimeLibraryService().series) {
      for (final ep in series.episodes) {
        if (ep.files.any((f) => f.path == videoPath)) {
          seriesId = series.id;
          episodeNumber = ep.number;
          episodeTitle = ep.title;
          break;
        }
      }
    }

    final now = DateTime.now();
    final todayStr = _formatDate(now);

    // Look for a record for the same videoPath watched today to merge secondsWatched
    int existingIndex = -1;
    for (int i = 0; i < _records.length; i++) {
      final rec = _records[i];
      if (rec.videoPath == videoPath) {
        final recDate = _formatDate(
          DateTime.fromMillisecondsSinceEpoch(rec.timestamp),
        );
        if (recDate == todayStr) {
          existingIndex = i;
          break;
        }
      }
    }

    int newSeconds = secondsWatched;
    if (existingIndex != -1) {
      newSeconds += _records[existingIndex].secondsWatched;
      _records.removeAt(existingIndex);
    }

    final newRecord = WatchRecord(
      videoPath: videoPath,
      seriesId: seriesId,
      episodeNumber: episodeNumber,
      episodeTitle: episodeTitle,
      timestamp: now.millisecondsSinceEpoch,
      secondsWatched: newSeconds,
      progressMs: progressMs,
      durationMs: durationMs,
    );

    // Insert at the beginning to keep chronological order
    _records.insert(0, newRecord);

    // Limit to 500 records to prevent bloating SharedPreferences
    if (_records.length > 500) {
      _records = _records.sublist(0, 500);
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _historyKey,
      json.encode(_records.map((r) => r.toJson()).toList()),
    );
    notifyListeners();
  }

  WatchRecord? getLastWatchedRecord() {
    if (_records.isEmpty) return null;
    return _records.first;
  }

  List<WatchRecord> getRecentRecords({int limit = 5}) {
    final uniqueSeries = <String>{};
    final result = <WatchRecord>[];
    for (final rec in _records) {
      if (rec.seriesId != 'unknown' && !uniqueSeries.contains(rec.seriesId)) {
        uniqueSeries.add(rec.seriesId);
        result.add(rec);
        if (result.length >= limit) break;
      }
    }
    return result;
  }

  WatchWeeklyStats getWeeklyStats() {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final startOfThisWeek = startOfToday.subtract(const Duration(days: 6));
    final startOfLastWeek = startOfThisWeek.subtract(const Duration(days: 7));

    final thisWeekRecords = _records
        .where((r) => r.timestamp >= startOfThisWeek.millisecondsSinceEpoch)
        .toList();
    final lastWeekRecords = _records
        .where(
          (r) =>
              r.timestamp >= startOfLastWeek.millisecondsSinceEpoch &&
              r.timestamp < startOfThisWeek.millisecondsSinceEpoch,
        )
        .toList();

    // 1. Watch duration this week
    final thisWeekSeconds = thisWeekRecords.fold(
      0,
      (sum, r) => sum + r.secondsWatched,
    );
    final lastWeekSeconds = lastWeekRecords.fold(
      0,
      (sum, r) => sum + r.secondsWatched,
    );

    // 2. Episodes watched this week
    final episodesThisWeek = thisWeekRecords
        .map((r) => r.videoPath)
        .toSet()
        .length;

    // 3. Consecutive watch days
    final watchedDates = _records.where((r) => r.secondsWatched > 0).map((r) {
      return _formatDate(DateTime.fromMillisecondsSinceEpoch(r.timestamp));
    }).toSet();

    int streak = 0;
    DateTime checkDate = startOfToday;
    if (!watchedDates.contains(_formatDate(checkDate))) {
      checkDate = checkDate.subtract(const Duration(days: 1));
    }
    while (watchedDates.contains(_formatDate(checkDate))) {
      streak++;
      checkDate = checkDate.subtract(const Duration(days: 1));
    }

    // 4. Completed series this week
    int completedCount = 0;
    for (final series in AnimeLibraryService().series) {
      if (series.episodes.isEmpty) continue;
      final lastEp = series.episodes.last;
      // Find latest watch record for this episode
      final epRecords = _records
          .where(
            (r) => r.seriesId == series.id && r.episodeNumber == lastEp.number,
          )
          .toList();
      if (epRecords.isNotEmpty) {
        final latestEpRec = epRecords.first;
        if (latestEpRec.timestamp >= startOfThisWeek.millisecondsSinceEpoch &&
            latestEpRec.progressRatio > 0.9) {
          completedCount++;
        }
      }
    }

    // 5. Change percentage
    double changePct = 0.0;
    if (lastWeekSeconds == 0) {
      changePct = thisWeekSeconds > 0 ? 100.0 : 0.0;
    } else {
      changePct = ((thisWeekSeconds - lastWeekSeconds) / lastWeekSeconds) * 100;
    }

    // 6. Narrative
    final hours = thisWeekSeconds ~/ 3600;
    final minutes = (thisWeekSeconds % 3600) ~/ 60;
    String narrative = '';
    if (thisWeekSeconds == 0) {
      narrative = '本周你还没有在动画世界中度过时间，快去挑选一部喜欢的作品开启冒险吧！';
    } else {
      final timeStr = hours > 0 ? '$hours 小时 $minutes 分钟' : '$minutes 分钟';
      narrative = '本周你在动画世界中度过了 $timeStr。';
    }

    return WatchWeeklyStats(
      episodesWatched: episodesThisWeek,
      watchDuration: Duration(seconds: thisWeekSeconds),
      consecutiveDays: streak,
      completedSeriesCount: completedCount,
      changePercentage: changePct,
      narrative: narrative,
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}
