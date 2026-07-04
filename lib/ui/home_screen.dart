import 'dart:io';
import 'dart:math' as math;
import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anivault/services/app_i18n.dart';
import 'package:anivault/services/anime_library_service.dart';
import 'package:anivault/services/logger_service.dart';
import 'package:anivault/services/theme_service.dart';
import 'package:anivault/services/torrent_service.dart';
import 'package:anivault/ui/ani_glass_theme.dart';
import 'package:anivault/ui/anime_series_screen.dart';
import 'package:anivault/ui/bt_downloads_view.dart';
import 'package:anivault/ui/page_transition.dart';
import 'package:anivault/ui/settings_screen.dart';
import 'package:anivault/services/watch_history_service.dart';
import 'package:anivault/ui/homepage_view.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  static const _mediaPickerChannel = MethodChannel('anivault/media_picker');

  final _homeScrollController = ScrollController();
  final _libraryScrollController = ScrollController();
  final _downloadScrollController = ScrollController();
  final _settingsScrollController = ScrollController();
  final _searchController = TextEditingController();

  List<String> _mediaPaths = [];
  List<AnimeSeries> _animeSeries = [];
  bool _isSyncing = false;
  bool _isScraping = false;
  int _sectionIndex = 0;
  bool _filterSearchActive = false;
  String _filter = 'All';
  String _query = '';
  final Set<String> _selectedSeriesIds = {};
  String? _sessionBackgroundCoverUrl;
  Timer? _syncTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WatchHistoryService().initialize();
    AnimeLibraryService().addListener(_onLibraryChanged);
    WatchHistoryService().addListener(_onHistoryChanged);
    AppI18n().addListener(_onLanguageChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final delay =
          defaultTargetPlatform == TargetPlatform.iOS ||
              defaultTargetPlatform == TargetPlatform.android
          ? const Duration(milliseconds: 1800)
          : const Duration(milliseconds: 450);
      _syncTimer = Timer(delay, () {
        if (mounted) unawaited(_syncMedia());
      });
    });
  }

  void _onLibraryChanged() {
    if (!mounted) return;
    setState(() {
      _animeSeries = AnimeLibraryService().series;
      _chooseSessionBackgroundCover();
      _selectedSeriesIds.removeWhere(
        (id) => !_animeSeries.any((series) => series.id == id),
      );
    });
  }

  void _onHistoryChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    AnimeLibraryService().removeListener(_onLibraryChanged);
    WatchHistoryService().removeListener(_onHistoryChanged);
    AppI18n().removeListener(_onLanguageChanged);
    WidgetsBinding.instance.removeObserver(this);
    _syncTimer?.cancel();
    _homeScrollController.dispose();
    _libraryScrollController.dispose();
    _downloadScrollController.dispose();
    _settingsScrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didHaveMemoryPressure() {
    LoggerService().log('[Perf] Memory pressure reported');
  }

  void _onLanguageChanged() {
    if (!mounted || _mediaPaths.isEmpty) return;
    unawaited(_refreshAnimeLibrary(_mediaPaths));
  }

  Future<void> _syncMedia() async {
    if (_isSyncing) return;
    final totalWatch = Stopwatch()..start();
    final showBusy = _sectionIndex != 0;
    _isSyncing = true;
    if (showBusy) setState(() {});
    try {
      final prefs = await SharedPreferences.getInstance();
      final knownPaths = _uniqueResolvedPaths(
        prefs.getStringList('media_library') ?? const [],
      );
      knownPaths.removeWhere((path) => !File(path).existsSync());
      final knownKeys = knownPaths.map(PathResolver.canonicalKey).toSet();
      if (knownPaths.isNotEmpty) {
        if (mounted) setState(() => _mediaPaths = knownPaths);
        final refreshWatch = Stopwatch()..start();
        await _refreshAnimeLibrary(knownPaths);
        LoggerService().log(
          '[Perf] Initial library refresh: ${knownPaths.length} files in ${refreshWatch.elapsedMilliseconds}ms',
        );
      }

      final scanWatch = Stopwatch()..start();
      final docDir = await getApplicationDocumentsDirectory();
      final validExtensions = ['.mp4', '.mkv', '.avi', '.mov', '.webm'];
      final discoveredPaths = <String>[];
      final activeBtPaths = _activeIncompleteBtPaths();

      await for (final entity in _safeWalk(docDir)) {
        if (entity is! File) {
          continue;
        }
        final path = entity.path;
        final resolvedPath = PathResolver.resolve(path);
        final key = PathResolver.canonicalKey(resolvedPath);
        final isVideo = validExtensions.any(path.toLowerCase().endsWith);
        if (isVideo &&
            !knownKeys.contains(key) &&
            !activeBtPaths.contains(key)) {
          discoveredPaths.add(resolvedPath);
          knownKeys.add(key);
        }
      }

      // Also scan Windows download directories (relative to executable) if on Windows
      if (Platform.isWindows) {
        final exeDir = File(Platform.resolvedExecutable).parent.path;
        final winDownloadDirs = [
          Directory(p.join(exeDir, 'download')),
          Directory(p.join(exeDir, 'downloads')),
        ];
        for (final winDownloadDir in winDownloadDirs) {
          if (!await winDownloadDir.exists()) {
            continue;
          }
          await for (final entity in _safeWalk(winDownloadDir)) {
            if (entity is! File) {
              continue;
            }
            final path = entity.path;
            final resolvedPath = PathResolver.resolve(path);
            final key = PathResolver.canonicalKey(resolvedPath);
            final isVideo = validExtensions.any(path.toLowerCase().endsWith);
            if (isVideo &&
                !knownKeys.contains(key) &&
                !activeBtPaths.contains(key)) {
              discoveredPaths.add(resolvedPath);
              knownKeys.add(key);
            }
          }
        }
      }

      final mergedPaths = _uniqueResolvedPaths([
        ...discoveredPaths,
        ...knownPaths,
      ]);
      LoggerService().log(
        '[Perf] Media scan: known=${knownPaths.length}, discovered=${discoveredPaths.length}, merged=${mergedPaths.length}, scan=${scanWatch.elapsedMilliseconds}ms',
      );
      if (discoveredPaths.isNotEmpty ||
          mergedPaths.length != knownPaths.length) {
        if (!mounted) return;
        setState(() => _mediaPaths = mergedPaths);
        await prefs.setStringList('media_library', mergedPaths);
        final refreshWatch = Stopwatch()..start();
        await _refreshAnimeLibrary(mergedPaths);
        LoggerService().log(
          '[Perf] Full library refresh: ${mergedPaths.length} files in ${refreshWatch.elapsedMilliseconds}ms',
        );
      } else {
        await prefs.setStringList('media_library', knownPaths);
      }
    } catch (e) {
      LoggerService().log('[Library Error] Sync failed: $e');
    } finally {
      LoggerService().log(
        '[Perf] Media sync total: ${totalWatch.elapsedMilliseconds}ms',
      );
      _isSyncing = false;
      if (mounted && showBusy) setState(() {});
    }
  }

  Set<String> _activeIncompleteBtPaths() {
    return {
      for (final task in TorrentService().tasks)
        if (!task.complete)
          for (final file in task.files)
            if (_isVideoFilePath(file.path))
              PathResolver.canonicalKey(file.path),
    };
  }

  List<String> _uniqueResolvedPaths(Iterable<String> paths) {
    final seen = <String>{};
    final result = <String>[];
    for (final path in paths) {
      final resolved = PathResolver.resolve(path);
      final key = PathResolver.canonicalKey(resolved);
      if (seen.add(key)) result.add(resolved);
    }
    return result;
  }

  bool _isVideoFilePath(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.mp4') ||
        lower.endsWith('.mkv') ||
        lower.endsWith('.avi') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.webm');
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
        resolveAmbiguousMatch: _chooseAniListMatch,
      );
      if (!mounted) return;
      setState(() {
        _animeSeries = AnimeLibraryService().series;
        _chooseSessionBackgroundCover();
      });
      _selectedSeriesIds.removeWhere(
        (id) => !_animeSeries.any((series) => series.id == id),
      );
    } catch (e) {
      LoggerService().log('[Library Error] Metadata refresh failed: $e');
    } finally {
      if (mounted) setState(() => _isScraping = false);
    }
  }

  void _chooseSessionBackgroundCover() {
    if (_sessionBackgroundCoverUrl != null) return;
    final covers = _animeSeries
        .map((series) => series.coverUrl)
        .whereType<String>()
        .where((url) => url.trim().isNotEmpty)
        .toList();
    if (covers.isEmpty) return;
    _sessionBackgroundCoverUrl = covers[math.Random().nextInt(covers.length)];
  }

  Future<AniListSearchResult?> _chooseAniListMatch(
    String parsedTitle,
    List<AniListSearchResult> candidates,
  ) async {
    if (!mounted) return null;
    AniListSearchResult? selected;
    await showGlassActionSheet<void>(
      context: context,
      title: 'Choose anime',
      message: parsedTitle,
      quality: AniGlassTheme.quality,
      settings: AniGlassTheme.chromeFor(context),
      actions: [
        for (final candidate in candidates)
          GlassActionSheetAction(
            label: _candidateLabel(candidate),
            icon: const Icon(Icons.movie_filter_rounded),
            onPressed: () => selected = candidate,
          ),
        GlassActionSheetAction(
          label: 'Keep as unknown',
          icon: const Icon(Icons.help_outline_rounded),
          style: GlassActionSheetStyle.destructive,
          onPressed: () => selected = null,
        ),
      ],
      cancelLabel: 'Skip',
    );
    return selected;
  }

  String _candidateLabel(AniListSearchResult candidate) {
    final meta = [
      if (candidate.startYear != null) '${candidate.startYear}',
      if (candidate.episodes != null) '${candidate.episodes} eps',
    ].join(' 路 ');
    return meta.isEmpty
        ? candidate.displayTitle
        : '${candidate.displayTitle}  ($meta)';
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

  bool get _selectionMode => _selectedSeriesIds.isNotEmpty;

  List<String> _pathsForSeries(AnimeSeries series) {
    return [
      for (final episode in series.episodes)
        for (final file in episode.files) file.path,
    ];
  }

  Future<void> _removeSeriesFromLibrary(List<AnimeSeries> seriesList) async {
    if (seriesList.isEmpty) return;
    final removePaths = seriesList.expand(_pathsForSeries).toSet();
    final nextPaths = _mediaPaths
        .where((path) => !removePaths.contains(path))
        .toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('media_library', nextPaths);
    if (!mounted) return;
    setState(() {
      _mediaPaths = nextPaths;
      for (final series in seriesList) {
        _selectedSeriesIds.remove(series.id);
      }
    });
    await _refreshAnimeLibrary(nextPaths);
  }

  Future<void> _removeSelectedSeries() async {
    final selected = _animeSeries
        .where((series) => _selectedSeriesIds.contains(series.id))
        .toList();
    await _removeSeriesFromLibrary(selected);
  }

  void _toggleSeriesSelection(AnimeSeries series) {
    setState(() {
      if (!_selectedSeriesIds.add(series.id)) {
        _selectedSeriesIds.remove(series.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final busy = _isSyncing || _isScraping;
    final visible = _visibleSeries;
    final topPadding = MediaQuery.paddingOf(context).top + 14;
    final light = Theme.of(context).brightness == Brightness.light;
    final backgroundStyle = ThemeService().backgroundStyle;

    _chooseSessionBackgroundCover();
    final coverUrl = _sessionBackgroundCoverUrl;

    return GlassScaffold(
      background: AniGlassTheme.background(
        coverUrl: coverUrl,
        light: light,
        style: backgroundStyle,
      ),
      statusBarStyle: light
          ? GlassStatusBarStyle.dark
          : GlassStatusBarStyle.light,
      settings: AniGlassTheme.chromeFor(context),
      topEdgeFade: true,
      bottomEdgeFade: true,
      headerScrollController: _sectionIndex == 0
          ? _homeScrollController
          : _sectionIndex == 1
          ? _libraryScrollController
          : _sectionIndex == 2
          ? _downloadScrollController
          : _settingsScrollController,
      headerFadeDistance: 46,
      body: Stack(
        children: [
          KeyedSubtree(
            key: ValueKey('section-$_sectionIndex'),
            child: _sectionIndex == 0
                ? HomepageView(
                    topPadding: topPadding,
                    scrollController: _homeScrollController,
                    onNavigateToLibrary: (index) =>
                        setState(() => _sectionIndex = index),
                  )
                : _sectionIndex == 1
                ? _buildLibraryView(
                    busy: busy,
                    visible: visible,
                    topPadding: topPadding,
                  )
                : _sectionIndex == 2
                ? BtDownloadsView(
                    topPadding: topPadding + 74,
                    scrollController: _downloadScrollController,
                    onLibraryRefresh: _syncMedia,
                  )
                : SettingsContent(
                    topPadding: topPadding + 74,
                    scrollController: _settingsScrollController,
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
              tabWidth: 86,
              tabs: const [
                GlassTab(label: 'Home'),
                GlassTab(label: 'Library'),
                GlassTab(label: 'Download'),
                GlassTab(label: 'Settings'),
              ],
            ),
          ),
          if (_sectionIndex == 1)
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
          if (_sectionIndex == 1 && _selectionMode)
            Positioned(
              left: 20,
              right: 20,
              bottom: MediaQuery.paddingOf(context).bottom + 84,
              child: _SelectionDeleteBar(
                count: _selectedSeriesIds.length,
                onCancel: () => setState(_selectedSeriesIds.clear),
                onDelete: _removeSelectedSeries,
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
      controller: _libraryScrollController,
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
          const SliverToBoxAdapter(child: SizedBox.shrink())
        else if (visible.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 110),
              child: Center(
                child: Text(
                  'No matching series',
                  style: TextStyle(
                    color: AniGlassTheme.secondaryTextColor(context),
                  ),
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
                    selected: _selectedSeriesIds.contains(series.id),
                    selectionMode: _selectionMode,
                    onTap: () {
                      if (_selectionMode) {
                        _toggleSeriesSelection(series);
                        return;
                      }
                      Navigator.of(context).push(
                        AniScalePageRoute(
                          page: AnimeSeriesScreen(
                            series: series,
                            onDeleteSeries: _removeSeriesFromLibrary,
                          ),
                        ),
                      );
                    },
                    onSelect: () => _toggleSeriesSelection(series),
                    onDelete: () => _removeSeriesFromLibrary([series]),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _SelectionDeleteBar extends StatelessWidget {
  final int count;
  final VoidCallback onCancel;
  final VoidCallback onDelete;

  const _SelectionDeleteBar({
    required this.count,
    required this.onCancel,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = AniGlassTheme.textColor(context);
    final secondary = AniGlassTheme.secondaryTextColor(context);
    return Align(
      alignment: Alignment.center,
      child: GlassButton.custom(
        quality: AniGlassTheme.quality,
        settings: AniGlassTheme.chromeFor(context),
        shape: const LiquidRoundedSuperellipse(borderRadius: 18),
        height: 56,
        onTap: () {},
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '$count selected',
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              GlassButton(
                quality: AniGlassTheme.quality,
                settings: AniGlassTheme.chromeFor(context),
                width: 38,
                height: 38,
                icon: Icon(Icons.close_rounded, color: secondary),
                onTap: onCancel,
              ),
              const SizedBox(width: 8),
              GlassButton(
                quality: AniGlassTheme.quality,
                settings: AniGlassTheme.chromeFor(context),
                width: 38,
                height: 38,
                icon: const Icon(Icons.delete_outline_rounded),
                onTap: onDelete,
              ),
            ],
          ),
        ),
      ),
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
    final textColor = AniGlassTheme.textColor(context);
    final secondaryTextColor = AniGlassTheme.secondaryTextColor(context);
    return GlassCard(
      quality: AniGlassTheme.quality,
      useOwnLayer: false,
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
                    color: secondaryTextColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Library',
                  style: TextStyle(
                    color: textColor,
                    fontSize: 38,
                    fontWeight: FontWeight.w800,
                    height: 0.95,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  '$totalSeries series  -  $totalFiles files',
                  style: TextStyle(color: secondaryTextColor),
                ),
              ],
            ),
          ),
          GlassButton.custom(
            quality: AniGlassTheme.quality,
            settings: AniGlassTheme.chromeFor(context),
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
                  : Icon(
                      key: const ValueKey('import'),
                      Icons.add_rounded,
                      color: textColor,
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
    final textColor = AniGlassTheme.textColor(context);
    final tertiaryTextColor = AniGlassTheme.tertiaryTextColor(context);
    const horizontalPadding = 12.0;
    final barGlassSettings = LiquidGlassSettings(
      glassColor: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xAA1C1C1E)
          : const Color(0xDDEFF1F5),
      backerColor: Theme.of(context).brightness == Brightness.dark
          ? null
          : const Color(0xFFEFF1F5),
      platformViewFallbackColor: Theme.of(context).brightness == Brightness.dark
          ? null
          : const Color(0xFFEFF1F5),
      thickness: 30,
      blur: 2,
      shadowElevation: 2.0,
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
                minQuality: AniGlassTheme.quality,
                child: GlassTabBar.bottom(
                  selectedIndex: selectedIndex,
                  onTabSelected: onChanged,
                  selectedIconColor: textColor,
                  unselectedIconColor: tertiaryTextColor,
                  selectedLabelColor: textColor,
                  unselectedLabelColor: tertiaryTextColor,
                  indicatorColor: textColor.withValues(alpha: 0.14),
                  iconSize: 28,
                  iconLabelSpacing: 0,
                  quality: AniGlassTheme.quality,
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
    final textColor = AniGlassTheme.textColor(context);
    final secondaryTextColor = AniGlassTheme.secondaryTextColor(context);
    final tertiaryTextColor = AniGlassTheme.tertiaryTextColor(context);
    final barGlassSettings = LiquidGlassSettings(
      glassColor: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xAA1C1C1E)
          : const Color(0xDDEFF1F5),
      backerColor: Theme.of(context).brightness == Brightness.dark
          ? null
          : const Color(0xFFEFF1F5),
      platformViewFallbackColor: Theme.of(context).brightness == Brightness.dark
          ? null
          : const Color(0xFFEFF1F5),
      thickness: 30,
      blur: 2,
      shadowElevation: 2.0,
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
              minQuality: AniGlassTheme.quality,
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
                selectedIconColor: textColor,
                unselectedIconColor: tertiaryTextColor,
                selectedLabelColor: textColor,
                unselectedLabelColor: tertiaryTextColor,
                indicatorColor: textColor.withValues(alpha: 0.14),
                labelFontSize: 10,
                iconSize: 22,
                iconLabelSpacing: 1,
                quality: AniGlassTheme.quality,
                interactionBehavior: GlassInteractionBehavior.full,
                settings: barGlassSettings,
                searchConfig: GlassSearchBarConfig(
                  controller: searchController,
                  hintText: 'Search library',
                  showsCancelButton: true,
                  autoFocusOnExpand: false,
                  searchIconColor: secondaryTextColor,
                  textColor: textColor,
                  hintStyle: TextStyle(color: tertiaryTextColor),
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

class _EmptyLibrary extends StatelessWidget {
  final VoidCallback onImport;

  const _EmptyLibrary({required this.onImport});

  @override
  Widget build(BuildContext context) {
    final textColor = AniGlassTheme.textColor(context);
    final secondaryTextColor = AniGlassTheme.secondaryTextColor(context);
    final tertiaryTextColor = AniGlassTheme.tertiaryTextColor(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.video_library_outlined,
            color: tertiaryTextColor,
            size: 58,
          ),
          const SizedBox(height: 16),
          Text(
            'No media imported',
            style: TextStyle(
              color: textColor,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Add local videos to build the library.',
            style: TextStyle(color: secondaryTextColor),
          ),
          const SizedBox(height: 18),
          GlassButton.custom(
            quality: AniGlassTheme.quality,
            settings: AniGlassTheme.chromeFor(context),
            shape: const LiquidRoundedSuperellipse(borderRadius: 16),
            onTap: onImport,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_rounded, color: textColor),
                  const SizedBox(width: 8),
                  Text('Import videos', style: TextStyle(color: textColor)),
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
  final VoidCallback onSelect;
  final VoidCallback onDelete;
  final bool selected;
  final bool selectionMode;

  const _AnimeSeriesCard({
    required this.series,
    required this.onTap,
    required this.onSelect,
    required this.onDelete,
    required this.selected,
    required this.selectionMode,
  });

  @override
  Widget build(BuildContext context) {
    return GlassMenu(
      settings: AniGlassTheme.chromeFor(context),
      quality: AniGlassTheme.quality,
      menuWidth: 220,
      items: [
        GlassMenuItem(
          title: selected ? 'Deselect' : 'Select',
          icon: Icon(
            selected
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
          ),
          onTap: onSelect,
        ),
        GlassMenuItem(
          title: 'Delete',
          icon: const Icon(Icons.delete_outline_rounded),
          isDestructive: true,
          onTap: onDelete,
        ),
      ],
      triggerBuilder: (context, toggle) {
        return GestureDetector(
          onLongPress: toggle,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: _AnimeSeriesCardSurface(
              series: series,
              selected: selected,
              selectionMode: selectionMode,
            ),
          ),
        );
      },
    );
  }
}

class _AnimeSeriesCardSurface extends StatelessWidget {
  final AnimeSeries series;
  final bool selected;
  final bool selectionMode;

  const _AnimeSeriesCardSurface({
    required this.series,
    required this.selected,
    required this.selectionMode,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected
              ? Colors.lightBlueAccent.withValues(alpha: 0.78)
              : Colors.white.withValues(alpha: 0.10),
          width: selected ? 2 : 1,
        ),
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
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (series.isUnknown)
              Positioned(
                top: 10,
                right: 10,
                child: _UnknownBadge(
                  label: series.isResolving ? 'Resolving' : 'Unknown',
                ),
              ),
            if (selectionMode)
              Positioned(
                top: 10,
                left: 10,
                child: Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: selected ? Colors.lightBlueAccent : Colors.white70,
                  size: 26,
                ),
              ),
          ],
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
        cacheWidth: 420,
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
