import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'package:anivault/services/anime_library_service.dart';
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
    _scrollController = ScrollController(initialScrollOffset: 0);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final series = widget.series;
    final topSpacer = MediaQuery.paddingOf(context).top + 44 + 8;

    return GlassScaffold(
      extendBody: true,
      edgeFade: false,
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
        buttonSettings: _SeriesGlassSettings.button,
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
          glowColor: const Color(0xFF8FEAFF),
          glowOpacity: 0.45,
          glowBlurRadius: 16,
          interactionScale: 1.08,
          stretch: 0.7,
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onTap: () => Navigator.pop(context),
        ),
      ),
      body: CustomScrollView(
        controller: _scrollController,
        primary: false,
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(20, topSpacer, 20, 32),
            sliver: SliverList(
              delegate: SliverChildListDelegate.fixed([
                _HeaderDetails(series: series),
                const SizedBox(height: 16),
                ...series.episodes.map(
                  (episode) => _EpisodeBlock(episode: episode),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _SeriesGlassSettings {
  static const panel = LiquidGlassSettings(
    blur: 2,
    thickness: 34,
    glassColor: Colors.transparent,
    lightIntensity: 2.4,
    ambientStrength: 0,
    refractiveIndex: 1.54,
    chromaticAberration: 0.28,
    glowIntensity: 1.1,
    specularSharpness: GlassSpecularSharpness.sharp,
  );

  static const button = LiquidGlassSettings(
    blur: 0,
    thickness: 30,
    glassColor: Colors.transparent,
    lightIntensity: 2.8,
    ambientStrength: 0,
    refractiveIndex: 1.62,
    chromaticAberration: 0.42,
    glowIntensity: 1.3,
    specularSharpness: GlassSpecularSharpness.sharp,
  );
}

class _HeaderDetails extends StatelessWidget {
  final AnimeSeries series;

  const _HeaderDetails({required this.series});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      useOwnLayer: true,
      quality: GlassQuality.standard,
      settings: _SeriesGlassSettings.panel,
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
      useOwnLayer: true,
      quality: GlassQuality.standard,
      settings: _SeriesGlassSettings.panel,
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
          for (int i = 0; i < files.length; i++) ...[
            _EpisodeFileButton(file: files[i]),
            if (i != files.length - 1)
              Divider(
                height: 1,
                indent: 60,
                color: Colors.white.withValues(alpha: 0.08),
              ),
          ],
        ],
      ),
    );
  }
}

class _EpisodeFileButton extends StatelessWidget {
  final AnimeMediaFile file;

  const _EpisodeFileButton({required this.file});

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      if (file.releaseGroup != null) file.releaseGroup,
      if (file.resolution != null) file.resolution,
      file.path,
    ].join('  -  ');

    return GlassButton.custom(
      useOwnLayer: false,
      height: 72,
      settings: _SeriesGlassSettings.button,
      shape: const LiquidRoundedSuperellipse(borderRadius: 18),
      interactionScale: 1.025,
      stretch: 0.65,
      glowColor: const Color(0xFF8FEAFF),
      glowOpacity: 0.38,
      glowBlurRadius: 20,
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
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.play_arrow_rounded, color: Colors.white70),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w400,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 12,
                    ),
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
