import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anivault/services/cache_manager_service.dart';
import 'package:anivault/services/logger_service.dart';
import 'package:anivault/services/smb_service.dart';
import 'package:anivault/ui/downloads_view.dart';
import 'package:anivault/ui/player_screen.dart';
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
  HomeSection _currentSection = HomeSection.library;

  final _smbHostCtrl = TextEditingController();
  final _smbDomainCtrl = TextEditingController();
  final _smbUserCtrl = TextEditingController();
  final _smbPassCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSmbFields();
    _loadHomeSection();
    _syncMedia();
  }

  @override
  void dispose() {
    _smbHostCtrl.dispose();
    _smbDomainCtrl.dispose();
    _smbUserCtrl.dispose();
    _smbPassCtrl.dispose();
    super.dispose();
  }

  void _loadSmbFields() {
    _smbHostCtrl.text = SMBService().savedHost;
    _smbDomainCtrl.text = SMBService().savedDomain;
    _smbUserCtrl.text = SMBService().savedUser;
    _smbPassCtrl.text = SMBService().savedPass;
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

  Future<void> _removeVideo(String path) async {
    setState(() => _mediaPaths.remove(path));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('media_library', _mediaPaths);
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
              icon: _isSyncing ? null : Icons.add_rounded,
              tooltip: 'Import media',
              onPressed: _isSyncing ? null : _importVideo,
              child: _isSyncing
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

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
      itemCount: _mediaPaths.length,
      itemBuilder: (context, index) {
        final path = _mediaPaths[index];
        final filename = File(path).uri.pathSegments.last;

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF141414),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: ListTile(
            leading: const Icon(
              Icons.play_arrow_rounded,
              color: Colors.white70,
            ),
            title: Text(
              filename,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              path,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.45)),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _removeVideo(path),
            ),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) =>
                      PlayerScreen(videoPath: path, title: filename),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildBottomNavigation() {
    return Container(
      height: 56,
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
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
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF242424) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 20,
                color: selected ? Colors.white : Colors.white54,
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
