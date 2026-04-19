import 'package:flutter/material.dart';

import 'package:anivault/services/cache_manager_service.dart';
import 'package:anivault/ui/player_screen.dart';

class DownloadsView extends StatelessWidget {
  const DownloadsView({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: CacheManagerService(),
      builder: (context, _) {
        final activeTasks = CacheManagerService().activeTasks.values.toList();
        final downloads = CacheManagerService().cachedDownloads;

        if (activeTasks.isEmpty && downloads.isEmpty) {
          return Center(
            child: Text(
              'No downloads yet.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.45)),
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
          children: [
            if (activeTasks.isNotEmpty) ...[
              _SectionTitle(title: 'Downloading', count: activeTasks.length),
              for (final task in activeTasks) _ActiveDownloadTile(task: task),
              const SizedBox(height: 16),
            ],
            if (downloads.isNotEmpty) ...[
              _SectionTitle(title: 'Downloaded', count: downloads.length),
              for (final item in downloads) _CompletedDownloadTile(item: item),
            ],
          ],
        );
      },
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final int count;

  const _SectionTitle({required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 10),
      child: Text(
        '$title ($count)',
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.72),
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
      ),
    );
  }
}

class _ActiveDownloadTile extends StatelessWidget {
  final CacheTask task;

  const _ActiveDownloadTile({required this.task});

  @override
  Widget build(BuildContext context) {
    final progressLabel = task.totalBytes > 0
        ? '${(task.progress * 100).clamp(0, 100).toStringAsFixed(0)}%'
        : 'Working';

    return _DownloadSurface(
      child: ListTile(
        leading: const Icon(
          Icons.downloading_rounded,
          color: Colors.lightBlueAccent,
        ),
        title: Text(
          task.fileName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LinearProgressIndicator(
                value: task.totalBytes > 0 ? task.progress : null,
                minHeight: 4,
              ),
              const SizedBox(height: 6),
              Text(
                '${_formatBytes(task.downloadedBytes)} / ${_formatBytes(task.totalBytes)}  -  ${_formatBytes(task.speedBytesPerSecond.round())}/s',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.45)),
              ),
            ],
          ),
        ),
        trailing: Text(
          progressLabel,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _CompletedDownloadTile extends StatelessWidget {
  final CachedDownload item;

  const _CompletedDownloadTile({required this.item});

  @override
  Widget build(BuildContext context) {
    return _DownloadSurface(
      child: ListTile(
        leading: const Icon(
          Icons.movie_creation_outlined,
          color: Colors.white70,
        ),
        title: Text(
          item.fileName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${_formatBytes(item.size)}  -  ${item.smbPath}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.45)),
        ),
        trailing: Wrap(
          spacing: 4,
          children: [
            IconButton(
              tooltip: 'Play',
              icon: const Icon(Icons.play_arrow_rounded),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PlayerScreen(
                      videoPath: item.localPath,
                      title: item.fileName,
                    ),
                  ),
                );
              },
            ),
            IconButton(
              tooltip: 'Delete download',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => CacheManagerService().deleteDownload(item),
            ),
          ],
        ),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  PlayerScreen(videoPath: item.localPath, title: item.fileName),
            ),
          );
        },
      ),
    );
  }
}

class _DownloadSurface extends StatelessWidget {
  final Widget child;

  const _DownloadSurface({required this.child});

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
