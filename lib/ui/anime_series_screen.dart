import 'package:flutter/material.dart';

import 'package:anivault/services/anime_library_service.dart';
import 'package:anivault/ui/player_screen.dart';

class AnimeSeriesScreen extends StatelessWidget {
  final AnimeSeries series;

  const AnimeSeriesScreen({super.key, required this.series});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(series: series),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                itemCount: series.episodes.length,
                itemBuilder: (context, index) {
                  final episode = series.episodes[index];
                  return _EpisodeBlock(episode: episode);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final AnimeSeries series;

  const _Header({required this.series});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 20, 16),
      decoration: BoxDecoration(
        color: Colors.black,
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
          ),
          const SizedBox(width: 4),
          _Cover(series: series, size: 72),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  series.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${series.episodes.length} episodes  -  ${series.fileCount} files',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.54)),
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
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
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
                    ),
                  ),
                ),
                if (episode.files.length > 1)
                  Text(
                    '${episode.files.length} versions',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.52),
                    ),
                  ),
              ],
            ),
          ),
          for (final file in episode.files)
            ListTile(
              leading: const Icon(Icons.play_arrow_rounded),
              title: Text(
                file.fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                [
                  if (file.releaseGroup != null) file.releaseGroup,
                  if (file.resolution != null) file.resolution,
                  file.path,
                ].join('  -  '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.45)),
              ),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PlayerScreen(
                      videoPath: file.path,
                      title: file.fileName,
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
