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
              size: const Size(166, 126),
              painter: _AniVaultLogoPainter(animation.value),
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

class _AniVaultLogoPainter extends CustomPainter {
  final double t;

  const _AniVaultLogoPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final pulse = Curves.easeInOut.transform((t < 0.5 ? t : 1 - t) * 2);
    final sweep = Curves.easeInOutCubic.transform(t);

    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF28D9FF).withValues(alpha: 0.28 + pulse * 0.12),
          const Color(0xFF9068FF).withValues(alpha: 0.18),
          Colors.transparent,
        ],
      ).createShader(rect.inflate(30));
    canvas.drawOval(rect.inflate(8), glowPaint);

    final logoRect = Rect.fromCenter(
      center: center.translate(0, -3),
      width: size.width * 0.86,
      height: size.height * 0.70,
    );
    final leftWing = _roundedDiamondPath(
      Rect.fromLTWH(
        logoRect.left,
        logoRect.top + logoRect.height * 0.08,
        logoRect.width * 0.56,
        logoRect.height * 0.84,
      ),
      leftSide: true,
    );
    final rightWing = _roundedDiamondPath(
      Rect.fromLTWH(
        logoRect.left + logoRect.width * 0.44,
        logoRect.top + logoRect.height * 0.03,
        logoRect.width * 0.56,
        logoRect.height * 0.94,
      ),
      leftSide: false,
    );
    final lensRect = Rect.fromCenter(
      center: logoRect.center,
      width: logoRect.width * 0.49,
      height: logoRect.height * 0.98,
    );
    final lensPath = Path()
      ..addOval(lensRect)
      ..moveTo(lensRect.left + lensRect.width * 0.12, lensRect.center.dy)
      ..lineTo(lensRect.right - lensRect.width * 0.08, lensRect.top + 2)
      ..lineTo(lensRect.right + lensRect.width * 0.14, lensRect.center.dy)
      ..lineTo(lensRect.right - lensRect.width * 0.08, lensRect.bottom - 2)
      ..close();

    canvas.saveLayer(rect, Paint());
    canvas.drawPath(
      leftWing,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF27E7F1), Color(0xFF1B8DFF)],
        ).createShader(logoRect),
    );
    canvas.drawPath(
      rightWing,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomRight,
          colors: [Color(0xFFB78CFF), Color(0xFF6F42F5)],
        ).createShader(logoRect),
    );
    canvas.drawPath(
      lensPath,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0x9927E7F1), Color(0xDD2446FF)],
        ).createShader(lensRect),
    );

    final facetLeft = Path()
      ..moveTo(logoRect.left + logoRect.width * 0.23, logoRect.center.dy)
      ..quadraticBezierTo(
        logoRect.left + logoRect.width * 0.30,
        logoRect.top + logoRect.height * 0.03,
        logoRect.left + logoRect.width * 0.52,
        logoRect.top + logoRect.height * 0.10,
      )
      ..lineTo(logoRect.left + logoRect.width * 0.45, logoRect.bottom)
      ..quadraticBezierTo(
        logoRect.left + logoRect.width * 0.31,
        logoRect.bottom - logoRect.height * 0.10,
        logoRect.left + logoRect.width * 0.23,
        logoRect.center.dy,
      )
      ..close();
    canvas.drawPath(
      facetLeft,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x5028F3FF), Color(0xAA126FE9)],
        ).createShader(logoRect),
    );

    final facetRight = Path()
      ..moveTo(logoRect.left + logoRect.width * 0.58, logoRect.top + 4)
      ..quadraticBezierTo(
        logoRect.left + logoRect.width * 0.77,
        logoRect.center.dy,
        logoRect.left + logoRect.width * 0.55,
        logoRect.bottom - 3,
      )
      ..lineTo(logoRect.left + logoRect.width * 0.74, logoRect.bottom)
      ..quadraticBezierTo(
        logoRect.right - 2,
        logoRect.center.dy,
        logoRect.left + logoRect.width * 0.74,
        logoRect.top,
      )
      ..close();
    canvas.drawPath(
      facetRight,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomCenter,
          colors: [Color(0x609E85FF), Color(0xBB273BDE)],
        ).createShader(logoRect),
    );

    final shineX = logoRect.left + logoRect.width * (-0.18 + sweep * 1.36);
    final shinePath = Path()
      ..moveTo(shineX - 15, logoRect.bottom + 8)
      ..lineTo(shineX + 24, logoRect.top - 8)
      ..lineTo(shineX + 44, logoRect.top - 8)
      ..lineTo(shineX + 5, logoRect.bottom + 8)
      ..close();
    canvas.drawPath(
      shinePath,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.0),
            Colors.white.withValues(alpha: 0.22 + pulse * 0.08),
            Colors.white.withValues(alpha: 0.0),
          ],
        ).createShader(logoRect),
    );

    final playPath = Path()
      ..moveTo(center.dx - 17, center.dy - 31)
      ..quadraticBezierTo(
        center.dx - 20,
        center.dy - 36,
        center.dx - 13,
        center.dy - 40,
      )
      ..lineTo(center.dx + 40, center.dy - 8)
      ..quadraticBezierTo(
        center.dx + 48,
        center.dy - 3,
        center.dx + 40,
        center.dy + 3,
      )
      ..lineTo(center.dx - 13, center.dy + 36)
      ..quadraticBezierTo(
        center.dx - 20,
        center.dy + 40,
        center.dx - 17,
        center.dy + 31,
      )
      ..close();
    canvas.drawPath(playPath, Paint()..blendMode = BlendMode.clear);
    canvas.restore();

    final edgePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0x99FFFFFF), Color(0x4428D9FF), Color(0x88B78CFF)],
      ).createShader(logoRect);
    canvas.drawPath(leftWing, edgePaint);
    canvas.drawPath(rightWing, edgePaint);
  }

  Path _roundedDiamondPath(Rect rect, {required bool leftSide}) {
    final radius = rect.height * 0.18;
    final path = Path();
    if (leftSide) {
      path
        ..moveTo(rect.left + radius, rect.center.dy)
        ..quadraticBezierTo(
          rect.left + 2,
          rect.center.dy,
          rect.left + radius,
          rect.center.dy - radius,
        )
        ..lineTo(rect.center.dx - 2, rect.top + radius)
        ..quadraticBezierTo(
          rect.center.dx + radius,
          rect.top,
          rect.center.dx + radius * 2,
          rect.top + radius,
        )
        ..lineTo(rect.right, rect.center.dy)
        ..lineTo(rect.center.dx + radius * 2, rect.bottom - radius)
        ..quadraticBezierTo(
          rect.center.dx + radius,
          rect.bottom,
          rect.center.dx - 2,
          rect.bottom - radius,
        )
        ..lineTo(rect.left + radius, rect.center.dy + radius)
        ..quadraticBezierTo(
          rect.left + 2,
          rect.center.dy,
          rect.left + radius,
          rect.center.dy,
        );
    } else {
      path
        ..moveTo(rect.left, rect.center.dy)
        ..lineTo(rect.center.dx - radius, rect.top + radius)
        ..quadraticBezierTo(
          rect.center.dx,
          rect.top,
          rect.center.dx + radius,
          rect.top + radius,
        )
        ..lineTo(rect.right - radius, rect.center.dy - radius)
        ..quadraticBezierTo(
          rect.right - 2,
          rect.center.dy,
          rect.right - radius,
          rect.center.dy + radius,
        )
        ..lineTo(rect.center.dx + radius, rect.bottom - radius)
        ..quadraticBezierTo(
          rect.center.dx,
          rect.bottom,
          rect.center.dx - radius,
          rect.bottom - radius,
        )
        ..close();
    }
    return path;
  }

  @override
  bool shouldRepaint(covariant _AniVaultLogoPainter oldDelegate) =>
      oldDelegate.t != t;
}
