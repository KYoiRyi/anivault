import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AniBackgroundStyle { dynamic, solid }

enum AniGlassQualityMode { minimal, standard, premium }

class ThemeService extends ChangeNotifier {
  static final ThemeService _instance = ThemeService._internal();

  factory ThemeService() => _instance;

  ThemeService._internal();

  static const _themeModeKey = 'appearance_theme_mode';
  static const _backgroundStyleKey = 'appearance_background_style';
  static const _glassQualityKey = 'appearance_glass_quality';

  ThemeMode _themeMode = ThemeMode.system;
  AniBackgroundStyle _backgroundStyle = AniBackgroundStyle.dynamic;
  AniGlassQualityMode _glassQuality = AniGlassQualityMode.premium;

  ThemeMode get themeMode => _themeMode;
  AniBackgroundStyle get backgroundStyle => _backgroundStyle;
  AniGlassQualityMode get glassQuality => _glassQuality;
  GlassQuality get glassQualityValue => switch (_glassQuality) {
    AniGlassQualityMode.minimal => GlassQuality.minimal,
    AniGlassQualityMode.standard => GlassQuality.standard,
    AniGlassQualityMode.premium => GlassQuality.premium,
  };

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _themeMode = _themeModeFromName(prefs.getString(_themeModeKey));
    _backgroundStyle = _backgroundStyleFromName(
      prefs.getString(_backgroundStyleKey),
    );
    _glassQuality = _glassQualityFromName(prefs.getString(_glassQualityKey));
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

  Future<void> setGlassQuality(AniGlassQualityMode quality) async {
    if (_glassQuality == quality) return;
    _glassQuality = quality;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_glassQualityKey, quality.name);
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

  AniGlassQualityMode _glassQualityFromName(String? name) {
    return switch (name) {
      'minimal' => AniGlassQualityMode.minimal,
      'standard' => AniGlassQualityMode.standard,
      _ => AniGlassQualityMode.premium,
    };
  }
}
