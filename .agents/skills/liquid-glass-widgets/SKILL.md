---
name: "liquid-glass-widgets"
description: "Combination patterns for Flutter `liquid_glass_widgets` (iOS 26 Liquid Glass) — Scaffold skeletons, sheet peek/half/full, teardrop menus, Apple Music searchable morph, magic-lens bars, refraction sources, motion highlights."
---

---
name: liquid-glass-widgets
description: Combination patterns for the Flutter `liquid_glass_widgets` package (iOS 26 Liquid Glass). Use when composing screen skeletons (GlassScaffold + AppBar + TabBar), sheets (GlassModalSheet peek/half/full), menus (GlassMenu teardrop morph), searchable bars (Apple Music morph), magic-lens bottom bars, refraction sources, content-aware brightness, motion-driven highlights, and theme override chains.
---

# Liquid Glass Widgets — 组合用法 Skill

> Flutter 上实现 **iOS 26 Liquid Glass** 的 UI 库 — shader 模糊、jelly 动画、动态光照。仓库 `sdegenaar/liquid_glass_widgets` · pub.dev `liquid_glass_widgets`。
>
> **两条铁律**：
> 1. 玻璃只属于 **导航与控制层**（app bar / tab bar / sheet / menu / 控件），内容区保持 opaque。
> 2. 玻璃 **不要套玻璃**。`GlassCard` / `GlassContainer` 是 base surface，不要用来包其他玻璃控件（库内已强制 `avoidsRefraction`）。

---

