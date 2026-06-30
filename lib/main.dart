import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:anivault/ui/home_screen.dart';
import 'package:anivault/services/shader_service.dart';
import 'package:anivault/services/cache_manager_service.dart';
import 'package:anivault/services/smb_service.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  // Extract shaders from assets to local filesystem for native hook support
  await ShaderService().initializeShaders();
  await CacheManagerService().initialize();
  await SMBService().init();

  // Initialize liquid glass shaders
  await LiquidGlassWidgets.initialize();

  runApp(LiquidGlassWidgets.wrap(
    child: const AniVaultApp(),
    adaptiveQuality: true,
    adaptiveConfig: const GlassAdaptiveScopeConfig(
      initialQuality: GlassQuality.premium,
    ),
  ));
}

class AniVaultApp extends StatelessWidget {
  const AniVaultApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AniVault',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.grey,
        scaffoldBackgroundColor: Colors.black, // Pure black
        textTheme: _thinTextTheme(ThemeData.dark().textTheme),
        primaryTextTheme: _thinTextTheme(ThemeData.dark().primaryTextTheme),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.black,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
      ),
      home: const HomeScreen(),
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
    return style?.copyWith(
      fontWeight: FontWeight.w300,
    );
  }
}
