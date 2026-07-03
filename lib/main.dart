import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:anivault/ui/home_screen.dart';
import 'package:anivault/services/shader_service.dart';
import 'package:anivault/services/cache_manager_service.dart';
import 'package:anivault/services/smb_service.dart';
import 'package:anivault/services/theme_service.dart';
import 'package:anivault/services/torrent_service.dart';
import 'package:anivault/ui/ani_glass_theme.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  // Extract shaders from assets to local filesystem for native hook support
  await ShaderService().initializeShaders();
  await CacheManagerService().initialize();
  await PathResolver.initialize();
  await TorrentService().initialize();
  await SMBService().init();
  await ThemeService().load();

  // Initialize liquid glass shaders
  await LiquidGlassWidgets.initialize();

  runApp(
    LiquidGlassWidgets.wrap(
      child: const AniVaultApp(),
      adaptiveQuality: false,
      theme: AniGlassTheme.theme,
    ),
  );
}

class AniVaultApp extends StatelessWidget {
  const AniVaultApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeService(),
      builder: (context, _) {
        return MaterialApp(
          title: 'AniVault',
          debugShowCheckedModeBanner: false,
          themeMode: ThemeService().themeMode,
          theme: _buildTheme(Brightness.light),
          darkTheme: _buildTheme(Brightness.dark),
          home: const HomeScreen(),
        );
      },
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final base = dark ? ThemeData.dark() : ThemeData.light();
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorSchemeSeed: const Color(0xFF38BDF8),
      scaffoldBackgroundColor: dark
          ? const Color(0xFF05070D)
          : const Color(0xFFF8FBFF),
      fontFamily: 'SF Pro Display',
      fontFamilyFallback: const [
        '.AppleSystemUIFont',
        '-apple-system',
        'Segoe UI',
        'Arial',
      ],
      textTheme: _thinTextTheme(base.textTheme),
      primaryTextTheme: _thinTextTheme(base.primaryTextTheme),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
    );
  }

  TextTheme _thinTextTheme(TextTheme base) {
    return base.copyWith(
      displayLarge: _thinTextStyle(base.displayLarge),
      displayMedium: _thinTextStyle(base.displayMedium),
      displaySmall: _thinTextStyle(base.displaySmall),
      headlineLarge: _thinTextStyle(base.headlineLarge),
      headlineMedium: _thinTextStyle(base.headlineMedium),
      headlineSmall: _thinTextStyle(base.headlineSmall),
      titleLarge: _thinTextStyle(base.titleLarge),
      titleMedium: _thinTextStyle(base.titleMedium),
      titleSmall: _thinTextStyle(base.titleSmall),
      bodyLarge: _thinTextStyle(base.bodyLarge),
      bodyMedium: _thinTextStyle(base.bodyMedium),
      bodySmall: _thinTextStyle(base.bodySmall),
      labelLarge: _thinTextStyle(base.labelLarge),
      labelMedium: _thinTextStyle(base.labelMedium),
      labelSmall: _thinTextStyle(base.labelSmall),
    );
  }

  TextStyle? _thinTextStyle(TextStyle? style) {
    return style?.copyWith(fontWeight: FontWeight.w300);
  }
}
