import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AniBackgroundStyle { dynamic, solid }

class ThemeService extends ChangeNotifier {
  static final ThemeService _instance = ThemeService._internal();

  factory ThemeService() => _instance;

  ThemeService._internal();

  static const _themeModeKey = 'appearance_theme_mode';
  static const _backgroundStyleKey = 'appearance_background_style';

  ThemeMode _themeMode = ThemeMode.system;
  AniBackgroundStyle _backgroundStyle = AniBackgroundStyle.dynamic;

  ThemeMode get themeMode => _themeMode;
  AniBackgroundStyle get backgroundStyle => _backgroundStyle;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _themeMode = _themeModeFromName(prefs.getString(_themeModeKey));
    _backgroundStyle = _backgroundStyleFromName(
      prefs.getString(_backgroundStyleKey),
    );
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModeKey, mode.name);
  }

  Future<void> setBackgroundStyle(AniBackgroundStyle style) async {
    if (_backgroundStyle == style) return;
    _backgroundStyle = style;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_backgroundStyleKey, style.name);
  }

  ThemeMode _themeModeFromName(String? name) {
    return switch (name) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  AniBackgroundStyle _backgroundStyleFromName(String? name) {
    return switch (name) {
      'solid' => AniBackgroundStyle.solid,
      _ => AniBackgroundStyle.dynamic,
    };
  }
}