## 0. 一分钟上手

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LiquidGlassWidgets.initialize();   // 必调：预热 shader，避免首帧白闪
  runApp(LiquidGlassWidgets.wrap(child: const MyApp()));
}
```

每个屏幕先套 `GlassScaffold` — 自动处理背景、安全距离、z-order、滚动渐隐、bar 隔离、status bar。

---

## 1. 选型决策表（先用这个查）

| 场景 | 用 |
|---|---|
| 任何带 app bar / tab bar 的屏幕 | **`GlassScaffold`** |
| 不规则 Stack / 非 Scaffold 结构 | **`GlassPage`** |
| 局部悬浮面板（设置卡、popup） | **`GlassCard`** / **`GlassContainer`** |
| 多个玻璃元素共享一组参数 | **`AdaptiveLiquidGlassLayer`** |

---

## 2. 屏幕骨架三件套：GlassScaffold + AppBar + TabBar

Apple 风格标准屏：壁纸 + 大标题 + 底部标签栏。

```dart
GlassScaffold(
  background: Image.asset('assets/wallpaper.jpg', fit: BoxFit.cover),
  statusBarStyle: GlassStatusBarStyle.auto,
  appBar: GlassAppBar(
    largeTitle: const GlassLargeTitle(text: 'Library'),
    leading: GlassIconButton(icon: const Icon(CupertinoIcons.text_alignleft), onTap: (){}),
    trailing: GlassButton(icon: const Icon(CupertinoIcons.search), onTap: (){}),
  ),
  bottomBar: GlassTabBar.bottom(
    selectedIndex: _i,
    onTabSelected: (i) => setState(() => _i = i),
    tabs: const [GlassTab(icon: Icon(CupertinoIcons.music_note), label: 'Listen')],
  ),
  body: CustomScrollView(slivers: [/* opaque 内容 */]),
)
```

**底部 bar 选择：**

| 想做 | 用 |
|---|---|
| 标准 iOS 26 标签栏 | `GlassTabBar.bottom` |
| 标签栏 ↔ 搜索栏 morph 切换 | `GlassTabBar.searchable`（Apple Music 同款） |
| 内联 pill 横向选择 | `GlassTabBar.inline` |
| 自定义中间按钮 / 凹槽 / magic-lens | `GlassBottomBar` |
| 居中一个搜索入口 | `GlassSearchableBottomBar` |

---

## 3. 搜索 morph 组合（Apple Music 同款招牌特效）

`GlassTabBar.searchable` 把标签栏圆角胶囊与搜索框融合 — 下拉搜索时标签栏 morph 成横条，再下拉恢复。

```dart
GlassTabBar.searchable(
  searchController: _search,
  searchHintText: 'Search Music',
  selectedIndex: _i,
  onTabSelected: (i) => setState(() => _i = i),
  onSearchChanged: (q) {},
  onSearchSubmitted: (q) {},
  tabs: const [
    GlassTab(icon: Icon(CupertinoIcons.music_note), label: 'Listen Now'),
    GlassTab(icon: Icon(CupertinoIcons.search), label: 'Browse'),
    GlassTab(icon: Icon(CupertinoIcons.radio), label: 'Radio'),
  ],
)
```

`morphDuration` 控制 morph 时长；外部监听 `onSearchChanged` 而不是依赖内部 TextField。

---

## 4. 内容感知亮度组合（自动切换图标明暗）

滚动时根据下方内容明暗自动切换 bar 图标（深底用白图标，浅底用黑图标），WCAG 对比度 + 双阈值防抖。

```dart
GlassScaffold(
  contentAwareBrightness: true,            // 整屏开关
  bottomBar: GlassTabBar.bottom(
    adaptiveBrightness: true,               // bar 端开关
    onBrightnessChanged: (b) => debugPrint(b),
    selectedIndex: _i,
    onTabSelected: (i) => setState(() => _i = i),
    tabs: const [/* ... */],
  ),
  body: CustomScrollView(slivers: [/* 滚动内容 */]),
)
```

**手动版**（无 `GlassScaffold`）：`GlassContentAwareScope` 包 Scaffold + `GlassContentAwareContent` 包 body + bar 端 `adaptiveBrightness: true`。

---

## 5. 设置页组合（iOS Settings 风格）

```dart
GlassScaffold(
  appBar: GlassAppBar(title: const Text('Settings')),
  body: ListView(children: [
    GlassGroupedSection(children: [
      GlassListTile(leading: const Icon(CupertinoIcons.wifi), title: const Text('Wi-Fi'), trailing: const Icon(CupertinoIcons.chevron_right), onTap: (){}),
      GlassDivider(),
      GlassListTile(leading: const Icon(CupertinoIcons.bluetooth), title: const Text('Bluetooth'), trailing: const Icon(CupertinoIcons.chevron_right), onTap: (){}),
    ]),
  ]),
)
```

行用 `GlassListTile`，分隔用 `GlassDivider`，整组用 `GlassGroupedSection` 圆角化。

---

## 6. 局部面板组合（GlassCard / GlassContainer）

适用于自定义布局里的悬浮面板（不依赖 Scaffold）。

```dart
Center(child: GlassCard(
  onTap: () {},
  child: Padding(padding: const EdgeInsets.all(20), child: Column(/* ... */)),
))
```

`GlassContainer` 仅用于自定义 layout；不要用它再包其他玻璃控件。

---

## 7. 多玻璃共享参数：AdaptiveLiquidGlassLayer

把一组玻璃元素限定在一个矩形 region 内共享 quality/blur/thickness，避免每张卡单独算 GPU。

```dart
AdaptiveLiquidGlassLayer(
  quality: GlassQuality.minimal,
  child: Column(children: [GlassCard(child: ...), GlassCard(child: ...), GlassCard(child: ...)]),
)
```

---

## 8. 模态层组合：GlassModalSheet 三态

peek / half / full 可拖拽切换 — Apple Music / Apple News 都用。

```dart
showGlassModalSheet(
  context,
  builder: (ctx) => GlassModalSheet(
    initialState: GlassSheetState.half,
    minHeight: 120,
    maxHeight: 600,
    peekHeight: 120,
    builder: (state, scrollController) => MyContent(state, scrollController),
  ),
);
```

`initialState: GlassSheetState.peek` 让 sheet 一开始只露一条边；`builder` 拿到 `state` 让内容响应 peek/half/full 切换。

---

## 9. 上下文菜单：GlassMenu（液态 morph + 9 方位）

招牌特效：菜单从锚点像泪滴一样 open/close，第一个消费 Liquid Morph Engine 的控件。

```dart
final _menu = GlassMenuController();

GestureDetector(onLongPress: () => _menu.openAt(rect), child: MyItem())

