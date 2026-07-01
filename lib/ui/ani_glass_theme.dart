import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

class AniGlassTheme {
  const AniGlassTheme._();

  static GlassThemeData get theme => GlassThemeData.simple(
    blur: 10,
    thickness: 32,
    quality: GlassQuality.premium,
    chromaticAberration: 0.018,
    lightIntensity: 0.75,
    ambientStrength: 0.12,
    refractiveIndex: 1.28,
    saturation: 1.22,
    borderRadius: 22,
    brightness: Brightness.light,
  );

  static const LiquidGlassSettings chrome = LiquidGlassSettings(
    blur: 8,
    thickness: 32,
    glassColor: Color(0x18FFFFFF),
    lightAngle: GlassDefaults.lightAngle,
    lightIntensity: 0.75,
    ambientStrength: 0.1,
    saturation: 1.24,
    refractiveIndex: 1.32,
    chromaticAberration: 0.018,
    specularSharpness: GlassSpecularSharpness.sharp,
  );

  static const LiquidGlassSettings hero = LiquidGlassSettings(
    blur: 12,
    thickness: 42,
    glassColor: Color(0x14FFFFFF),
    lightAngle: GlassDefaults.lightAngle,
    lightIntensity: 0.9,
    ambientStrength: 0.08,
    saturation: 1.34,
    refractiveIndex: 1.45,
    chromaticAberration: 0.024,
    glowIntensity: 0.55,
    specularSharpness: GlassSpecularSharpness.sharp,
  );

  static const LiquidGlassSettings playerPanel = LiquidGlassSettings(
    blur: 10,
    thickness: 16,
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

  static Widget background({String? coverUrl, bool light = true}) {
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
