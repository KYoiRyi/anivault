import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:smb_connect/smb_connect.dart';
import 'package:anivault/services/smb_service.dart';
import 'package:anivault/services/cache_manager_service.dart';
import 'package:anivault/ui/player_screen.dart';

class SMBFileSystemViewer extends StatefulWidget {
  const SMBFileSystemViewer({super.key});

  @override
  State<SMBFileSystemViewer> createState() => _SMBFileSystemViewerState();
}

class _SMBFileSystemViewerState extends State<SMBFileSystemViewer> with AutomaticKeepAliveClientMixin {
  final List<String> _navigationStack = []; // Empty means seeing the root server UI
  List<SmbFile> _currentFiles = [];
  bool _isLoading = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    SMBService().addListener(_onSmbStateChanged);
    _loadCurrentDirectory();
  }

  @override
  void dispose() {
    SMBService().removeListener(_onSmbStateChanged);
    super.dispose();
  }

  void _onSmbStateChanged() {
    if (SMBService().isConnected && mounted) {
      if (_navigationStack.isNotEmpty) {
        _loadCurrentDirectory();
      } else {
        setState(() {}); // Trigger rebuild to show the 'Server Root UI'
      }
    }
  }

  Future<void> _loadCurrentDirectory() async {
    if (!SMBService().isConnected) return;
    final currentPath = _navigationStack.isEmpty ? null : _navigationStack.last;
    
    if (currentPath == null) {
      setState(() => _isLoading = false);
      return;
    }

    setState(() => _isLoading = true);
    List<SmbFile> files = [];
    if (currentPath.isEmpty) {
      files = await SMBService().listShares();
    } else {
      files = await SMBService().listFiles(currentPath);
      files.removeWhere((element) => element.name == '.' || element.name == '..');
    }
    
    setState(() {
      _currentFiles = files;
      _isLoading = false;
    });
  }

  void _navigateIn(String path) {
    _navigationStack.add(path);
    _loadCurrentDirectory();
  }

  void _navigateOut() {
    if (_navigationStack.length > 1) {
      _navigationStack.removeLast();
      _loadCurrentDirectory();
    }
  }

  void _handleFileTap(SmbFile file) async {
    if (file.isDirectory() || file.share == file.name && file.path.endsWith('/')) {
      _navigateIn(file.path);
    } else {
      // Check if it's cached
      final cachedPath = await CacheManagerService().getCachedPath(file.path);
      if (cachedPath != null) {
        if (!mounted) return;
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => PlayerScreen(videoPath: cachedPath, title: file.name)
        ));
      } else {
        _showFileInspectorPanel(file);
      }
    }
  }

  void _showFileInspectorPanel(SmbFile file) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (context) {
        return TweenAnimationBuilder<double>(
          duration: const Duration(milliseconds: 600),
          curve: Curves.elasticOut,
          tween: Tween(begin: 0.8, end: 1.0),
          builder: (context, scale, child) {
            return Transform.scale(scale: scale, child: child);
          },
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
              child: Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.3), width: 1.5)),
                  boxShadow: [
                    BoxShadow(color: Colors.blueAccent.withValues(alpha: 0.2), blurRadius: 40, spreadRadius: 10),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 80, height: 80,
                      decoration: BoxDecoration(
                        color: Colors.blueAccent.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.cloud_sync_rounded, size: 48, color: Colors.blueAccent),
                    ),
                    const SizedBox(height: 24),
                    Text(file.name, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    Text('${(file.size / 1024 / 1024).toStringAsFixed(2)} MB required', style: TextStyle(color: Colors.blueAccent.withValues(alpha: 0.5), fontSize: 16)),
                    const SizedBox(height: 40),
                    SizedBox(
                      width: double.infinity,
                      height: 64,
                      child: FilledButton.tonal(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.blueAccent.withValues(alpha: 0.25),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          CacheManagerService().cacheFile(file);
                        },
                        child: const Text('Inject Cache to Vault', style: TextStyle(fontSize: 18, color: Colors.blueAccent, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!SMBService().isConnected) {
      return Center(
        child: Text(
          'Connect to a Network Share to view files.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
        ),
      );
    }

    return Column(
      children: [
        // Download Citadel Floating Pill
        ListenableBuilder(
          listenable: CacheManagerService(),
          builder: (context, _) {
            final tasks = CacheManagerService().activeTasks.values.where((t) => !t.isCompleted).toList();
            if (tasks.isEmpty) return const SizedBox.shrink();
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.greenAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.5)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: ListTile(
                    leading: const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(color: Colors.greenAccent, strokeWidth: 2),
                    ),
                    title: Text('Vault injecting ${tasks.length} items', style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
            );
          }
        ),

        if (_navigationStack.length > 0)
          ListTile(
            leading: const Icon(Icons.drive_folder_upload, color: Colors.blueAccent),
            title: const Text('... Go Back', style: TextStyle(color: Colors.blueAccent)),
            onTap: _navigateOut,
          ),
        if (_isLoading)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (_navigationStack.isEmpty)
          Expanded(
            child: ListView(
              children: [
                TweenAnimationBuilder<double>(
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeOutBack,
                  tween: Tween(begin: 0.9, end: 1.0),
                  builder: (context, scale, child) {
                    return Transform.scale(
                      scale: scale,
                      child: Opacity(
                        opacity: (scale - 0.9) * 10,
                        child: child
                      ),
                    );
                  },
                  child: Container(
                    margin: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.blueAccent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(24),
                          leading: const Icon(Icons.dns_rounded, color: Colors.blueAccent, size: 48),
                          title: Text('Server Node', style: TextStyle(color: Colors.blueAccent.withValues(alpha: 0.7), fontSize: 14)),
                          subtitle: Text(SMBService().currentHost, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                          onTap: () {
                            _navigateIn('');
                          },
                        ),
                      ),
                    ),
                  ),
                )
              ]
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              itemCount: _currentFiles.length,
              itemBuilder: (context, index) {
                final file = _currentFiles[index];
                final isDir = file.isDirectory() || file.share == file.name && file.path.endsWith('/');
                
                return FutureBuilder<String?>(
                  future: isDir ? Future.value(null) : CacheManagerService().getCachedPath(file.path),
                  builder: (context, snapshot) {
                    final bool isCached = snapshot.data != null;
                    
                    return ListenableBuilder(
                      listenable: CacheManagerService(),
                      builder: (context, _) {
                        final task = CacheManagerService().activeTasks[file.path];
                        
                        Widget trailing = const SizedBox.shrink();
                        if (isDir) {
                          trailing = const Icon(Icons.chevron_right, color: Colors.white24);
                        } else if (task != null && !task.isCompleted) {
                          trailing = SizedBox(
                            width: 24, height: 24,
                            child: CircularProgressIndicator(value: task.progress, color: Colors.greenAccent),
                          );
                        } else if (isCached) {
                          trailing = const Icon(Icons.offline_pin, color: Colors.greenAccent);
                        }

                        return TweenAnimationBuilder<double>(
                          duration: Duration(milliseconds: 300 + (index * 50).clamp(0, 500)),
                          curve: Curves.easeOutQuart,
                          tween: Tween(begin: 0.0, end: 1.0),
                          builder: (context, value, child) {
                            return Transform.translate(
                              offset: Offset(0, 50 * (1 - value)),
                              child: Opacity(
                                opacity: value,
                                child: child
                              ),
                            );
                          },
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: BackdropFilter(
                                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                                  leading: Icon(
                                    isDir ? Icons.folder : Icons.movie,
                                    color: isDir ? Colors.amber : Colors.white70,
                                  ),
                                  title: Text(
                                    file.name,
                                    style: TextStyle(
                                      color: isCached ? Colors.greenAccent : Colors.white,
                                      fontWeight: isCached ? FontWeight.bold : FontWeight.normal
                                    ),
                                    maxLines: 1, overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: isDir ? null : Text('${(file.size / 1024 / 1024).toStringAsFixed(1)} MB', style: const TextStyle(color: Colors.white30)),
                                  trailing: trailing,
                                  onTap: () => _handleFileTap(file),
                                ),
                              ),
                            ),
                          ),
                        );
                      }
                    );
                  }
                );
              },
            ),
          ),
      ],
    );
  }
}
