---
name: liquid-glass-nav-replica
description: Use when porting or repairing Flutter navigation bars, tab bars, segmented controls, or sliding indicators built with sdegenaar/liquid_glass_widgets, especially when the user wants to copy a demo such as Apple Music and preserve the liquid indicator instead of accidentally creating a plain frosted-glass or oversized pill effect.
---

# Liquid Glass Nav Replica

## Core Rule

Treat the demo as the source of truth. Before editing app code, read the exact demo file from the installed package or a fresh clone of `sdegenaar/liquid_glass_widgets`.

Prefer the local Pub cache when available:

```powershell
Get-ChildItem -Recurse -Directory "$env:LOCALAPPDATA\Pub\Cache\git" |
  Where-Object { $_.Name -match 'liquid_glass_widgets' }
```

For the Apple Music bottom navigation, inspect:

```text
example/lib/apple_music/apple_music_demo.dart
```

Search inside it for:

```text
GlassTabBar.searchable
_barGlassSettings
interactionBehavior
indicatorColor
```

## Widget Choice

Use the widget family that matches the target surface:

- `GlassTabBar.bottom`: structural bottom navigation shell.
- `GlassTabBar.searchable`: Apple Music / Apple News style bottom navigation with morphing search.
- `GlassSegmentedControl`: inline segmented controls only.

Do not switch widget families just to chase a visual effect. If the target already has a working navigation shell, keep that shell and port only the demo's relevant parameters.

## Apple Music Nav Parameters

When copying Apple Music's liquid bottom-nav feel into an existing `GlassTabBar.bottom` or `GlassTabBar.searchable`, carry over this shape of configuration:

```dart
final barGlassSettings = LiquidGlassSettings(
  glassColor: Theme.of(context).brightness == Brightness.dark
      ? const Color(0xAA1C1C1E)
      : const Color(0xAAF2F2F7),
  thickness: 30,
  blur: 2,
  chromaticAberration: .01,
  lightAngle: GlassDefaults.lightAngle,
  lightIntensity: .5,
  ambientStrength: 0,
  refractiveIndex: 1.2,
  saturation: 1.2,
  specularSharpness: GlassSpecularSharpness.medium,
);
```

Then apply the demo-style tab bar parameters:

```dart
GlassTabBar.bottom(
  selectedIndex: selectedIndex,
  onTabSelected: onChanged,
  selectedIconColor: Colors.white,
  unselectedIconColor: Colors.white60,
  selectedLabelColor: Colors.white,
  unselectedLabelColor: Colors.white60,
  indicatorColor: Colors.white.withValues(alpha: 0.20),
  labelFontSize: 10,
  iconSize: 28,
  iconLabelSpacing: 0,
  quality: GlassQuality.premium,
  interactionBehavior: GlassInteractionBehavior.full,
  settings: barGlassSettings,
  barHeight: 64,
  verticalPadding: 16,
  spacing: 8,
  tabs: tabs,
)
```

Keep app-specific layout values such as width, position, selected index, labels, and callbacks unless the user explicitly asks to copy the full demo layout.

## Complete Reference Implementation

Use this full implementation when the user wants the AniVault home top bar and bottom filter bar to match the accepted Apple Music liquid navigation feel. It intentionally keeps the existing bar positions and widths while copying the Apple Music glass settings and interaction behavior.

Required imports:

```dart
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
```

Drop-in shared widget:

```dart
class _DemoTopGlassTabBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  final List<GlassTab> tabs;
  final double? tabWidth;

  const _DemoTopGlassTabBar({
    required this.selectedIndex,
    required this.onChanged,
    required this.tabs,
    this.tabWidth,
  });

  @override
  Widget build(BuildContext context) {
    const horizontalPadding = 20.0;
    final barGlassSettings = LiquidGlassSettings(
      glassColor: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xAA1C1C1E)
          : const Color(0xAAF2F2F7),
      thickness: 30,
      blur: 2,
      chromaticAberration: .01,
      lightAngle: GlassDefaults.lightAngle,
      lightIntensity: .5,
      ambientStrength: 0,
      refractiveIndex: 1.2,
      saturation: 1.2,
      specularSharpness: GlassSpecularSharpness.medium,
    );
    final preferredWidth = tabWidth == null
        ? double.infinity
        : tabWidth! * tabs.length + horizontalPadding * 2;

    return SizedBox(
      height: 104,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final barWidth = preferredWidth.isFinite
              ? preferredWidth.clamp(0.0, constraints.maxWidth)
              : constraints.maxWidth;

          return Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: barWidth,
              // ignore: experimental_member_use
              child: GlassAdaptiveScope(
                minQuality: GlassQuality.premium,
                child: GlassTabBar.bottom(
                  selectedIndex: selectedIndex,
                  onTabSelected: onChanged,
                  selectedIconColor: Colors.white,
                  unselectedIconColor: Colors.white60,
                  selectedLabelColor: Colors.white,
                  unselectedLabelColor: Colors.white60,
                  indicatorColor: Colors.white.withValues(alpha: 0.20),
                  labelFontSize: 10,
                  iconSize: 28,
                  iconLabelSpacing: 0,
                  quality: GlassQuality.premium,
                  interactionBehavior: GlassInteractionBehavior.full,
                  settings: barGlassSettings,
                  tabWidth: tabWidth,
                  barHeight: 64,
                  horizontalPadding: horizontalPadding,
                  verticalPadding: 16,
                  spacing: 8,
                  textStyle: const TextStyle(
                    fontFamily: 'SF Pro Display',
                    fontFamilyFallback: [
                      '.AppleSystemUIFont',
                      '-apple-system',
                      'Segoe UI',
                    ],
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                  selectedLabelStyle: const TextStyle(
                    fontFamily: 'SF Pro Display',
                    fontFamilyFallback: [
                      '.AppleSystemUIFont',
                      '-apple-system',
                      'Segoe UI',
                    ],
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                  tabs: tabs,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
```

Reuse it for the bottom filter bar like this:

```dart
class _FilterBar extends StatelessWidget {
  static const filters = ['All', 'Matched', 'Unknown', 'Multi-file'];

  final String selected;
  final ValueChanged<String> onSelected;

  const _FilterBar({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final index = filters.indexOf(selected).clamp(0, filters.length - 1);
    return _DemoTopGlassTabBar(
      selectedIndex: index,
      onChanged: (index) => onSelected(filters[index]),
      tabWidth: 96,
      tabs: const [
        GlassTab(label: 'All'),
        GlassTab(label: 'Matched'),
        GlassTab(label: 'Unknown'),
        GlassTab(label: 'Multi-file'),
      ],
    );
  }
}
```

## Anti-Patterns

Avoid these unless the demo itself uses them for the same surface:

- Setting `indicatorColor: Colors.transparent` when the user wants the Apple Music selected-pill look.
- Forcing custom `indicatorSettings` from a generic card/hero glass preset; this often turns the indicator into plain frosted glass.
- Adding `innerBlur` to fake the effect; it makes the selected pill read as a blur block.
- Copying `GlassTabBar.searchable` into a non-search UI unless the user wants the search pill too.
- Replacing a completed navigation shell with `GlassSegmentedControl` when the user only asked for the liquid bottom-nav effect.

## Validation

Always run:

```powershell
dart format <changed dart files>
flutter analyze
```

If Flutter marks generated platform files dirty only from line endings and there is no content diff, restore those generated files before committing.