// 树中：
GlassMenu(
  controller: _menu,
  alignment: GlassMenuAlignment.autoStart,
  children: [
    GlassMenuItem(icon: const Icon(CupertinoIcons.heart), label: 'Like', onTap: (){}),
    GlassMenuItem(icon: const Icon(CupertinoIcons.bookmark), label: 'Save'),
    GlassMenuDivider(),
    GlassMenuLabel(label: 'More'),
    GlassMenuItem(icon: const Icon(CupertinoIcons.share), label: 'Share', destructive: true),
  ],
);
```

**9 种 alignment**：`autoStart / autoEnd / autoCenter` + `topStart / topEnd / topCenter` + `bottomStart / bottomEnd / bottomCenter`。`auto*` 自动避开屏幕边。

controller 必须在 `State` 里持有并在 `dispose` 关闭。

---

## 10. Action Sheet 组合

```dart
showGlassActionSheet(context,
  title: 'Choose',
  message: 'Pick one',
  actions: [
    GlassActionSheetAction(label: 'Share', onPressed: (){}),
    GlassActionSheetAction(label: 'Delete', isDestructive: true),
  ],
  cancelAction: GlassActionSheetAction(label: 'Cancel'),
);
```

---

## 11. Dialog 组合

```dart
showGlassDialog(context,
  title: const Text('Delete?'),
  content: const Text('Cannot be undone.'),
  actions: [
    GlassDialogAction(label: 'Cancel'),
    GlassDialogAction(label: 'Delete', isDestructive: true, onPressed: (){}),
  ],
);
```

---

## 12. Popover 组合

点击目标 widget 旁弹出小窗。

```dart
showGlassPopover(context,
  anchorKey: myAnchorKey,
  alignment: GlassMenuAlignment.autoStart,
  builder: (ctx) => Padding(padding: const EdgeInsets.all(12), child: const Text('Hi')),
);
```

---

## 13. 表单/控件组合（Settings 表单面板）

```dart
GlassGroupedSection(children: [
  GlassFormField(child: GlassTextField(controller: _email, hint: 'Email')),
  GlassDivider(),
  GlassFormField(child: GlassPasswordField(controller: _pwd, hint: 'Password')),
  GlassDivider(),
  GlassFormField(child: GlassPicker<String>(
    value: _currency, options: const ['USD','EUR','CNY'],
    onChanged: (v) => setState(() => _currency = v),
    decoration: const InputDecoration(labelText: 'Currency'),
  )),
])
```

搜索单独使用：`GlassSearchBar` 放在屏幕任何位置（不依赖 tab bar）。

---

## 14. 反馈组合：Toast + ProgressIndicator

```dart
GlassToast.show(context, message: 'Saved',
  action: GlassToastAction(label: 'Undo', onPressed: (){}));

const Center(child: GlassProgressIndicator.circular());

