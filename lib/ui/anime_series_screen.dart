import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'package:anivault/services/anime_library_service.dart';
import 'package:anivault/ui/ani_glass_theme.dart';
import 'package:anivault/ui/player_screen.dart';

class AnimeSeriesScreen extends StatefulWidget {
  final AnimeSeries series;

  const AnimeSeriesScreen({super.key, required this.series});

  @override
  State<AnimeSeriesScreen> createState() => _AnimeSeriesScreenState();
}

class _AnimeSeriesScreenState extends State<AnimeSeriesScreen> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final series = widget.series;
    return GlassScaffold(
      background: AniGlassTheme.background(
        coverUrl: series.coverUrl,
        light: false,
      ),
      statusBarStyle: GlassStatusBarStyle.light,
      settings: AniGlassTheme.chrome,
      headerScrollController: _scrollController,
      headerFadeDistance: 54,
      appBar: GlassAppBar(
        title: Text(series.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        leading: GlassButton(
          quality: GlassQuality.premium,
          settings: AniGlassTheme.chrome,
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onTap: () => Navigator.pop(context),
        ),
      ),
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                MediaQuery.paddingOf(context).top + 78,
                20,
                18,
              ),
              child: _SeriesHero(series: series),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
            sliver: SliverList.builder(
              itemCount: series.episodes.length,
              itemBuilder: (context, index) => AnimatedGlassEntrance(
                index: index,
                child: _EpisodeBlock(episode: series.episodes[index]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SeriesHero extends StatelessWidget {
  final AnimeSeries series;

  const _SeriesHero({required this.series});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      quality: GlassQuality.premium,
      useOwnLayer: true,
      settings: AniGlassTheme.hero,
      padding: const EdgeInsets.all(18),
      shape: const LiquidRoundedSuperellipse(borderRadius: 32),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: SizedBox(
              width: 104,
              height: 142,
              child: _Cover(series: series),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (series.isUnknown)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: GlassChip(
                      quality: GlassQuality.premium,
                      label: 'Unknown match',
                      selected: true,
                    ),
                  ),
                Text(
                  series.title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    height: 1.02,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '${series.episodes.length} episodes  -  ${series.fileCount} files',
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
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
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
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
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
                if (files.length > 1)
                  Text(
                    '${files.length} versions',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
              ],
            ),
          ),
          for (int i = 0; i < files.length; i++) ...[
            _EpisodeFileRow(file: files[i]),
            if (i != files.length - 1)
              const Divider(height: 1, indent: 58, color: Colors.white10),
          ],
        ],
      ),
    );
  }
}

class _EpisodeFileRow extends StatelessWidget {
  final AnimeMediaFile file;

  const _EpisodeFileRow({required this.file});

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      if (file.releaseGroup != null) file.releaseGroup,
      if (file.resolution != null) file.resolution,
      file.path,
    ].join('  -  ');

    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                PlayerScreen(videoPath: file.path, title: file.fileName),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        child: Row(
          children: [
            GlassButton(
              quality: GlassQuality.premium,
              settings: AniGlassTheme.chrome,
              width: 36,
              height: 36,
              icon: const Icon(Icons.play_arrow_rounded, size: 22),
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
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  final AnimeSeries series;

  const _Cover({required this.series});

  @override
  Widget build(BuildContext context) {
    final coverUrl = series.coverUrl;
    if (coverUrl != null) {
      return Image.network(
        coverUrl,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            _FallbackCover(series: series),
      );
    }
    return _FallbackCover(series: series);
  }
}

class _FallbackCover extends StatelessWidget {
  final AnimeSeries series;

  const _FallbackCover({required this.series});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF111827),
      child: Center(
        child: Icon(
          series.isUnknown
              ? Icons.help_outline_rounded
              : Icons.movie_creation_outlined,
          color: Colors.white54,
          size: 42,
        ),
      ),
    );
  }
}
