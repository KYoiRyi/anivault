import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'package:anivault/services/torrent_service.dart';
import 'package:anivault/ui/ani_glass_theme.dart';
import 'package:anivault/ui/page_transition.dart';
import 'package:anivault/ui/player_screen.dart';

class BtDownloadsView extends StatefulWidget {
  final double topPadding;
  final Future<void> Function()? onLibraryRefresh;

  const BtDownloadsView({
    super.key,
    required this.topPadding,
    this.onLibraryRefresh,
  });

  @override
  State<BtDownloadsView> createState() => _BtDownloadsViewState();
}

class _BtDownloadsViewState extends State<BtDownloadsView> {
  final _magnetCtrl = TextEditingController();
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    TorrentService().setLibraryChangedHandler(widget.onLibraryRefresh);
  }

  @override
  void didUpdateWidget(covariant BtDownloadsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.onLibraryRefresh != widget.onLibraryRefresh) {
      TorrentService().setLibraryChangedHandler(widget.onLibraryRefresh);
    }
  }

  @override
  void dispose() {
    TorrentService().setLibraryChangedHandler(null);
    _magnetCtrl.dispose();
    super.dispose();
  }

  Future<void> _addMagnet() async {
    final magnet = _magnetCtrl.text.trim();
    if (magnet.isEmpty || _adding) return;
    setState(() => _adding = true);
    try {
      await TorrentService().addMagnet(magnet);
      _magnetCtrl.clear();
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textColor = AniGlassTheme.textColor(context);
    final secondary = AniGlassTheme.secondaryTextColor(context);
    return ListenableBuilder(
      listenable: TorrentService(),
      builder: (context, _) {
        final service = TorrentService();
        final tasks = service.tasks;
        return ListView(
          padding: EdgeInsets.fromLTRB(20, widget.topPadding, 20, 110),
          children: [
            _MagnetInputCard(
              controller: _magnetCtrl,
              adding: _adding,
              onAdd: _addMagnet,
            ),
            if (service.lastError != null) ...[
              const SizedBox(height: 12),
              Text(
                service.lastError!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
            ],
            const SizedBox(height: 18),
            Text(
              'BT Tasks',
              style: TextStyle(
                color: textColor,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            if (!service.nativeReady)
              Text(
                'Native torrent engine unavailable',
                style: TextStyle(color: secondary),
              )
            else if (tasks.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 36),
                child: Center(
                  child: Text(
                    'Paste a magnet link to start downloading.',
                    style: TextStyle(color: secondary),
                  ),
                ),
              )
            else
              for (final task in tasks)
                _TorrentTaskCard(
                  task: task,
                  onLibraryRefresh: widget.onLibraryRefresh,
                ),
          ],
        );
      },
    );
  }
}

class _MagnetInputCard extends StatelessWidget {
  final TextEditingController controller;
  final bool adding;
  final VoidCallback onAdd;

  const _MagnetInputCard({
    required this.controller,
    required this.adding,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = AniGlassTheme.textColor(context);
    final secondary = AniGlassTheme.secondaryTextColor(context);
    return GlassCard(
      quality: AniGlassTheme.quality,
      useOwnLayer: true,
      settings: AniGlassTheme.heroFor(context),
      padding: const EdgeInsets.all(14),
      shape: const LiquidRoundedSuperellipse(borderRadius: 22),
      child: Row(
        children: [
          Icon(Icons.link_rounded, color: textColor),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 3,
              style: TextStyle(color: textColor, fontWeight: FontWeight.w700),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: 'magnet:?xt=urn:btih:...',
                hintStyle: TextStyle(color: secondary),
              ),
              onSubmitted: (_) => onAdd(),
            ),
          ),
          const SizedBox(width: 10),
          GlassButton(
            quality: AniGlassTheme.quality,
            settings: AniGlassTheme.chromeFor(context),
            icon: Icon(
              adding ? Icons.hourglass_top_rounded : Icons.add_rounded,
            ),
            onTap: onAdd,
          ),
        ],
      ),
    );
  }
}

class _TorrentTaskCard extends StatelessWidget {
  final TorrentTaskState task;
  final Future<void> Function()? onLibraryRefresh;

  const _TorrentTaskCard({required this.task, this.onLibraryRefresh});

  @override
  Widget build(BuildContext context) {
    final textColor = AniGlassTheme.textColor(context);
    final secondary = AniGlassTheme.secondaryTextColor(context);
    final title = task.name.isEmpty ? 'Resolving metadata' : task.name;
    final status = task.complete
        ? 'Complete'
        : task.paused
        ? 'Paused'
        : task.gotInfo
        ? '${(task.progress * 100).clamp(0, 100).toStringAsFixed(0)}%'
        : 'Fetching metadata';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        quality: AniGlassTheme.quality,
        useOwnLayer: true,
        settings: AniGlassTheme.chromeFor(context),
        padding: const EdgeInsets.all(14),
        shape: const LiquidRoundedSuperellipse(borderRadius: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  task.complete
                      ? Icons.download_done_rounded
                      : Icons.downloading_rounded,
                  color: task.complete ? Colors.greenAccent : textColor,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  status,
                  style: TextStyle(
                    color: secondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: task.totalBytes > 0 ? task.progress : null,
            ),
            const SizedBox(height: 8),
            Text(
              '${_formatBytes(task.downloadedBytes)} / ${_formatBytes(task.totalBytes)}',
              style: TextStyle(color: secondary, fontSize: 12),
            ),
            if (task.files.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (final file in task.files.take(3))
                Text(
                  '${file.displayPath}  -  ${_formatBytes(file.length)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: secondary, fontSize: 12),
                ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                GlassButton(
                  quality: AniGlassTheme.quality,
                  settings: AniGlassTheme.chromeFor(context),
                  icon: Icon(
                    task.paused
                        ? Icons.play_arrow_rounded
                        : Icons.pause_rounded,
                  ),
                  onTap: () => task.paused
                      ? TorrentService().resume(task.id)
                      : TorrentService().pause(task.id),
                ),
                const SizedBox(width: 8),
                GlassButton(
                  quality: AniGlassTheme.quality,
                  settings: AniGlassTheme.chromeFor(context),
                  icon: const Icon(Icons.refresh_rounded),
                  onTap: () =>
                      TorrentService().poll(onLibraryChanged: onLibraryRefresh),
                ),
                const Spacer(),
                if (task.bestLibraryPath != null)
                  GlassButton(
                    quality: AniGlassTheme.quality,
                    settings: AniGlassTheme.chromeFor(context),
                    icon: const Icon(Icons.play_arrow_rounded),
                    onTap: () {
                      Navigator.of(context).push(
                        AniScalePageRoute(
                          page: PlayerScreen(
                            videoPath: task.bestLibraryPath!,
                            title: title,
                          ),
                        ),
                      );
                    },
                  ),
                const SizedBox(width: 8),
                GlassButton(
                  quality: AniGlassTheme.quality,
                  settings: AniGlassTheme.chromeFor(context),
                  icon: const Icon(Icons.delete_outline_rounded),
                  onTap: () => TorrentService().remove(task.id),
                ),
              ],
            ),
          ],
        ),
      ),
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
