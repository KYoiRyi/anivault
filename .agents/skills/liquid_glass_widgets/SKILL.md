---
name: liquid_glass_widgets
description: Guidelines, design philosophy, rules, and code patterns for using the liquid_glass_widgets package in Flutter.
---

# Liquid Glass Widgets Integration Guide & Rules

This guide outlines the rules, layout structures, and best practices for implementing Apple iOS 26 "Liquid Glass" interfaces using `liquid_glass_widgets` in Flutter.

---

## 📐 Design Rules & Philosophy

> [!IMPORTANT]
> **Rule 1: Glass is for Navigation and Controls, Not Content**
> - **Opaque Content**: Keep lists, articles, media players, full-screen backgrounds, and standard content cards opaque.
> - **Glass Elements**: Only use glass for floating bars (`GlassAppBar`, `GlassTabBar`, `GlassToolbar`), action buttons, sheets, dropdown menus, and interactive controls (`GlassSlider`, `GlassSwitch`).

> [!WARNING]
> **Rule 2: Glass is a Platter, Not a Wrapper**
> Do not wrap other interactive glass widgets (like `GlassButton`, `GlassSwitch`, `GlassSlider`, or `GlassSegmentedControl`) inside an outer `GlassCard` or `GlassContainer`. 
> - **Allowed inside GlassCard/GlassContainer**: `Text`, `Icon`, standard `ListTile`/`CupertinoListTile`, and other non-glass standard Flutter widgets.
> - **Why?** Nested glass widgets degrade visual refraction quality by design and cause animation clip issues during jelly-physics overshoots.

---

## ⚙️ Glass Quality Modes

Choose the correct quality mode based on the position and scrolling behavior of the widget:

| Quality Mode | Target Widgets / Use Cases | Performance Characteristics |
| :--- | :--- | :--- |
| **`GlassQuality.premium`** | Static hero headers, isolated app/tab bars. | Uses full two-pass Impeller shader pipeline with chromatic aberration. **Do not use inside scrolling list views.** |
| **`GlassQuality.standard`** | Standard interactive buttons, sliders, switches. | Default option. Optimal for general interactive controls. |
| **`GlassQuality.minimal`** | Dense scrollable lists, low-end device fallbacks. | **Shader-free.** Uses standard `BackdropFilter` with specular stroke. Fires zero custom fragment shaders on scroll. |

---

## 🛠️ Code Patterns & Implementation

### 1. Startup Initialization & Wrap
Initialize and warm up shaders in `main()` to avoid first-frame white flashes, and wrap the root widget:

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Pre-caches fragment shaders
  await LiquidGlassWidgets.initialize();

  runApp(
    LiquidGlassWidgets.wrap(
      adaptiveQuality: true, // Automatically benchmarks device performance
      child: const MyApp(),
    ),
  );
}
```

### 2. Scaffold Layout (`GlassScaffold`)
Always prefer `GlassScaffold` for screens utilizing glass chrome. It coordinates background blur, bar isolation, edge fading, and safe areas:

```dart
GlassScaffold(
  background: Image.asset('assets/wallpaper.jpg', fit: BoxFit.cover),
  statusBarStyle: GlassStatusBarStyle.auto, // Adapts status bar icons dynamically
  appBar: GlassAppBar(
    title: const Text('My App'),
    trailing: GlassButton(
      icon: const Icon(Icons.edit),
      onTap: () {},
    ),
  ),
  bottomBar: GlassTabBar.bottom(
    selectedIndex: _currentIndex,
    onTabSelected: (i) => setState(() => _currentIndex = i),
    tabs: const [
      GlassTab(icon: Icon(Icons.home), label: 'Home'),
      GlassTab(icon: Icon(Icons.settings), label: 'Settings'),
    ],
  ),
  body: CustomScrollView(
    slivers: [
      // Scrollable opaque content goes here
    ],
  ),
)
```

### 3. Content-Aware Brightness
To make navigation chrome adapt to dark or light content scrolling underneath:

```dart
GlassScaffold(
  contentAwareBrightness: true, // Wires up content sampling automatically
  appBar: GlassAppBar(
    adaptiveBrightness: true,  // Adapts text/icons based on background contrast
    title: const Text('Adaptive Title'),
  ),
  body: CustomScrollView(
    slivers: [...],
  ),
)
```

### 4. Avoiding Repeat Warmup Jank (Cold Start Optimization)
Cache the device benchmark settled quality to prevent performance degradation on every fresh launch:

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getString('glass_quality');
  final initialQuality = saved != null 
      ? GlassQuality.values.byName(saved) 
      : null;

  await LiquidGlassWidgets.initialize();

  runApp(LiquidGlassWidgets.wrap(
    child: const MyApp(),
    adaptiveQuality: true,
    adaptiveConfig: GlassAdaptiveScopeConfig(
      initialQuality: initialQuality,
      onQualityChanged: (_, settledQuality) =>
          prefs.setString('glass_quality', settledQuality.name),
    ),
  ));
}
```

### 5. Gyroscope Dynamic Reflection
Drive specular highlights dynamically using a device gyroscope or other motion streams:

```dart
GlassMotionScope(
  stream: gyroscopeEvents.map((e) => e.y * 0.5), // Maps gyroscope Y rotation to specularity offset
  child: const HomeScreen(),
)
```

---

## ♿ Accessibility

Liquid glass widgets respect system preferences out of the box:
- **Reduce Motion**: Disables all spring/jelly physics animations and snaps elements instantly.
- **Reduce Transparency**: Bypasses the glass shader completely and falls back to flat frosted `BackdropFilter` panels.
