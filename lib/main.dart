import 'dart:math' as math;

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
              size: const Size(118, 118),
              painter: _AniVaultLogoPainter(animation.value),
            ),
            const SizedBox(height: 18),
            Text(
              'AniVault',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.92),
                fontSize: 25,
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
    final draw = Curves.easeOutCubic.transform((t * 1.45).clamp(0.0, 1.0));

    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF38BDF8).withValues(alpha: 0.24 + pulse * 0.10),
          const Color(0xFFB56CFF).withValues(alpha: 0.14),
          Colors.transparent,
        ],
      ).createShader(rect.inflate(26));
    canvas.drawCircle(center, size.width * (0.54 + pulse * 0.03), glowPaint);

    final vaultRect = Rect.fromCenter(
      center: center,
      width: size.width * 0.66,
      height: size.height * 0.72,
    );
    final vaultPath = Path()
      ..addRRect(
        RRect.fromRectAndRadius(vaultRect, Radius.circular(size.width * 0.16)),
      );
    final fillPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF101827), Color(0xFF07111F)],
      ).createShader(vaultRect);
    canvas.drawPath(vaultPath, fillPaint);

    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: -1.6,
        endAngle: 4.7,
        transform: GradientRotation(t * math.pi * 2),
        colors: const [
          Color(0xFF38BDF8),
          Color(0xFFFFFFFF),
          Color(0xFFB56CFF),
          Color(0xFF38BDF8),
        ],
      ).createShader(vaultRect.inflate(3));
    canvas.drawPath(vaultPath, borderPaint);

    final clipPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.78);
    final topLine = Path()
      ..moveTo(vaultRect.left + 18, vaultRect.top + 21)
      ..lineTo(vaultRect.right - 18, vaultRect.top + 21);
    _drawProgressPath(canvas, topLine, clipPaint, draw);

    final playPath = Path()
      ..moveTo(center.dx - 13, center.dy - 19)
      ..lineTo(center.dx - 13, center.dy + 19)
      ..lineTo(center.dx + 22, center.dy)
      ..close();
    final playPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFFFFFF), Color(0xFF38BDF8)],
      ).createShader(playPath.getBounds());
    canvas.drawPath(playPath, playPaint);

    final orbitRadius = size.width * 0.43;
    final orbitAngle = t * math.pi * 2;
    final dot =
        center +
        Offset(math.cos(orbitAngle), math.sin(orbitAngle)) * orbitRadius;
    canvas.drawCircle(dot, 3.1, Paint()..color = const Color(0xFFFFFFFF));

    final sparklePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFB56CFF).withValues(alpha: 0.55 + pulse * 0.25);
    final sparkleCenter = Offset(vaultRect.right - 4, vaultRect.top + 8);
    canvas.drawLine(
      sparkleCenter + const Offset(-6, 0),
      sparkleCenter + const Offset(6, 0),
      sparklePaint,
    );
    canvas.drawLine(
      sparkleCenter + const Offset(0, -6),
      sparkleCenter + const Offset(0, 6),
      sparklePaint,
    );
  }

  void _drawProgressPath(
    Canvas canvas,
    Path path,
    Paint paint,
    double progress,
  ) {
    for (final metric in path.computeMetrics()) {
      canvas.drawPath(metric.extractPath(0, metric.length * progress), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _AniVaultLogoPainter oldDelegate) =>
      oldDelegate.t != t;
}
