import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'package:anivault/services/anime_library_service.dart';
import 'package:anivault/ui/player_screen.dart';

class AnimeSeriesScreen extends StatelessWidget {
  final AnimeSeries series;

  const AnimeSeriesScreen({super.key, required this.series});

  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
      background: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0C0720), // Deep blue space
              Color(0xFF1B0C30), // Deep purple space
              Color(0xFF000000), // Pure black
            ],
          ),
        ),
      ),
      statusBarStyle: GlassStatusBarStyle.auto,
      appBar: GlassAppBar(
        backgroundColor: Colors.transparent,
        title: Text(
          series.title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        leading: GlassButton(
          shape: const LiquidRoundedSuperellipse(borderRadius: 12),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onTap: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          _HeaderDetails(series: series),
          const SizedBox(height: 16),
          ...series.episodes.map((episode) => _EpisodeBlock(episode: episode)),
        ],
      ),
    );
  }
}

class _HeaderDetails extends StatelessWidget {
  final AnimeSeries series;

  const _HeaderDetails({required this.series});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      shape: const LiquidRoundedSuperellipse(borderRadius: 16),
      child: Row(
        children: [
          _Cover(series: series, size: 72),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  series.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${series.episodes.length} episodes  -  ${series.fileCount} files',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  final AnimeSeries series;
  final double size;

  const _Cover({required this.series, required this.size});

  @override
  Widget build(BuildContext context) {
    final coverUrl = series.coverUrl;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: size,
        height: size,
        color: const Color(0xFF191919),
        child: coverUrl == null
            ? Center(
                child: Icon(
                  series.isUnknown
                      ? Icons.help_outline_rounded
                      : Icons.movie_creation_outlined,
                  color: Colors.white54,
                ),
              )
            : Image.network(
                coverUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return const Center(
                    child: Icon(
                      Icons.movie_creation_outlined,
                      color: Colors.white54,
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _EpisodeBlock extends StatelessWidget {
  final AnimeEpisodeGroup episode;

  const _EpisodeBlock({required this.episode});

  @override
  Widget build(BuildContext context) {
    final files = episode.files;
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 14),
      padding: EdgeInsets.zero,
      shape: const LiquidRoundedSuperellipse(borderRadius: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    episode.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
                if (files.length > 1)
                  Text(
                    '${files.length} versions',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                  ),
              ],
            ),
          ),
          for (int i = 0; i < files.length; i++)
            GlassListTile(
              isLast: i == files.length - 1,
              leading: const Icon(Icons.play_arrow_rounded, color: Colors.white70),
              title: Text(
                files[i].fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
              ),
              subtitle: Text(
                [
                  if (files[i].releaseGroup != null) files[i].releaseGroup,
                  if (files[i].resolution != null) files[i].resolution,
                  files[i].path,
                ].join('  -  '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
              ),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PlayerScreen(
                      videoPath: files[i].path,
                      title: files[i].fileName,
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
