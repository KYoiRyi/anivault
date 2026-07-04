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
    final center = rect.center.translate(0, -2);
    final pulse = Curves.easeInOut.transform((t < 0.5 ? t : 1 - t) * 2);
    final sweep = Curves.easeInOutCubic.transform(t);

    canvas.drawOval(
      Rect.fromCenter(
        center: center,
        width: size.width * (1.02 + pulse * 0.04),
        height: size.height * (0.92 + pulse * 0.03),
      ),
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0.08, -0.06),
          radius: 0.76,
          colors: [
            const Color(0xFF26DFFF).withValues(alpha: 0.25 + pulse * 0.08),
            const Color(0xFF7C4DFF).withValues(alpha: 0.16 + pulse * 0.06),
            Colors.transparent,
          ],
        ).createShader(rect.inflate(18)),
    );

    final logoRect = Rect.fromCenter(
      center: center,
      width: size.width * 0.76,
      height: size.height * 0.58,
    );
    final body = _squircleDiamond(logoRect);
    final bodyBounds = body.getBounds();

    canvas.saveLayer(rect, Paint());
    canvas.drawPath(
      body,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF26E4F1),
            Color(0xFF2193F7),
            Color(0xFF443CF1),
            Color(0xFFB46BFF),
          ],
          stops: [0.02, 0.42, 0.68, 1],
        ).createShader(bodyBounds),
    );

    final leftFacet = Path()
      ..moveTo(logoRect.left + logoRect.width * 0.17, logoRect.center.dy)
      ..cubicTo(
        logoRect.left + logoRect.width * 0.30,
        logoRect.top + logoRect.height * 0.08,
        logoRect.left + logoRect.width * 0.45,
        logoRect.top + logoRect.height * 0.03,
        logoRect.left + logoRect.width * 0.50,
        logoRect.top + logoRect.height * 0.05,
      )
      ..cubicTo(
        logoRect.left + logoRect.width * 0.42,
        logoRect.top + logoRect.height * 0.34,
        logoRect.left + logoRect.width * 0.42,
        logoRect.top + logoRect.height * 0.66,
        logoRect.left + logoRect.width * 0.50,
        logoRect.bottom - logoRect.height * 0.05,
      )
      ..cubicTo(
        logoRect.left + logoRect.width * 0.36,
        logoRect.bottom - logoRect.height * 0.08,
        logoRect.left + logoRect.width * 0.25,
        logoRect.bottom - logoRect.height * 0.24,
        logoRect.left + logoRect.width * 0.17,
        logoRect.center.dy,
      )
      ..close();
    canvas.drawPath(
      leftFacet,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.15),
            const Color(0xFF0F77E8).withValues(alpha: 0.34),
          ],
        ).createShader(bodyBounds),
    );

    final centerFacet = Path()
      ..moveTo(logoRect.left + logoRect.width * 0.50, logoRect.top + 1)
      ..cubicTo(
        logoRect.left + logoRect.width * 0.67,
        logoRect.top + logoRect.height * 0.12,
        logoRect.left + logoRect.width * 0.75,
        logoRect.top + logoRect.height * 0.35,
        logoRect.left + logoRect.width * 0.76,
        logoRect.center.dy,
      )
      ..cubicTo(
        logoRect.left + logoRect.width * 0.75,
        logoRect.top + logoRect.height * 0.65,
        logoRect.left + logoRect.width * 0.67,
        logoRect.bottom - logoRect.height * 0.12,
        logoRect.left + logoRect.width * 0.50,
        logoRect.bottom - 1,
      )
      ..cubicTo(
        logoRect.left + logoRect.width * 0.57,
        logoRect.top + logoRect.height * 0.68,
        logoRect.left + logoRect.width * 0.57,
        logoRect.top + logoRect.height * 0.32,
        logoRect.left + logoRect.width * 0.50,
        logoRect.top + 1,
      )
      ..close();
    canvas.drawPath(
      centerFacet,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF93F5FF).withValues(alpha: 0.26),
            const Color(0xFF1C36E9).withValues(alpha: 0.56),
          ],
        ).createShader(bodyBounds),
    );

    final rightFacet = Path()
      ..moveTo(logoRect.left + logoRect.width * 0.61, logoRect.top + 4)
      ..cubicTo(
        logoRect.left + logoRect.width * 0.82,
        logoRect.top + logoRect.height * 0.20,
        logoRect.right - logoRect.width * 0.05,
        logoRect.center.dy,
        logoRect.left + logoRect.width * 0.61,
        logoRect.bottom - 4,
      )
      ..cubicTo(
        logoRect.left + logoRect.width * 0.73,
        logoRect.top + logoRect.height * 0.62,
        logoRect.left + logoRect.width * 0.73,
        logoRect.top + logoRect.height * 0.38,
        logoRect.left + logoRect.width * 0.61,
        logoRect.top + 4,
      )
      ..close();
    canvas.drawPath(
      rightFacet,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFFC89AFF).withValues(alpha: 0.58),
            const Color(0xFF563AF6).withValues(alpha: 0.70),
          ],
        ).createShader(bodyBounds),
    );

    canvas.clipPath(body);
    final shineX = logoRect.left + logoRect.width * (-0.35 + sweep * 1.7);
    final shine = Path()
      ..moveTo(shineX - 16, logoRect.bottom + 10)
      ..lineTo(shineX + 30, logoRect.top - 10)
      ..lineTo(shineX + 52, logoRect.top - 10)
      ..lineTo(shineX + 6, logoRect.bottom + 10)
      ..close();
    canvas.drawPath(
      shine,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0.18 + pulse * 0.08),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(bodyBounds),
    );
    canvas.restore();

    final play = _roundedPlay(
      Rect.fromCenter(
        center: center.translate(size.width * 0.035, 0),
        width: size.width * 0.34,
        height: size.height * 0.48,
      ),
    );
    canvas.drawPath(
      play,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.99),
            const Color(0xFFE8F8FF).withValues(alpha: 0.96),
          ],
        ).createShader(play.getBounds()),
    );

    canvas.drawPath(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.15
        ..strokeCap = StrokeCap.round
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.34),
            const Color(0xFF31E5FF).withValues(alpha: 0.12),
            const Color(0xFFB982FF).withValues(alpha: 0.32),
          ],
        ).createShader(bodyBounds),
    );
  }

  Path _squircleDiamond(Rect rect) {
    final w = rect.width;
    final h = rect.height;
    final left = rect.left;
    final right = rect.right;
    final top = rect.top;
    final bottom = rect.bottom;
    final cy = rect.center.dy;
    return Path()
      ..moveTo(left + w * 0.08, cy)
      ..cubicTo(
        left + w * 0.23,
        top + h * 0.18,
        left + w * 0.34,
        top,
        left + w * 0.52,
        top,
      )
      ..cubicTo(
        left + w * 0.68,
        top + h * 0.02,
        right - w * 0.14,
        top + h * 0.22,
        right - w * 0.04,
        cy,
      )
      ..cubicTo(
        right - w * 0.14,
        bottom - h * 0.22,
        left + w * 0.68,
        bottom - h * 0.02,
        left + w * 0.52,
        bottom,
      )
      ..cubicTo(
        left + w * 0.34,
        bottom,
        left + w * 0.23,
        bottom - h * 0.18,
        left + w * 0.08,
        cy,
      )
      ..close();
  }

  Path _roundedPlay(Rect rect) {
    return Path()
      ..moveTo(rect.left + rect.width * 0.20, rect.top + rect.height * 0.13)
      ..quadraticBezierTo(
        rect.left + rect.width * 0.17,
        rect.top,
        rect.left + rect.width * 0.31,
        rect.top + rect.height * 0.07,
      )
      ..lineTo(
        rect.right - rect.width * 0.05,
        rect.center.dy - rect.height * 0.08,
      )
      ..quadraticBezierTo(
        rect.right + rect.width * 0.07,
        rect.center.dy,
        rect.right - rect.width * 0.05,
        rect.center.dy + rect.height * 0.08,
      )
      ..lineTo(rect.left + rect.width * 0.31, rect.bottom - rect.height * 0.07)
      ..quadraticBezierTo(
        rect.left + rect.width * 0.17,
        rect.bottom,
        rect.left + rect.width * 0.20,
        rect.bottom - rect.height * 0.13,
      )
      ..close();
  }

  @override
  bool shouldRepaint(covariant _AniVaultLogoPainter oldDelegate) =>
      oldDelegate.t != t;
}
