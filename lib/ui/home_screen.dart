import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:file_selector/file_selector.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:anivault/ui/player_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<String> _mediaPaths = [];

  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _syncMedia();
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
              titlePadding: const EdgeInsets.only(left: 20, bottom: 16),
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
          
          // Media List
          if (_mediaPaths.isEmpty)
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
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
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
    );
  }
}
