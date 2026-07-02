import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anivault/services/anime_library_service.dart';
import 'package:anivault/services/logger_service.dart';
import 'package:anivault/services/theme_service.dart';
import 'package:anivault/ui/ani_glass_theme.dart';
import 'package:anivault/ui/anime_series_screen.dart';
import 'package:anivault/ui/settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _mediaPickerChannel = MethodChannel('anivault/media_picker');

  final _scrollController = ScrollController();
  final _searchController = TextEditingController();

  List<String> _mediaPaths = [];
  List<AnimeSeries> _animeSeries = [];
  bool _isSyncing = false;
  bool _isScraping = false;
  int _sectionIndex = 0;
  bool _filterSearchActive = false;
  String _filter = 'All';
  String _query = '';

  @override
  void initState() {
    super.initState();
    _syncMedia();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _syncMedia() async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final knownPaths = prefs.getStringList('media_library') ?? [];
      final docDir = await getApplicationDocumentsDirectory();
      final validExtensions = ['.mp4', '.mkv', '.avi', '.mov', '.webm'];
      final discoveredPaths = <String>[];

      await for (final entity in _safeWalk(docDir)) {
        if (entity is! File) {
          continue;
        }
        final path = entity.path;
        final isVideo = validExtensions.any(path.toLowerCase().endsWith);
        if (isVideo && !knownPaths.contains(path)) {
          discoveredPaths.add(path);
        }
      }

      knownPaths.removeWhere((path) => !File(path).existsSync());
      final mergedPaths = [...discoveredPaths, ...knownPaths];
      if (!mounted) return;
      setState(() => _mediaPaths = mergedPaths);
      await prefs.setStringList('media_library', mergedPaths);
      await _refreshAnimeLibrary(mergedPaths);
    } catch (e) {
      LoggerService().log('[Library Error] Sync failed: $e');
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Stream<FileSystemEntity> _safeWalk(Directory root) async* {
    Stream<FileSystemEntity> children;
    try {
      children = root.list(followLinks: false);
    } on FileSystemException catch (e) {
      LoggerService().log(
        '[Library] Skip inaccessible directory: ${root.path} ($e)',
      );
      return;
    }

    try {
      await for (final entity in children) {
        if (entity is Directory) {
          yield* _safeWalk(entity);
        } else {
          yield entity;
        }
      }
    } on FileSystemException catch (e) {
      LoggerService().log(
        '[Library] Skip inaccessible directory: ${root.path} ($e)',
      );
    }
  }

  Future<void> _importVideo() async {
    try {
      final importedPaths = Platform.isAndroid
          ? await _importAndroidVideos()
          : await _pickDesktopVideos();

      if (importedPaths.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        setState(() {
          for (final path in importedPaths) {
            if (!_mediaPaths.contains(path)) _mediaPaths.insert(0, path);
          }
        });
        await prefs.setStringList('media_library', _mediaPaths);
      }
    } catch (e) {
      LoggerService().log('[Library Error] Import failed: $e');
    }
    await _syncMedia();
  }

  Future<List<String>> _pickDesktopVideos() async {
    const typeGroup = XTypeGroup(
      label: 'Videos',
      extensions: ['mkv', 'mp4', 'avi', 'mov', 'webm'],
    );
    final files = await openFiles(acceptedTypeGroups: [typeGroup]);
    return files
        .map((file) => file.path)
        .where((path) => path.isNotEmpty)
        .toList();
  }

  Future<List<String>> _importAndroidVideos() async {
    final result = await _mediaPickerChannel.invokeListMethod<String>(
      'pickVideos',
    );
    return result ?? const [];
  }

  Future<void> _refreshAnimeLibrary([List<String>? paths]) async {
    final sourcePaths = paths ?? _mediaPaths;
    if (!mounted || sourcePaths.isEmpty) {
      if (mounted) setState(() => _animeSeries = []);
      return;
    }

    setState(() => _isScraping = true);
    try {
      final language =
          Localizations.maybeLocaleOf(context)?.languageCode ??
          Platform.localeName.split('_').first;
      await AnimeLibraryService().refreshLibrary(
        sourcePaths,
        languageCode: language,
      );
      if (!mounted) return;
      setState(() => _animeSeries = AnimeLibraryService().series);
    } catch (e) {
      LoggerService().log('[Library Error] Metadata refresh failed: $e');
    } finally {
      if (mounted) setState(() => _isScraping = false);
    }
  }

  List<AnimeSeries> get _visibleSeries {
    final query = _query.trim().toLowerCase();
    return _animeSeries.where((series) {
      final matchesQuery =
          query.isEmpty ||
          series.title.toLowerCase().contains(query) ||
          series.sortTitle.toLowerCase().contains(query);
      final matchesFilter = switch (_filter) {
        'Matched' => !series.isUnknown,
        'Unknown' => series.isUnknown,
        'Multi-file' => series.fileCount > series.episodes.length,
        _ => true,
      };
      return matchesQuery && matchesFilter;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final busy = _isSyncing || _isScraping;
    final visible = _visibleSeries;
    final topPadding = MediaQuery.paddingOf(context).top + 14;
    final light = Theme.of(context).brightness == Brightness.light;
    final backgroundStyle = ThemeService().backgroundStyle;

    return GlassScaffold(
      background: AniGlassTheme.background(
        coverUrl: _animeSeries.isNotEmpty ? _animeSeries.first.coverUrl : null,
        light: light,
        style: backgroundStyle,
      ),
      statusBarStyle: light
          ? GlassStatusBarStyle.dark
          : GlassStatusBarStyle.light,
      settings: AniGlassTheme.chrome,
      topEdgeFade: true,
      bottomEdgeFade: true,
      headerScrollController: _scrollController,
      headerFadeDistance: 46,
      body: Stack(
        children: [
          _PageSwitchTransition(
            selectedIndex: _sectionIndex,
            child: _sectionIndex == 0
                ? _buildLibraryView(
                    key: const ValueKey('library-page'),
                    busy: busy,
                    visible: visible,
                    topPadding: topPadding,
                  )
                : SettingsContent(
                    key: const ValueKey('settings-page'),
                    topPadding: topPadding + 96,
                    onLibraryRefresh: _refreshAnimeLibrary,
                  ),
          ),
          Positioned(
            top: topPadding,
            left: 0,
            right: 0,
            child: _DemoTopGlassTabBar(
              selectedIndex: _sectionIndex,
              onChanged: (index) => setState(() => _sectionIndex = index),
              tabWidth: 92,
              tabs: const [
                GlassTab(label: 'Library'),
                GlassTab(label: 'Settings'),
              ],
            ),
          ),
          if (_sectionIndex == 0)
            Positioned(
              left: 0,
              right: 0,
              bottom: MediaQuery.paddingOf(context).bottom + 10,
              child: _FilterBar(
                selected: _filter,
                searchActive: _filterSearchActive,
                searchController: _searchController,
                onSearchActiveChanged: (active) =>
                    setState(() => _filterSearchActive = active),
                onSearchChanged: (value) => setState(() => _query = value),
                onSelected: (filter) => setState(() {
                  _filter = filter;
                  _filterSearchActive = false;
                }),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLibraryView({
    Key? key,
    required bool busy,
    required List<AnimeSeries> visible,
    required double topPadding,
  }) {
    return CustomScrollView(
      key: key,
      controller: _scrollController,
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, topPadding + 104, 20, 18),
            child: _HomeHero(
              totalSeries: _animeSeries.length,
              totalFiles: _mediaPaths.length,
              busy: busy,
              onImport: busy ? () {} : () => _importVideo(),
            ),
          ),
        ),
        if (_mediaPaths.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 110),
              child: _EmptyLibrary(onImport: () => _importVideo()),
            ),
          )
        else if (_isScraping && _animeSeries.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: EdgeInsets.only(bottom: 110),
              child: Center(child: CircularProgressIndicator()),
            ),
          )
        else if (visible.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: EdgeInsets.only(bottom: 110),
              child: Center(
                child: Text(
                  'No matching series',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 130),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 230,
                mainAxisExtent: 306,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
              ),
              itemCount: visible.length,
              itemBuilder: (context, index) {
                final series = visible[index];
                return AnimatedGlassEntrance(
                  index: index,
                  child: _AnimeSeriesCard(
                    series: series,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => AnimeSeriesScreen(series: series),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _HomeHero extends StatelessWidget {
  final int totalSeries;
  final int totalFiles;
  final bool busy;
  final VoidCallback onImport;

  const _HomeHero({
    required this.totalSeries,
    required this.totalFiles,
    required this.busy,
    required this.onImport,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      quality: GlassQuality.premium,
      useOwnLayer: true,
      settings: AniGlassTheme.hero,
      padding: const EdgeInsets.all(22),
      shape: const LiquidRoundedSuperellipse(borderRadius: 30),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your anime vault',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.62),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Library',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 38,
                    fontWeight: FontWeight.w800,
                    height: 0.95,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  '$totalSeries series  -  $totalFiles files',
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
          GlassButton.custom(
            quality: GlassQuality.premium,
            settings: AniGlassTheme.chrome,
            shape: const LiquidOval(),
            width: 54,
            height: 54,
            interactionScale: 1.08,
            stretch: 0.75,
            glowColor: const Color(0xFF38BDF8),
            glowOpacity: 0.45,
            glowBlurRadius: 18,
            onTap: onImport,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              child: busy
                  ? const SizedBox(
                      key: ValueKey('busy'),
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    )
                  : const Icon(
                      key: ValueKey('import'),
                      Icons.add_rounded,
                      color: Colors.white,
                      size: 30,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

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
    const horizontalPadding = 12.0;
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

    return SizedBox(
      height: 66,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final widthScale =
              1.0 + ((constraints.maxWidth - 420) / 900).clamp(0.0, 0.28);
          final effectiveTabWidth = tabWidth == null
              ? null
              : (tabWidth! * widthScale).clamp(tabWidth!, tabWidth! * 1.28);
          final preferredWidth = effectiveTabWidth == null
              ? double.infinity
              : effectiveTabWidth * tabs.length + horizontalPadding * 2;
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
                  iconSize: 28,
                  iconLabelSpacing: 0,
                  quality: GlassQuality.premium,
                  interactionBehavior: GlassInteractionBehavior.full,
                  settings: barGlassSettings,
                  tabWidth: effectiveTabWidth,
                  barHeight: 42,
                  horizontalPadding: horizontalPadding,
                  verticalPadding: 8,
                  spacing: 4,
                  labelFontSize: 18,
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

class _FilterBar extends StatelessWidget {
  static const filters = ['All', 'Matched', 'Unknown', 'Multi-file'];

  final String selected;
  final bool searchActive;
  final TextEditingController searchController;
  final ValueChanged<String> onSelected;
  final ValueChanged<bool> onSearchActiveChanged;
  final ValueChanged<String> onSearchChanged;

  const _FilterBar({
    required this.selected,
    required this.searchActive,
    required this.searchController,
    required this.onSelected,
    required this.onSearchActiveChanged,
    required this.onSearchChanged,
  });

  @override
  Widget build(BuildContext context) {
    final index = filters.indexOf(selected).clamp(0, filters.length - 1);
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final tabWidth = (constraints.maxWidth / 5.4).clamp(86.0, 120.0);
        final barWidth = (tabWidth * filters.length + 54 + 8 + 40).clamp(
          0.0,
          constraints.maxWidth,
        );
        return Align(
          alignment: Alignment.center,
          child: SizedBox(
            width: barWidth,
            height: 80,
            // ignore: experimental_member_use
            child: GlassAdaptiveScope(
              minQuality: GlassQuality.premium,
              child: GlassTabBar.searchable(
                selectedIndex: index,
                isSearchActive: searchActive,
                onTabSelected: (index) => onSelected(filters[index]),
                tabWidth: tabWidth,
                barHeight: 54,
                searchBarHeight: 54,
                horizontalPadding: 20,
                verticalPadding: 10,
                spacing: 8,
                selectedIconColor: Colors.white,
                unselectedIconColor: Colors.white60,
                selectedLabelColor: Colors.white,
                unselectedLabelColor: Colors.white60,
                indicatorColor: Colors.white.withValues(alpha: 0.20),
                labelFontSize: 10,
                iconSize: 22,
                iconLabelSpacing: 1,
                quality: GlassQuality.premium,
                interactionBehavior: GlassInteractionBehavior.full,
                settings: barGlassSettings,
                searchConfig: GlassSearchBarConfig(
                  controller: searchController,
                  hintText: 'Search library',
                  showsCancelButton: true,
                  autoFocusOnExpand: false,
                  searchIconColor: Colors.white70,
                  textColor: Colors.white,
                  hintStyle: const TextStyle(color: Colors.white54),
                  onChanged: onSearchChanged,
                  onSearchToggle: onSearchActiveChanged,
                ),
                tabs: const [
                  GlassTab(label: 'All', icon: Icon(Icons.apps_rounded)),
                  GlassTab(
                    label: 'Matched',
                    icon: Icon(Icons.verified_rounded),
                  ),
                  GlassTab(
                    label: 'Unknown',
                    icon: Icon(Icons.help_outline_rounded),
                  ),
                  GlassTab(
                    label: 'Multi-file',
                    icon: Icon(Icons.video_library_rounded),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PageSwitchTransition extends StatelessWidget {
  final int selectedIndex;
  final Widget child;

  const _PageSwitchTransition({
    required this.selectedIndex,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 240),
      reverseDuration: const Duration(milliseconds: 90),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeOutCubic,
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          fit: StackFit.expand,
          children: [...previousChildren, ?currentChild],
        );
      },
      transitionBuilder: (child, animation) {
        final isIncoming =
            child.key ==
            ValueKey(selectedIndex == 0 ? 'library-page' : 'settings-page');
        if (!isIncoming) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: const Interval(0, 0.24, curve: Curves.easeOutCubic),
            ),
            child: child,
          );
        }
        return FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: const Interval(0.18, 0.62, curve: Curves.easeOutCubic),
          ),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.97, end: 1).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  final VoidCallback onImport;

  const _EmptyLibrary({required this.onImport});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.video_library_outlined,
            color: Colors.white54,
            size: 58,
          ),
          const SizedBox(height: 16),
          const Text(
            'No media imported',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Add local videos to build the library.',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 18),
          GlassButton.custom(
            quality: GlassQuality.premium,
            settings: AniGlassTheme.chrome,
            shape: const LiquidRoundedSuperellipse(borderRadius: 16),
            onTap: onImport,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_rounded, color: Colors.white),
                  SizedBox(width: 8),
                  Text('Import videos', style: TextStyle(color: Colors.white)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnimeSeriesCard extends StatelessWidget {
  final AnimeSeries series;
  final VoidCallback onTap;

  const _AnimeSeriesCard({required this.series, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _SeriesCover(series: series),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0xEE050505)],
                  ),
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      series.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        height: 1.12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${series.episodes.length} episodes  -  ${series.fileCount} files',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (series.isUnknown)
                Positioned(
                  top: 10,
                  right: 10,
                  child: _UnknownBadge(label: 'Unknown'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UnknownBadge extends StatelessWidget {
  final String label;

  const _UnknownBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.34),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _SeriesCover extends StatelessWidget {
  final AnimeSeries series;

  const _SeriesCover({required this.series});

  @override
  Widget build(BuildContext context) {
    final coverUrl = series.coverUrl;
    if (coverUrl != null) {
      return Image.network(
        coverUrl,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            _CoverFallback(series: series),
      );
    }
    return _CoverFallback(series: series);
  }
}

class _CoverFallback extends StatelessWidget {
  final AnimeSeries series;

  const _CoverFallback({required this.series});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1F2937), Color(0xFF020617)],
        ),
      ),
      child: Center(
        child: Icon(
          series.isUnknown
              ? Icons.help_outline_rounded
              : Icons.movie_creation_outlined,
          color: Colors.white54,
          size: 46,
        ),
      ),
    );
  }
}
