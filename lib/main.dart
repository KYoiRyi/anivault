import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:anivault/ui/home_screen.dart';
import 'package:anivault/services/anime_library_service.dart';
import 'package:anivault/services/shader_service.dart';
import 'package:anivault/services/cache_manager_service.dart';
import 'package:anivault/services/smb_service.dart';
import 'package:anivault/services/theme_service.dart';
import 'package:anivault/services/torrent_service.dart';
import 'package:anivault/services/app_i18n.dart';
import 'package:anivault/services/home_insights_service.dart';
import 'package:anivault/services/logger_service.dart';
import 'package:anivault/services/watch_history_service.dart';
import 'package:anivault/ui/ani_glass_theme.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  PaintingBinding.instance.imageCache.maximumSize = 160;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 48 << 20;
  MediaKit.ensureInitialized();
  await LoggerService().initialize();

  // Extract shaders from assets to local filesystem for native hook support
  await ShaderService().initializeShaders();
  await CacheManagerService().initialize();
  await PathResolver.initialize();
  await TorrentService().initialize();
  await SMBService().init();
  await ThemeService().load();
  await AppI18n().load();

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
      listenable: Listenable.merge([ThemeService(), AppI18n()]),
      builder: (context, _) {
        return GlassTheme(
          data: AniGlassTheme.theme,
          child: MaterialApp(
            title: 'AniVault',
            debugShowCheckedModeBanner: false,
            supportedLocales: const [Locale('en'), Locale('zh')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            localeResolutionCallback: (locale, supportedLocales) {
              return AppI18n().locale;
            },
            locale: AppI18n().locale,
            themeMode: ThemeService().themeMode,
            theme: _buildTheme(Brightness.light),
            darkTheme: _buildTheme(Brightness.dark),
            home: const StartupGate(child: HomeScreen()),
          ),
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

class StartupGate extends StatefulWidget {
  final Widget child;

  const StartupGate({super.key, required this.child});

  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _ready = false;
  bool _showStartupOverlay = true;

  @override
  void initState() {
    super.initState();
    if (_isWidgetTest) {
      _ready = true;
      _showStartupOverlay = false;
      _controller = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1),
      );
      return;
    }
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
    _warmStart();
  }

  bool get _isWidgetTest => WidgetsBinding.instance.runtimeType
      .toString()
      .contains('TestWidgetsFlutterBinding');

  Future<void> _warmStart() async {
    final minimum = Future<void>.delayed(const Duration(seconds: 3));
    final warmup = Future.wait<void>([
      _preloadLibrary(),
      _preloadHome(),
      _precacheGlass(),
    ]);
    await Future.wait([minimum, warmup]);
    if (!mounted) return;
    setState(() => _ready = true);
    _controller.stop();
    Future<void>.delayed(const Duration(milliseconds: 560), () {
      if (mounted) setState(() => _showStartupOverlay = false);
    });
  }

  Future<void> _preloadLibrary() async {
    try {
      await WatchHistoryService().initialize();
      final prefs = await SharedPreferences.getInstance();
      final paths = (prefs.getStringList('media_library') ?? const [])
          .map(PathResolver.resolve)
          .toList();
      if (paths.isNotEmpty && AnimeLibraryService().series.isEmpty) {
        await AnimeLibraryService().refreshLibrary(
          paths,
          languageCode: AppI18n().languageCode,
        );
      }
    } catch (e) {
      LoggerService().log('[Startup] Library preload failed: $e');
    }
  }

  Future<void> _preloadHome() async {
    try {
      await HomeInsightsService().initialize();
    } catch (e) {
      LoggerService().log('[Startup] Home preload failed: $e');
    }
  }

  Future<void> _precacheGlass() async {
    try {
      await LiquidGlassWidgets.initialize();
    } catch (e) {
      LoggerService().log('[Startup] Glass warmup failed: $e');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedOpacity(
          opacity: _ready ? 1 : 0,
          duration: const Duration(milliseconds: 520),
          curve: Curves.easeOutCubic,
          child: _ready
              ? IgnorePointer(ignoring: false, child: widget.child)
              : const SizedBox.shrink(),
        ),
        if (_showStartupOverlay)
          AnimatedOpacity(
            opacity: _ready ? 0 : 1,
            duration: const Duration(milliseconds: 520),
            curve: Curves.easeOutCubic,
            child: IgnorePointer(
              ignoring: _ready,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF05070D), Color(0xFF121826)],
                  ),
                ),
                child: Center(child: _StartupMark(animation: _controller)),
              ),
            ),
          ),
      ],
    );
  }
}

class _StartupMark extends StatelessWidget {
  final Animation<double> animation;

  const _StartupMark({required this.animation});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CustomPaint(
              size: const Size(190, 136),
              painter: _StartupGlowPainter(animation.value),
              child: _StartupLogoImage(t: animation.value),
            ),
            const SizedBox(height: 16),
            Text(
              'AniVault',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.92),
                fontSize: 26,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _StartupLogoImage extends StatelessWidget {
  final double t;

  const _StartupLogoImage({required this.t});

  static const _asset = 'assets/branding/anivault_startup_mark.png';

  @override
  Widget build(BuildContext context) {
    final pulse = Curves.easeInOut.transform((t < 0.5 ? t : 1 - t) * 2);
    final sweep = Curves.easeInOutCubic.transform(t);
    return Transform.scale(
      scale: 0.985 + pulse * 0.018,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            _asset,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
          ),
          ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (bounds) {
              final start = -2.2 + sweep * 4.4;
              return LinearGradient(
                begin: Alignment(start, 0),
                end: Alignment(start + 1.0, 0),
                colors: [
                  Colors.transparent,
                  Colors.white.withValues(alpha: 0),
                  Colors.white.withValues(alpha: 0.52 + pulse * 0.12),
                  Colors.white.withValues(alpha: 0),
                  Colors.transparent,
                ],
                stops: const [0, 0.38, 0.50, 0.62, 1],
              ).createShader(bounds);
            },
            child: Image.asset(
              _asset,
              fit: BoxFit.contain,
              color: Colors.white,
              colorBlendMode: BlendMode.srcIn,
              filterQuality: FilterQuality.high,
            ),
          ),
        ],
      ),
    );
  }
}

class _StartupGlowPainter extends CustomPainter {
  final double t;

  const _StartupGlowPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final pulse = Curves.easeInOut.transform((t < 0.5 ? t : 1 - t) * 2);
    final glowPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.08, -0.03),
        radius: 0.78,
        colors: [
          const Color(0xFF22D3EE).withValues(alpha: 0.22 + pulse * 0.08),
          const Color(0xFF7C3AED).withValues(alpha: 0.15 + pulse * 0.05),
          Colors.transparent,
        ],
      ).createShader(rect.inflate(18));
    canvas.drawOval(rect.inflate(8), glowPaint);
  }

  @override
  bool shouldRepaint(covariant _StartupGlowPainter oldDelegate) =>
      oldDelegate.t != t;
}
