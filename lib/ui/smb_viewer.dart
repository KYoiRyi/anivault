import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smb_connect/smb_connect.dart';

import 'package:anivault/services/cache_manager_service.dart';
import 'package:anivault/services/smb_service.dart';
import 'package:anivault/ui/player_screen.dart';

class SMBFileSystemViewer extends StatefulWidget {
  const SMBFileSystemViewer({super.key});

  @override
  State<SMBFileSystemViewer> createState() => _SMBFileSystemViewerState();
}

class _SMBFileSystemViewerState extends State<SMBFileSystemViewer>
    with AutomaticKeepAliveClientMixin {
  static const _navigationStackKey = 'smb_navigation_stack';

  final List<String> _navigationStack = [];
  List<SmbFile> _currentFiles = [];
  bool _isLoading = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    SMBService().addListener(_onSmbStateChanged);
    _restoreStateAndConnect();
  }

  @override
  void dispose() {
    SMBService().removeListener(_onSmbStateChanged);
    super.dispose();
  }

  void _onSmbStateChanged() {
    if (!mounted) return;
    if (SMBService().isConnected &&
        _navigationStack.isNotEmpty &&
        !_isLoading) {
      _loadCurrentDirectory();
    } else {
      setState(() {});
    }
  }

  Future<void> _restoreStateAndConnect() async {
    final prefs = await SharedPreferences.getInstance();
    final savedStack = prefs.getStringList(_navigationStackKey) ?? [];

    if (!mounted) return;
    setState(() {
      _navigationStack
        ..clear()
        ..addAll(savedStack);
      _isLoading = SMBService().hasSavedConnection && !SMBService().isConnected;
    });

    if (!SMBService().isConnected && SMBService().hasSavedConnection) {
      await SMBService().connectSaved();
    }

    if (!mounted) return;
    if (SMBService().isConnected && _navigationStack.isNotEmpty) {
      await _loadCurrentDirectory();
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadCurrentDirectory() async {
    if (!SMBService().isConnected) return;
    final currentPath = _navigationStack.isEmpty ? null : _navigationStack.last;

    if (currentPath == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    setState(() => _isLoading = true);

    var files = <SmbFile>[];
    if (currentPath.isEmpty) {
      files = await SMBService().listShares();
    } else {
      files = await SMBService().listFiles(currentPath);
      files.removeWhere(
        (element) => element.name == '.' || element.name == '..',
      );
    }

    if (!mounted) return;
    setState(() {
      _currentFiles = files;
      _isLoading = false;
    });
  }

  void _navigateIn(String path) {
    _navigationStack.add(path);
    _saveNavigationStack();
    _loadCurrentDirectory();
  }

  void _navigateOut() {
    if (_navigationStack.isEmpty) return;
    _navigationStack.removeLast();
    _saveNavigationStack();
    _loadCurrentDirectory();
  }

  Future<void> _saveNavigationStack() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_navigationStackKey, _navigationStack);
  }

  Future<void> _handleFileTap(SmbFile file) async {
    if (_isDirectory(file)) {
      _navigateIn(file.path);
      return;
    }

    final cachedPath = await CacheManagerService().getCachedPath(
      file.path,
      expectedBytes: file.size,
    );
    if (!mounted) return;

    if (cachedPath != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PlayerScreen(videoPath: cachedPath, title: file.name),
        ),
      );
      return;
    }

    _showDownloadPanel(file);
  }

  void _showDownloadPanel(SmbFile file) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111111),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  file.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${_formatBytes(file.size)} will be saved for offline playback.',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.55)),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('Download'),
                  onPressed: () {
                    Navigator.pop(context);
                    CacheManagerService().cacheFile(file);
                  },
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (SMBService().isConnecting || _isLoading && !SMBService().isConnected) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!SMBService().isConnected) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                SMBService().hasSavedConnection
                    ? 'Saved network share is not connected.'
                    : 'Connect to a network share to browse files.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
              ),
              if (SMBService().hasSavedConnection) ...[
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: SMBService().connectSaved,
                  child: const Text('Reconnect'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        _DownloadStatusBar(),
        if (_navigationStack.isNotEmpty)
          _PathBar(
            title: _navigationStack.last.isEmpty
                ? 'Shares'
                : _navigationStack.last,
            onBack: _navigateOut,
          ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _navigationStack.isEmpty
              ? _ServerRoot(onOpen: () => _navigateIn(''))
              : _FileList(files: _currentFiles, onTap: _handleFileTap),
        ),
      ],
    );
  }

  bool _isDirectory(SmbFile file) {
    return file.isDirectory() ||
        (file.share == file.name && file.path.endsWith('/'));
  }
}

