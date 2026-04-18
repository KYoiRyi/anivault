import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:file_selector/file_selector.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:ui';
import 'package:anivault/ui/player_screen.dart';
import 'package:anivault/services/logger_service.dart';
import 'package:anivault/services/smb_service.dart';
import 'package:anivault/services/cache_manager_service.dart';
import 'package:anivault/ui/smb_viewer.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

enum NetworkMode { local, smb }

class _HomeScreenState extends State<HomeScreen> {
  List<String> _mediaPaths = [];
  bool _isSyncing = false;
  NetworkMode _currentMode = NetworkMode.local;
  
  final _smbHostCtrl = TextEditingController();
  final _smbDomainCtrl = TextEditingController();
  final _smbUserCtrl = TextEditingController();
  final _smbPassCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _syncMedia();
    _smbHostCtrl.text = SMBService().savedHost;
    _smbUserCtrl.text = SMBService().savedUser;
    _smbPassCtrl.text = SMBService().savedPass;
  }

  Future<void> _syncMedia() async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);
    
    try {
      final prefs = await SharedPreferences.getInstance();
      List<String> knownPaths = prefs.getStringList('media_library') ?? [];
      
      // Auto-scan iOS Sandbox / Local Document directory
      final Directory docDir = await getApplicationDocumentsDirectory();
      final List<FileSystemEntity> entities = await docDir.list(recursive: true).toList();
      
      final validExtensions = ['.mp4', '.mkv', '.avi', '.mov', '.webm'];
      List<String> discoveredPaths = [];
      
      for (var entity in entities) {
        if (entity is File) {
          final ext = entity.path.substring(entity.path.lastIndexOf('.')).toLowerCase();
          if (validExtensions.contains(ext) && !knownPaths.contains(entity.path)) {
            discoveredPaths.add(entity.path);
          }
        }
      }
      
      // Validate existing known paths to clean up deleted synced files
      knownPaths.removeWhere((path) => !File(path).existsSync());
      
      final mergedPaths = [...discoveredPaths, ...knownPaths];
      
      setState(() {
        _mediaPaths = mergedPaths;
      });
      await prefs.setStringList('media_library', mergedPaths);
    } catch (e) {
      debugPrint('Error syncing media: $e');
    } finally {
      setState(() => _isSyncing = false);
    }
  }

  void _showSMBDial() {
    showDialog(
      context: context,
      builder: (context) {
        bool connecting = false;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: Colors.black87,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Colors.white24)),
              title: const Text('Connect to Network Share', style: TextStyle(color: Colors.white)),
              content: SizedBox(
                width: 300,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(controller: _smbHostCtrl, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Host IP (e.g. 192.168.1.10)')),
                    TextField(controller: _smbDomainCtrl, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Domain (Optional)')),
                    TextField(controller: _smbUserCtrl, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Username')),
                    TextField(controller: _smbPassCtrl, obscureText: true, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Password')),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                FilledButton.tonal(
                  onPressed: connecting ? null : () async {
                    setDialogState(() => connecting = true);
                    final success = await SMBService().connect(
                      _smbHostCtrl.text,
                      _smbDomainCtrl.text,
                      _smbUserCtrl.text,
                      _smbPassCtrl.text
                    );
                    setDialogState(() => connecting = false);
                    if (success && mounted) Navigator.pop(context);
                  },
                  child: connecting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Connect'),
                )
              ],
            );
          }
        );
      }
    );
  }

  Future<void> _importVideo() async {
    // Legacy file picker fallback (Useful for Desktop) + trigger Sync
    try {
      const XTypeGroup typeGroup = XTypeGroup(
        label: 'Videos',
        extensions: <String>['mkv', 'mp4', 'avi', 'mov', 'webm'],
      );
      final List<XFile> files = await openFiles(acceptedTypeGroups: <XTypeGroup>[typeGroup]);

      if (files.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        setState(() {
          for (var xfile in files) {
            final path = xfile.path;
            if (!_mediaPaths.contains(path)) {
              _mediaPaths.insert(0, path); // Add to top
            }
          }
        });
        await prefs.setStringList('media_library', _mediaPaths);
      }
    } catch (e) {
      debugPrint('Error picking file: $e');
    }
    // Deep sync after manual additions just in case
    await _syncMedia();
  }

  Future<void> _removeVideo(String path) async {
    setState(() {
      _mediaPaths.remove(path);
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('media_library', _mediaPaths);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // Monochrome base
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // Apple Style Large Header
          SliverAppBar(
            expandedHeight: 120.0,
            floating: false,
            pinned: true,
            backgroundColor: Colors.black.withValues(alpha: 0.8),
            elevation: 0,
            flexibleSpace: FlexibleSpaceBar(
              title: const Text(
                'Library',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1.0,
                  color: Colors.white,
                ),
              ),
            ),
            actions: [
              if (_currentMode == NetworkMode.smb)
                Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: IconButton.filledTonal(
                    icon: const Icon(Icons.router, size: 24),
                    style: IconButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _showSMBDial,
                    tooltip: 'SMB Config',
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: IconButton.filledTonal(
                  icon: const Icon(Icons.terminal_rounded, size: 24),
                  style: IconButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) {
                        return Dialog(
                          backgroundColor: Colors.black87,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Colors.white24)),
                          child: Container(
                            width: 600,
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('Hardware Console', style: TextStyle(color: Colors.greenAccent, fontFamily: 'Consolas', fontWeight: FontWeight.bold)),
                                    IconButton(
                                      icon: const Icon(Icons.close, color: Colors.white54),
                                      onPressed: () => Navigator.pop(context),
                                    )
                                  ],
                                ),
                                const Divider(color: Colors.white24),
                                SizedBox(
                                  height: 400,
                                  child: ListenableBuilder(
                                    listenable: LoggerService(),
                                    builder: (context, _) {
                                      final logs = LoggerService().logs;
                                      if (logs.isEmpty) {
                                        return const Center(child: Text('Console is waiting for trace signals...', style: TextStyle(color: Colors.white54, fontStyle: FontStyle.italic)));
                                      }
                                      return ListView.builder(
                                        itemCount: logs.length,
                                        itemBuilder: (context, index) {
                                          return Padding(
                                            padding: const EdgeInsets.symmetric(vertical: 2.0),
                                            child: Text(
                                              logs[index],
                                              style: const TextStyle(fontFamily: 'Consolas', fontSize: 13, color: Colors.white70),
                                            ),
                                          );
                                        },
                                      );
                                    },
                                  ),
                                ),
                                const Divider(color: Colors.white24),
                                ListenableBuilder(
                                  listenable: CacheManagerService(),
                                  builder: (context, _) {
                                    final limit = CacheManagerService().cacheLimitGB;
                                    return Row(
                                      children: [
                                        const Icon(Icons.storage, color: Colors.white54, size: 20),
                                        const SizedBox(width: 8),
                                        Text('Offline Cache Limit: ${limit.toInt()} GB', style: const TextStyle(color: Colors.white70)),
                                        Expanded(
                                          child: Slider(
                                            value: limit,
                                            min: 5,
                                            max: 100,
                                            divisions: 19,
                                            activeColor: Colors.greenAccent,
                                            onChanged: (val) {
                                              CacheManagerService().setCacheLimit(val);
                                            },
                                          ),
                                        ),
                                      ],
                                    );
                                  }
                                )
                              ],
                            ),
                          ),
                        );
                      }
                    );
                  },
                  tooltip: 'System Console',
                ),
              ),
              if (_currentMode == NetworkMode.local)
                Padding(
                  padding: const EdgeInsets.only(right: 16.0),
                  child: IconButton.filledTonal(
                    icon: _isSyncing 
                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)) 
                        : const Icon(Icons.sync_rounded, size: 24),
                    style: IconButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _isSyncing ? null : _importVideo,
                    tooltip: 'Sync / Import Media',
                  ),
                )
            ],
          ),
          
          // Media List OR Network List
          if (_currentMode == NetworkMode.smb)
            const SliverFillRemaining(
               child: SMBFileSystemViewer()
            )
          else if (_mediaPaths.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Text(
                  'No media imported.\nTap + to add local videos.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 16,
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final path = _mediaPaths[index];
                    final file = File(path);
                    final filename = file.uri.pathSegments.last;
                    
                    return OutlinedButton(
                      style: ButtonStyle(
                        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
                        shape: WidgetStatePropertyAll(
                          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        backgroundColor: WidgetStatePropertyAll(Theme.of(context).colorScheme.surfaceContainerLow),
                        side: WidgetStateProperty.resolveWith((states) {
                          if (states.contains(WidgetState.hovered) || states.contains(WidgetState.pressed)) {
                            return BorderSide(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.6));
                          }
                          return BorderSide(color: Theme.of(context).colorScheme.surfaceContainerHighest);
                        }),
                      ),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => PlayerScreen(
                              videoPath: path,
                              title: filename,
                            ),
                          ),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                        child: ListTile(
                          leading: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.play_arrow_rounded, color: Colors.white70),
                          ),
                          title: Text(
                            filename,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            path,
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _removeVideo(path),
                          ),
                        ),
                      ),
                    );
                  },
                  childCount: _mediaPaths.length,
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: Container(
        margin: const EdgeInsets.only(bottom: 24, left: 32, right: 32),
        height: 64,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: Colors.white12),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 20, offset: const Offset(0, 10))
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildDockItem('Vault', Icons.drive_folder_upload, NetworkMode.local),
                _buildDockItem('Network', Icons.rocket_launch, NetworkMode.smb),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDockItem(String label, IconData icon, NetworkMode mode) {
    final isSelected = _currentMode == mode;
    return GestureDetector(
      onTap: () => setState(() => _currentMode = mode),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutExpo,
        width: isSelected ? 120 : 64,
        height: 48,
        decoration: BoxDecoration(
          color: isSelected ? Colors.white.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: isSelected ? Colors.greenAccent : Colors.white54, size: 20),
            if (isSelected) ...[
              const SizedBox(height: 4),
              Container(
                width: 4, height: 4,
                decoration: const BoxDecoration(color: Colors.greenAccent, shape: BoxShape.circle),
              )
            ]
          ],
        ),
      ),
    );
  }
}
