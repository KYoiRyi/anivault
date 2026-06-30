import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'package:anivault/services/anime_library_service.dart';
import 'package:anivault/services/cache_manager_service.dart';
import 'package:anivault/services/smb_service.dart';
import 'package:anivault/ui/anime_series_screen.dart';
import 'package:anivault/ui/downloads_view.dart';
import 'package:anivault/ui/smb_viewer.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

enum HomeSection { library, network, downloads }

class _HomeScreenState extends State<HomeScreen> {
  static const _homeSectionKey = 'home_section';
  static const _mediaPickerChannel = MethodChannel('anivault/media_picker');

  List<String> _mediaPaths = [];
  bool _isSyncing = false;
  bool _isScraping = false;
  List<AnimeSeries> _animeSeries = [];
  HomeSection _currentSection = HomeSection.library;

  final _smbHostCtrl = TextEditingController();
  final _smbDomainCtrl = TextEditingController();
  final _smbUserCtrl = TextEditingController();
  final _smbPassCtrl = TextEditingController();
  final _anidbClientCtrl = TextEditingController();
  final _anidbClientVerCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSmbFields();
    _loadAniDbFields();
    _loadHomeSection();
    _syncMedia();
  }

  @override
  void dispose() {
    _smbHostCtrl.dispose();
    _smbDomainCtrl.dispose();
    _smbUserCtrl.dispose();
    _smbPassCtrl.dispose();
    _anidbClientCtrl.dispose();
    _anidbClientVerCtrl.dispose();
    super.dispose();
  }

  void _loadSmbFields() {
    _smbHostCtrl.text = SMBService().savedHost;
    _smbDomainCtrl.text = SMBService().savedDomain;
    _smbUserCtrl.text = SMBService().savedUser;
    _smbPassCtrl.text = SMBService().savedPass;
  }

  Future<void> _loadAniDbFields() async {
    final prefs = await SharedPreferences.getInstance();
    _anidbClientCtrl.text = prefs.getString('anidb_client') ?? '';
    _anidbClientVerCtrl.text = '${prefs.getInt('anidb_clientver') ?? 1}';
  }

  Future<void> _loadHomeSection() async {
    final prefs = await SharedPreferences.getInstance();
    final index = prefs.getInt(_homeSectionKey) ?? _currentSection.index;
    if (index < 0 || index >= HomeSection.values.length || !mounted) return;
    setState(() => _currentSection = HomeSection.values[index]);
  }

  Future<void> _setSection(HomeSection section) async {
    if (_currentSection == section) return;
    setState(() => _currentSection = section);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_homeSectionKey, section.index);
  }

  Future<void> _syncMedia() async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final knownPaths = prefs.getStringList('media_library') ?? [];
      final docDir = await getApplicationDocumentsDirectory();
      final entities = await docDir.list(recursive: true).toList();
      final validExtensions = ['.mp4', '.mkv', '.avi', '.mov', '.webm'];
      final discoveredPaths = <String>[];

      for (final entity in entities) {
        if (entity is! File) continue;
        final path = entity.path;
        final lowerPath = path.toLowerCase();
        final isVideo = validExtensions.any(lowerPath.endsWith);
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
      debugPrint('Error syncing media: $e');
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  void _showSMBDialog() {
    showDialog(
      context: context,
      builder: (context) {
        var connecting = false;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              child: AdaptiveLiquidGlassLayer(
                settings: const LiquidGlassSettings(),
                child: GlassCard(
                  padding: const EdgeInsets.all(20),
                  shape: const LiquidRoundedSuperellipse(borderRadius: 16),
                  child: SizedBox(
                    width: 340,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Connect to Network Share',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 16),
                        GlassTextField(
                          useOwnLayer: true,
                          controller: _smbHostCtrl,
                          placeholder: 'Host IP or name',
                          textStyle: const TextStyle(color: Colors.white),
                        ),
                        const SizedBox(height: 12),
                        GlassTextField(
                          useOwnLayer: true,
                          controller: _smbDomainCtrl,
                          placeholder: 'Domain',
                          textStyle: const TextStyle(color: Colors.white),
                        ),
                        const SizedBox(height: 12),
                        GlassTextField(
                          useOwnLayer: true,
                          controller: _smbUserCtrl,
                          placeholder: 'Username',
                          textStyle: const TextStyle(color: Colors.white),
                        ),
                        const SizedBox(height: 12),
                        GlassTextField(
                          useOwnLayer: true,
                          controller: _smbPassCtrl,
                          placeholder: 'Password',
                          obscureText: true,
                          textStyle: const TextStyle(color: Colors.white),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            GlassButton.custom(
                              shape: const LiquidRoundedSuperellipse(borderRadius: 10),
                              onTap: () => Navigator.pop(context),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                child: Text('Cancel', style: TextStyle(color: Colors.white54)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            GlassButton.custom(
                              shape: const LiquidRoundedSuperellipse(borderRadius: 10),
                              onTap: () async {
                                if (connecting) return;
                                setDialogState(() => connecting = true);
                                final success = await SMBService().connect(
                                  _smbHostCtrl.text.trim(),
                                  _smbDomainCtrl.text.trim(),
                                  _smbUserCtrl.text.trim(),
                                  _smbPassCtrl.text,
                                );
                                setDialogState(() => connecting = false);
                                if (success && context.mounted) {
                                  Navigator.pop(context);
                                }
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                child: connecting
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                      )
                                    : const Text('Connect', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
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
            if (!_mediaPaths.contains(path)) {
              _mediaPaths.insert(0, path);
            }
          }
        });
        await prefs.setStringList('media_library', _mediaPaths);
      }
    } catch (e) {
      debugPrint('Error picking file: $e');
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
    } finally {
      if (mounted) setState(() => _isScraping = false);
    }
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: GlassCard(
            useOwnLayer: true,
            padding: const EdgeInsets.all(20),
            shape: const LiquidRoundedSuperellipse(borderRadius: 16),
            child: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Settings',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      GlassIconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(color: Colors.white12),
                  const SizedBox(height: 12),
                  ListenableBuilder(
                    listenable: CacheManagerService(),
                    builder: (context, _) {
                      final limit = CacheManagerService().cacheLimitGB;
                      return Row(
                        children: [
                          const Icon(Icons.storage_rounded, size: 20, color: Colors.white70),
                          const SizedBox(width: 8),
                          Text(
                            'Download limit: ${limit.toInt()} GB',
                            style: const TextStyle(color: Colors.white70),
                          ),
                          Expanded(
                            child: GlassSlider(
                              useOwnLayer: true,
                              value: limit,
                              min: 5.0,
                              max: 100.0,
                              divisions: 19,
                              activeColor: Colors.white,
                              thumbColor: Colors.white,
                              onChanged: CacheManagerService().setCacheLimit,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  const Divider(color: Colors.white12),
                  const SizedBox(height: 12),
                  const Text(
                    'AniDB API',
                    style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  GlassTextField(
                    useOwnLayer: true,
                    controller: _anidbClientCtrl,
                    placeholder: 'Client name',
                    textStyle: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 12),
                  GlassTextField(
                    useOwnLayer: true,
                    controller: _anidbClientVerCtrl,
                    placeholder: 'Client version',
                    keyboardType: TextInputType.number,
                    textStyle: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: GlassButton.custom(
                      shape: const LiquidRoundedSuperellipse(borderRadius: 10),
                      onTap: () async {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setString(
                          'anidb_client',
                          _anidbClientCtrl.text.trim(),
                        );
                        await prefs.setInt(
                          'anidb_clientver',
                          int.tryParse(_anidbClientVerCtrl.text.trim()) ?? 1,
                        );
                        if (context.mounted) Navigator.pop(context);
                        await _refreshAnimeLibrary();
                      },
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        child: Text('Save API settings', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
      extendBody: false,
      background: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0C0720), // Deep blue space
              Color(0xFF1B0C30), // Deep purple space
              Color(0xFF000000), // Pure black
            ],
          ),
        ),
      ),
      statusBarStyle: GlassStatusBarStyle.auto,
      appBar: GlassAppBar(
        backgroundColor: Colors.transparent,
        title: Text(
          _sectionTitle,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        actions: [
          if (_currentSection == HomeSection.network)
            GlassButton(
              shape: const LiquidRoundedSuperellipse(borderRadius: 12),
              icon: const Icon(Icons.router_rounded, color: Colors.white),
              onTap: _showSMBDialog,
            ),
          GlassButton(
            shape: const LiquidRoundedSuperellipse(borderRadius: 12),
            icon: const Icon(Icons.settings_rounded, color: Colors.white),
            onTap: _showSettingsDialog,
          ),
          if (_currentSection == HomeSection.library)
            GlassButton.custom(
              shape: const LiquidRoundedSuperellipse(borderRadius: 12),
              onTap: () {
                if (_isSyncing || _isScraping) return;
                _importVideo();
              },
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: _isSyncing || _isScraping
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.add_rounded, color: Colors.white),
              ),
            ),
        ],
      ),
      body: _buildContent(),
      // ignore: experimental_member_use
      bottomBar: GlassAdaptiveScope(
        minQuality: GlassQuality.premium,
        child: GlassTabBar.bottom(
          tabs: const [
            GlassTab(icon: Icon(Icons.video_library_outlined), label: 'Library'),
            GlassTab(icon: Icon(Icons.folder_shared_outlined), label: 'Network'),
            GlassTab(icon: Icon(Icons.download_done_outlined), label: 'Downloads'),
          ],
          selectedIndex: _currentSection.index,
          onTabSelected: (index) => _setSection(HomeSection.values[index]),
        ),
      ),
    );
  }

  Widget _buildContent() {
    return IndexedStack(
      index: _currentSection.index,
      children: [
        _buildLibrary(),
        const SMBFileSystemViewer(),
        const DownloadsView(),
      ],
    );
  }

  Widget _buildLibrary() {
    if (_mediaPaths.isEmpty) {
      return Center(
        child: Text(
          'No media imported.\nUse + to add local videos.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.45),
            fontSize: 16,
          ),
        ),
      );
    }

    if (_isScraping && _animeSeries.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final series = _animeSeries;
    if (series.isEmpty) {
      return Center(
        child: Text(
          'Scraping media library...',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.45)),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisExtent: 272,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
      ),
      itemCount: series.length,
      itemBuilder: (context, index) {
        return _AnimeSeriesCard(
          series: series[index],
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => AnimeSeriesScreen(series: series[index]),
              ),
            );
          },
        );
      },
    );
  }

  String get _sectionTitle {
    return switch (_currentSection) {
      HomeSection.library => 'Library',
      HomeSection.network => 'Network',
      HomeSection.downloads => 'Downloads',
    };
  }
}

class _AnimeSeriesCard extends StatelessWidget {
  final AnimeSeries series;
  final VoidCallback onTap;

  const _AnimeSeriesCard({required this.series, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: EdgeInsets.zero,
      clipBehavior: Clip.none, // Disable card-level clip to avoid border cut-offs and white outline glitches
      shape: const LiquidRoundedSuperellipse(borderRadius: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
                child: _SeriesCover(series: series),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          series.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            height: 1.16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      if (series.isUnknown)
                        Container(
                          margin: const EdgeInsets.only(left: 6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orangeAccent.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'Unknown',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.orangeAccent,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${series.episodes.length} episodes  -  ${series.fileCount} files',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.48),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
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
        errorBuilder: (context, error, stackTrace) {
          return _CoverFallback(series: series);
        },
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
          colors: [Color(0xFF202020), Color(0xFF101010)],
        ),
      ),
      child: Center(
        child: Icon(
          series.isUnknown
              ? Icons.help_outline_rounded
              : Icons.movie_creation_outlined,
          color: Colors.white54,
          size: 42,
        ),
      ),
    );
  }
}
