import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppLanguageMode { system, zh, en }

class AppI18n extends ChangeNotifier {
  static final AppI18n _instance = AppI18n._internal();
  factory AppI18n() => _instance;
  AppI18n._internal();

  static const _languageModeKey = 'app_language_mode';

  Locale _locale = PlatformDispatcher.instance.locale;
  AppLanguageMode _mode = AppLanguageMode.system;

  Locale get locale => _locale;
  AppLanguageMode get mode => _mode;
  String get languageCode => _locale.languageCode == 'zh' ? 'zh' : 'en';
  bool get isChinese => languageCode == 'zh';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _mode = switch (prefs.getString(_languageModeKey)) {
      'zh' => AppLanguageMode.zh,
      'en' => AppLanguageMode.en,
      _ => AppLanguageMode.system,
    };
    _locale = _localeForMode(_mode, PlatformDispatcher.instance.locale);
    notifyListeners();
  }

  Future<void> setMode(AppLanguageMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    _locale = _localeForMode(mode, PlatformDispatcher.instance.locale);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_languageModeKey, mode.name);
  }

  void updateSystemLocale(Locale locale) {
    if (_mode != AppLanguageMode.system) return;
    _setLocale(locale);
  }

  void _setLocale(Locale locale) {
    final next = locale.languageCode == 'zh'
        ? const Locale('zh')
        : const Locale('en');
    if (_locale == next) return;
    _locale = next;
    notifyListeners();
  }

  Locale _localeForMode(AppLanguageMode mode, Locale systemLocale) {
    return switch (mode) {
      AppLanguageMode.zh => const Locale('zh'),
      AppLanguageMode.en => const Locale('en'),
      AppLanguageMode.system =>
        systemLocale.languageCode == 'zh'
            ? const Locale('zh')
            : const Locale('en'),
    };
  }

  String t(String key) =>
      (_strings[languageCode] ?? _strings['en']!)[key] ?? key;

  String animeTitle({
    String? userPreferred,
    String? romaji,
    String? english,
    String? native,
  }) {
    final candidates = isChinese
        ? [native, userPreferred, english, romaji]
        : [english, userPreferred, romaji, native];
    for (final candidate in candidates) {
      final value = candidate?.trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return '';
  }
}

const _strings = {
  'en': {
    'todayContinue': 'Continue Watching',
    'weeklyProgress': 'Weekly Progress',
    'todayUpdates': 'Today Updates',
    'seasonProgress': 'Season Progress',
    'recommendations': 'New Anime Picks',
    'backgroundRefreshing': 'Refreshing',
    'fromLocalLibrary': 'From local library',
    'anilistAi': 'AniList + AI Agent',
    'emptyUpdates': 'No airing updates found today',
    'emptySeasonProgress': 'Season progress appears after matched local anime',
    'emptyRecommendations':
        'Seasonal recommendations will appear after refresh',
    'aiReason': 'AI Recommendation',
    'fallbackReason': 'This title is worth adding to the seasonal shortlist.',
    'description': 'Synopsis',
    'noDescription': 'No synopsis yet.',
    'justUpdated': 'Just updated',
    'waitingRefresh': 'Waiting refresh',
    'minutesAgo': 'minutes ago',
    'hoursAgo': 'hours ago',
    'seasonalAnime': 'Seasonal anime',
    'airingToday': 'Airing today',
    'episodeUpdate': 'Episode',
    'timePending': 'Time pending',
    'winter': 'Winter',
    'spring': 'Spring',
    'summer': 'Summer',
    'fall': 'Fall',
  },
  'zh': {
    'todayContinue': '今日继续观看',
    'weeklyProgress': '本周追番进度',
    'todayUpdates': '今日更新',
    'seasonProgress': '追番进度',
    'recommendations': '新番推荐',
    'backgroundRefreshing': '正在后台刷新',
    'fromLocalLibrary': '来自本地媒体库',
    'anilistAi': 'AniList + AI Agent',
    'emptyUpdates': '今天还没有抓到更新情报',
    'emptySeasonProgress': '本季度番剧会在入库并识别后显示进度',
    'emptyRecommendations': '后台会自动拉取本季新番并生成推荐理由',
    'aiReason': 'AI 推荐理由',
    'fallbackReason': '这部作品适合加入本季候选片单。',
    'description': '简介',
    'noDescription': '暂无简介。',
    'justUpdated': '刚刚更新',
    'waitingRefresh': '等待刷新',
    'minutesAgo': '分钟前',
    'hoursAgo': '小时前',
    'seasonalAnime': '本季新番',
    'airingToday': '今日放送',
    'episodeUpdate': '第',
    'timePending': '时间待定',
    'winter': '冬季',
    'spring': '春季',
    'summer': '夏季',
    'fall': '秋季',
  },
};
