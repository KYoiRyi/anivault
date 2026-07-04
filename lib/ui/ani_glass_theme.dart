import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'package:anivault/services/theme_service.dart';

class AniGlassTheme {
  const AniGlassTheme._();

  static bool isLight(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light;

  static Color textColor(BuildContext context) =>
      isLight(context) ? Colors.black : Colors.white;

  static Color secondaryTextColor(BuildContext context) =>
      isLight(context) ? Colors.black54 : Colors.white70;

  static Color tertiaryTextColor(BuildContext context) =>
      isLight(context) ? Colors.black45 : Colors.white54;

  static Color subtleBorderColor(BuildContext context) =>
      isLight(context) ? const Color(0x1F000000) : const Color(0x1AFFFFFF);

  static Color subtleSurfaceColor(BuildContext context) =>
      isLight(context) ? const Color(0x12FFFFFF) : const Color(0x12FFFFFF);

  static GlassThemeData get theme => GlassThemeData.simple(
    blur: 10,
    thickness: 28,
    quality: GlassQuality.premium,
    chromaticAberration: 0.012,
    lightIntensity: 0.48,
    ambientStrength: 0.04,
    refractiveIndex: 1.28,
    saturation: 1.12,
    borderRadius: 22,
    brightness: Brightness.dark,
  );

  static const LiquidGlassSettings chrome = LiquidGlassSettings(
    blur: 8,
    thickness: 24,
    shadowElevation: 2.0,
    glassColor: Color(0x0EFFFFFF),
    lightAngle: GlassDefaults.lightAngle,
    lightIntensity: 0.42,
    ambientStrength: 0.03,
    saturation: 1.1,
    refractiveIndex: 1.22,
    chromaticAberration: 0.01,
    specularSharpness: GlassSpecularSharpness.sharp,
  );

  static const LiquidGlassSettings hero = LiquidGlassSettings(
    blur: 12,
    thickness: 30,
    shadowElevation: 2.0,
    glassColor: Color(0x10FFFFFF),
    lightAngle: GlassDefaults.lightAngle,
    lightIntensity: 0.5,
    ambientStrength: 0.04,
    saturation: 1.16,
    refractiveIndex: 1.34,
    chromaticAberration: 0.012,
    glowIntensity: 0.28,
    specularSharpness: GlassSpecularSharpness.sharp,
  );

  static const LiquidGlassSettings playerPanel = LiquidGlassSettings(
    blur: 10,
    thickness: 16,
    shadowElevation: 2.0,
    glassColor: Color(0x12FFFFFF),
    lightAngle: 0.72 * math.pi,
    lightIntensity: 0.9,
    ambientStrength: 0.08,
    saturation: 1.18,
    refractiveIndex: 1.18,
    chromaticAberration: 0.0,
    glowIntensity: 0.42,
    specularSharpness: GlassSpecularSharpness.sharp,
  );

  static const LiquidGlassSettings playerControl = LiquidGlassSettings(
    blur: 0,
    thickness: 10,
    shadowElevation: 2.0,
    glassColor: Colors.transparent,
    lightAngle: 0.7 * math.pi,
    lightIntensity: 1.55,
    ambientStrength: 0.0,
    saturation: 1.35,
    refractiveIndex: 1.24,
    chromaticAberration: 0.0,
    glowIntensity: 0.65,
    specularSharpness: GlassSpecularSharpness.sharp,
  );

  static LiquidGlassSettings chromeFor(BuildContext context) {
    if (!isLight(context)) return chrome;
    return chrome.copyWith(
      glassColor: const Color(0xE9F3F6FA),
      backerColor: const Color(0xFFF3F6FA),
      platformViewFallbackColor: const Color(0xFFF3F6FA),
      shadowElevation: 5.0,
      whitenStrength: 0.2,
      ambientStrength: 0.16,
      lightIntensity: 0.58,
    );
  }

  static LiquidGlassSettings heroFor(BuildContext context) {
    if (!isLight(context)) return hero;
    return hero.copyWith(
      glassColor: const Color(0xEDF4F7FB),
      backerColor: const Color(0xFFF4F7FB),
      platformViewFallbackColor: const Color(0xFFF4F7FB),
      shadowElevation: 6.0,
      whitenStrength: 0.22,
      ambientStrength: 0.18,
      lightIntensity: 0.62,
    );
  }

  static LiquidGlassSettings playerPanelFor(BuildContext context) {
    if (!isLight(context)) return playerPanel;
    return playerPanel.copyWith(
      glassColor: const Color(0xDDEFF1F5),
      backerColor: const Color(0xFFEFF1F5),
      platformViewFallbackColor: const Color(0xFFEFF1F5),
      shadowElevation: 2.0,
      whitenStrength: 0.36,
    );
  }

  static LiquidGlassSettings playerControlFor(BuildContext context) {
    if (!isLight(context)) return playerControl;
    return playerControl.copyWith(
      glassColor: const Color(0xCCE8EAEE),
      backerColor: const Color(0xFFE8EAEE),
      platformViewFallbackColor: const Color(0xFFE8EAEE),
      shadowElevation: 2.0,
      whitenStrength: 0.32,
    );
  }

  static Widget background({
    String? coverUrl,
    bool light = true,
    AniBackgroundStyle style = AniBackgroundStyle.dynamic,
  }) {
    if (style == AniBackgroundStyle.solid) {
      return Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: light ? Colors.white : Colors.black,
            ),
          ),
          if (coverUrl != null)
            Opacity(
              opacity: light ? 0.05 : 0.14,
              child: Image.network(
                coverUrl,
                fit: BoxFit.cover,
                cacheWidth: 900,
                errorBuilder: (context, error, stackTrace) =>
                    const SizedBox.shrink(),
              ),
            ),
        ],
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: light
              ? const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFFF8FBFF),
                      Color(0xFFEAF4FF),
                      Color(0xFFF8EEFF),
                      Color(0xFFFFFFFF),
                    ],
                  ),
                )
              : const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF090B14),
                      Color(0xFF111827),
                      Color(0xFF050505),
                    ],
                  ),
                ),
        ),
        if (light) ...const [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(-0.7, -0.92),
                radius: 1.0,
                colors: [Color(0x7738BDF8), Colors.transparent],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0.84, -0.18),
                radius: 1.1,
                colors: [Color(0x66F0ABFC), Colors.transparent],
              ),
            ),
          ),
        ],
        if (coverUrl != null)
          Opacity(
            opacity: light ? 0.12 : 0.28,
            child: Image.network(
              coverUrl,
              fit: BoxFit.cover,
              cacheWidth: 900,
              errorBuilder: (context, error, stackTrace) =>
                  const SizedBox.shrink(),
            ),
          ),
        if (!light) ...const [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(-0.65, -0.88),
                radius: 1.1,
                colors: [Color(0x6638BDF8), Colors.transparent],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0.86, -0.2),
                radius: 1.0,
                colors: [Color(0x55F472B6), Colors.transparent],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Color(0xDD050505)],
              ),
            ),
          ),
        ],
        if (light) ...const [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x66FFFFFF), Color(0xCCFFFFFF)],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class AnimatedGlassEntrance extends StatelessWidget {
  final int index;
  final Widget child;

  const AnimatedGlassEntrance({
    super.key,
    required this.index,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 360 + (index.clamp(0, 10) * 35)),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 18),
            child: Transform.scale(scale: 0.96 + value * 0.04, child: child),
          ),
        );
      },
      child: child,
    );
  }
}