GlassProgressIndicator.determinate(value: 0.6);
```

---

## 15. Magic-lens Masking（GlassBottomBar 特有）

`GlassBottomBar` 的选中 pill 不是简单覆盖，而是 **圆形遮罩后退 8px 形成透镜感**。

```dart
GlassBottomBar(
  selectedIndex: _i,
  onTabSelected: (i) => setState(() => _i = i),
  tabWidth: 72,
  centerSlot: Center(child: GlassButton(icon: const Icon(CupertinoIcons.add), onTap: (){}, shape: GlassButtonShape.circle)),
  tabs: const [/* GlassBottomBarTab(...) */],
)
```

调整 `tabWidth` 可看到 lens 强度变化（`bottom_bar_tab_width_demo.dart`）。

---

## 16. 折射源组合：让玻璃真的"看到"背景

Skia / Web 上需要显式告诉玻璃背后那张壁纸就是采样源。Impeller（iOS / Android / macOS）自动无需。

**推荐：`GlassPage` 自动配**

```dart
GlassPage(
  background: Image.asset('assets/wallpaper.jpg', fit: BoxFit.cover),
  child: Scaffold(body: Center(child: GlassSegmentedControl(/*...*/))),
)
```

**手动版（多区域 / 嵌套）：**

```dart
LiquidGlassScope.stack(
  background: Image.asset('assets/wallpaper.jpg', fit: BoxFit.cover),
  content: Scaffold(body: Center(child: GlassSegmentedControl(/*...*/))),
)
```

---

## 17. 陀螺仪高光组合（Apple Music 全屏壁纸体验）

任何 `Stream<double>` 驱动高光角度，配合 `sensors_plus` 实现手机倾斜高光跟随。

```dart
GlassMotionScope(
  stream: gyroscopeEvents.map((e) => e.y * 0.5),
  child: Scaffold(/*...*/),
)
```

无需新依赖；任何流（鼠标位置、scroll offset）都行。

---

## 18. 性能与自适应组合

```dart
LiquidGlassWidgets.wrap(
  child: const MyApp(),
  adaptiveQuality: true,                 // 启动时 benchmark，自动降到 minimal / standard
)
```

**Quality 选型心法：**

| 场景 | 用 |
|---|---|
| 列表 / 滚动 | `standard`（默认） |
| 静态 hero / app bar / bottom bar | `premium`（`GlassScaffold` 自动提升） |
| 大量玻璃卡 / 低端机 | `minimal`（零 shader 开销） |

---

## 19. 主题与多级覆盖

```dart
runApp(LiquidGlassWidgets.wrap(
  child: const MyApp(),
  theme: GlassThemeData.simple(blur: 10, thickness: 30, quality: GlassQuality.standard),
));
```

**三级覆盖（高 → 低）：**

1. Widget 自带 `settings:`
2. `GlassPage(themeOverride: ...)`（单屏）
3. `wrap(theme: ...)`（全局）

**局部子树换主题：**

```dart
GlassTheme(
  data: GlassThemeData.simple(quality: GlassQuality.minimal),
  child: MyBackgroundPanel(),
)
```

---

## 20. 完整 showcase 复刻

| Demo | 招牌特效 | 运行 |
|---|---|---|
| **Apple Music** | `GlassTabBar.searchable()` + 浮窗播放 pill + 全屏 morph | `flutter run -t lib/apple_music/apple_music_demo.dart` |
| **Apple Messages** | `GlassMenu` 泪滴 open/close | `flutter run -t lib/apple_messages/apple_messages_demo.dart` |
| **Apple News** | `GlassTabBar.searchable` + morph 搜索胶囊 + 分类 chips + hero cards | `flutter run -t lib/apple_news/apple_news_demo.dart` |
| **Wanderlust** | 完整 app：parallax + hero transitions + chat | `cd example/showcase && flutter run` |
| **Widget Showcase** | 全组件目录 | `cd example && flutter run` |

---

## 21. 单组件聚焦 demo（拿来即用）

```
flutter run -t lib/demos/glass_menu_demo.dart                  # 9 方位菜单
flutter run -t lib/demos/glass_modal_sheet_demo.dart           # peek/half/full
flutter run -t lib/demos/glass_bottom_bar_demo.dart            # magic-lens
flutter run -t lib/demos/bottom_bar_tab_width_demo.dart        # tabWidth 调整
flutter run -t lib/demos/glass_tab_bar_scrollable_demo.dart    # 滚动 tab
flutter run -t lib/demos/searchable_bar_demo.dart              # 搜索边缘
flutter run -t lib/demos/shape_debug_demo.dart                 # 按钮形状
flutter run -t lib/demos/quality_comparison_demo.dart          # quality 对比
flutter run -t lib/demos/nav_bar_patterns_demo.dart            # GlassScaffold 模式
flutter run -t lib/demos/content_aware_brightness_demo.dart    # 亮度切换
flutter run -t lib/demos/indicator_parity_demo.dart            # 4 种 pill
flutter run -t lib/demos/buttons_and_shadows_demo.dart
flutter run -t lib/demos/text_field_demo.dart
flutter run -t lib/demos/google_maps_demo.dart
flutter run -t lib/demos/video_player_demo.dart
flutter run -t lib/demos/stretch_test_demo.dart
flutter run -t lib/demos/scaffold_menu_regression_demo.dart
```

---

## 22. 易错点速查

1. **玻璃套玻璃** — `GlassCard` 不要被另一个玻璃控件包（自动 `avoidsRefraction`）。
2. **`premium` 在 `ListView` 里** — 用 `standard`；premium 只用于静态表面。
3. **没有 `GlassScaffold` 就要 `GlassPage`** — 否则玻璃变平 / 不可见。
4. **不调 `initialize()`** — 首帧白闪。
5. **`setState` 必加** — `onTabSelected` / `onChanged` / `onValueChanged` 不 setState 不刷新。
6. **`GlassMenu` controller 必须持有** — 在 `State` 里 new + dispose 关掉。
7. **Reduce Transparency** — 全自动，无需配置；测试用 `GlassAccessibilityScope` 强制。
8. **`morphDuration`** — `GlassTabBar.searchable` 用它控制搜索 morph 时长。
9. **`AdaptiveLiquidGlassLayer`** — 多张卡共享 quality/blur，节省 GPU。
10. **Widget `settings` > 主题** — 想让单个 widget 突破主题，直接 `settings:`。
