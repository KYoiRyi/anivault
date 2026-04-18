import 'package:flutter/material.dart';
import 'package:smb_connect/smb_connect.dart';
import 'package:anivault/services/smb_service.dart';
import 'package:anivault/services/cache_manager_service.dart';
import 'package:anivault/ui/player_screen.dart';

class SMBFileSystemViewer extends StatefulWidget {
  const SMBFileSystemViewer({super.key});

  @override
  State<SMBFileSystemViewer> createState() => _SMBFileSystemViewerState();
}

class _SMBFileSystemViewerState extends State<SMBFileSystemViewer> {
  final List<String> _navigationStack = [''];
  List<SmbFile> _currentFiles = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentDirectory();
  }

  Future<void> _loadCurrentDirectory() async {
    if (!SMBService().isConnected) return;
    setState(() => _isLoading = true);
    final currentPath = _navigationStack.last;
    
    List<SmbFile> files;
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
        // Play local
        if (!mounted) return;
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => PlayerScreen(
            videoPath: cachedPath,
            title: file.name,
          )
        ));
      } else {
        // Alert to download
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${file.name} is not on disk. Tap the cloud icon to cache.'),
            behavior: SnackBarBehavior.floating,
          )
        );
      }
    }
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
        if (_navigationStack.length > 1)
          ListTile(
            leading: const Icon(Icons.drive_folder_upload, color: Colors.blueAccent),
            title: const Text('... Go Back', style: TextStyle(color: Colors.blueAccent)),
            onTap: _navigateOut,
          ),
        if (_isLoading)
          const Expanded(child: Center(child: CircularProgressIndicator()))
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
                        
                        Widget trailing;
                        if (isDir) {
                          trailing = const Icon(Icons.chevron_right, color: Colors.white24);
                        } else if (task != null && !task.isCompleted) {
                          trailing = SizedBox(
                            width: 24, height: 24,
                            child: CircularProgressIndicator(value: task.progress, color: Colors.greenAccent),
                          );
                        } else if (isCached) {
                          trailing = const Icon(Icons.offline_pin, color: Colors.greenAccent);
                        } else {
                          trailing = IconButton(
                            icon: const Icon(Icons.cloud_download, color: Colors.white54),
                            onPressed: () {
                              CacheManagerService().cacheFile(file);
                            },
                          );
                        }

                        return ListTile(
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
