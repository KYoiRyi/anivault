import 'dart:io';
import 'dart:ui';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anivault/services/anime_library_service.dart';
import 'package:anivault/services/cache_manager_service.dart';
import 'package:anivault/services/logger_service.dart';
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
            return AlertDialog(
              backgroundColor: const Color(0xFF111111),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              title: const Text('Connect to Network Share'),
              content: SizedBox(
                width: 340,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: _smbHostCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Host IP or name',
                      ),
                    ),
                    TextField(
                      controller: _smbDomainCtrl,
                      decoration: const InputDecoration(labelText: 'Domain'),
                    ),
                    TextField(
                      controller: _smbUserCtrl,
                      decoration: const InputDecoration(labelText: 'Username'),
                    ),
                    TextField(
                      controller: _smbPassCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Password'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: connecting
                      ? null
                      : () async {
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
                  child: connecting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Connect'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _importVideo() async {
    try {
      const typeGroup = XTypeGroup(
        label: 'Videos',
        extensions: ['mkv', 'mp4', 'avi', 'mov', 'webm'],
      );
      final files = await openFiles(acceptedTypeGroups: [typeGroup]);

      if (files.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        setState(() {
          for (final xfile in files) {
            final path = xfile.path;
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

  void _showLogsDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: const Color(0xFF111111),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: SizedBox(
            width: 640,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Logs',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const Divider(),
                  SizedBox(
                    height: 360,
                    child: ListenableBuilder(
                      listenable: LoggerService(),
                      builder: (context, _) {
                        final logs = LoggerService().logs;
                        if (logs.isEmpty) {
                          return Center(
                            child: Text(
                              'No logs yet.',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.45),
                              ),
                            ),
                          );
                        }
                        return ListView.builder(
                          itemCount: logs.length,
                          itemBuilder: (context, index) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Text(
                                logs[index],
                                style: const TextStyle(
                                  fontFamily: 'Consolas',
                                  fontSize: 13,
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                  const Divider(),
                  ListenableBuilder(
                    listenable: CacheManagerService(),
                    builder: (context, _) {
                      final limit = CacheManagerService().cacheLimitGB;
                      return Row(
                        children: [
                          const Icon(Icons.storage_rounded, size: 20),
                          const SizedBox(width: 8),
                          Text('Download limit: ${limit.toInt()} GB'),
                          Expanded(
                            child: Slider(
                              value: limit,
                              min: 5,
                              max: 100,
                              divisions: 19,
                              onChanged: CacheManagerService().setCacheLimit,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const Divider(),
                  const Text(
                    'AniDB API',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _anidbClientCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Client name',
                      helperText:
                          'Optional. Required only for cover/detail fetching.',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _anidbClientVerCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Client version',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.tonal(
                      onPressed: () async {
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
                      child: const Text('Save API settings'),
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
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(),
            Expanded(child: _buildContent()),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: _buildBottomNavigation(),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.black,
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _sectionTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
          ),
          if (_currentSection == HomeSection.network)
            _HeaderButton(
              icon: Icons.router_rounded,
              tooltip: 'SMB settings',
              onPressed: _showSMBDialog,
            ),
          _HeaderButton(
            icon: Icons.terminal_rounded,
            tooltip: 'Logs',
            onPressed: _showLogsDialog,
          ),
          if (_currentSection == HomeSection.library)
            _HeaderButton(
              icon: _isSyncing || _isScraping ? null : Icons.add_rounded,
              tooltip: 'Import media',
              onPressed: _isSyncing || _isScraping ? null : _importVideo,
              child: _isSyncing || _isScraping
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
            ),
        ],
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

  Widget _buildBottomNavigation() {
    return Container(
      height: 66,
      margin: const EdgeInsets.fromLTRB(18, 8, 18, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(33),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.34),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(33),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(33),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: 0.24),
                  Colors.white.withValues(alpha: 0.08),
                  Colors.black.withValues(alpha: 0.18),
                ],
              ),
              border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
            ),
            child: Row(
              children: [
                _NavigationItem(
                  label: 'Library',
                  icon: Icons.video_library_outlined,
                  selected: _currentSection == HomeSection.library,
                  onTap: () => _setSection(HomeSection.library),
                ),
                _NavigationItem(
                  label: 'Network',
                  icon: Icons.folder_shared_outlined,
                  selected: _currentSection == HomeSection.network,
                  onTap: () => _setSection(HomeSection.network),
                ),
                _NavigationItem(
                  label: 'Downloads',
                  icon: Icons.download_done_outlined,
                  selected: _currentSection == HomeSection.downloads,
                  onTap: () => _setSection(HomeSection.downloads),
                ),
              ],
            ),
          ),
        ),
      ),
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

class _HeaderButton extends StatelessWidget {
  final IconData? icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Widget? child;

  const _HeaderButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: const Color(0xFF1B1B1B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        icon: child ?? Icon(icon),
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
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF141414),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(8),
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

class _NavigationItem extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _NavigationItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          height: double.infinity,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: selected
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withValues(alpha: 0.34),
                      Colors.white.withValues(alpha: 0.16),
                    ],
                  )
                : null,
            border: selected
                ? Border.all(color: Colors.white.withValues(alpha: 0.24))
                : null,
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.18),
                      blurRadius: 18,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 20,
                color: selected ? Colors.white : Colors.white60,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? Colors.white : Colors.white54,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
