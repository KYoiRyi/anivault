import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:file_selector/file_selector.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:anivault/ui/player_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<String> _mediaPaths = [];

  @override
  void initState() {
    super.initState();
    _loadMedia();
  }

  Future<void> _loadMedia() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _mediaPaths = prefs.getStringList('media_library') ?? [];
    });
  }

  Future<void> _saveMedia() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('media_library', _mediaPaths);
  }

  Future<void> _importVideo() async {
    try {
      const XTypeGroup typeGroup = XTypeGroup(
        label: 'Videos',
        extensions: <String>['mkv', 'mp4', 'avi', 'mov', 'webm'],
      );
      final List<XFile> files = await openFiles(acceptedTypeGroups: <XTypeGroup>[typeGroup]);

      if (files.isNotEmpty) {
        setState(() {
          for (var xfile in files) {
            final path = xfile.path;
            if (!_mediaPaths.contains(path)) {
              _mediaPaths.insert(0, path); // Add to top
            }
          }
        });
        await _saveMedia();
      }
    } catch (e) {
      debugPrint('Error picking file: $e');
    }
  }

  Future<void> _removeVideo(String path) async {
    setState(() {
      _mediaPaths.remove(path);
    });
    await _saveMedia();
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
                  icon: const Icon(Icons.add, size: 24),
                  style: IconButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _importVideo,
                  tooltip: 'Import Video',
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