class _DownloadStatusBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: CacheManagerService(),
      builder: (context, _) {
        final tasks = CacheManagerService().activeTasks.values
            .where((task) => !task.isCompleted && !task.hasFailed)
            .toList();
        if (tasks.isEmpty) return const SizedBox.shrink();

        return Container(
          margin: const EdgeInsets.fromLTRB(20, 8, 20, 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF102032),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Colors.lightBlueAccent.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${tasks.length} download${tasks.length == 1 ? '' : 's'} in progress',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PathBar extends StatelessWidget {
  final String title;
  final VoidCallback onBack;

  const _PathBar({required this.title, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: onBack,
      ),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _ServerRoot extends StatelessWidget {
  final VoidCallback onOpen;

  const _ServerRoot({required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
      children: [
        _ListSurface(
          child: ListTile(
            leading: const Icon(
              Icons.dns_rounded,
              color: Colors.lightBlueAccent,
            ),
            title: const Text('Server'),
            subtitle: Text(SMBService().currentHost),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: onOpen,
          ),
        ),
      ],
    );
  }
}

class _FileList extends StatelessWidget {
  final List<SmbFile> files;
  final ValueChanged<SmbFile> onTap;

  const _FileList({required this.files, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (files.isEmpty) {
      return Center(
        child: Text(
          'No files found.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.45)),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
      itemCount: files.length,
      itemBuilder: (context, index) {
        final file = files[index];
        final isDir =
            file.isDirectory() ||
            (file.share == file.name && file.path.endsWith('/'));

        return ListenableBuilder(
          listenable: CacheManagerService(),
          builder: (context, _) {
            final task = CacheManagerService().activeTasks[file.path];
            final isCached = CacheManagerService().isCached(
              file.path,
              expectedBytes: file.size,
            );

            Widget trailing;
            if (isDir) {
              trailing = const Icon(Icons.chevron_right_rounded);
            } else if (task != null && task.hasFailed) {
              trailing = const Icon(
                Icons.error_outline_rounded,
                color: Colors.redAccent,
              );
            } else if (task != null && !task.isCompleted) {
              trailing = SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(value: task.progress),
              );
            } else if (isCached) {
              trailing = const Icon(
                Icons.offline_pin_rounded,
                color: Colors.greenAccent,
              );
            } else {
              trailing = const Icon(Icons.download_outlined);
            }

            return _ListSurface(
              child: ListTile(
                leading: Icon(
                  isDir ? Icons.folder_outlined : Icons.movie_outlined,
                  color: isDir ? Colors.amber : Colors.white70,
                ),
                title: Text(
                  file.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: isDir
                    ? null
                    : Text(
                        _fileSubtitle(file, task, isCached),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.45),
                        ),
                      ),
                trailing: trailing,
                onTap: () => onTap(file),
              ),
            );
          },
        );
      },
    );
  }

  String _fileSubtitle(SmbFile file, CacheTask? task, bool isCached) {
    if (task != null && !task.isCompleted) {
      if (task.hasFailed) return 'Download failed';
      return 'Downloading ${_formatBytes(task.downloadedBytes)} / ${_formatBytes(task.totalBytes)}';
    }
    if (isCached) return 'Downloaded - ${_formatBytes(file.size)}';
    return _formatBytes(file.size);
  }
}

class _ListSurface extends StatelessWidget {
  final Widget child;

  const _ListSurface({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: child,
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = value >= 10 || unit == 0 ? 0 : 1;
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}
