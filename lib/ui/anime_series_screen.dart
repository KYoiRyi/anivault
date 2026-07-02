import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'package:anivault/services/anime_library_service.dart';
import 'package:anivault/services/theme_service.dart';
import 'package:anivault/ui/ani_glass_theme.dart';
import 'package:anivault/ui/page_transition.dart';
import 'package:anivault/ui/player_screen.dart';

class AnimeSeriesScreen extends StatefulWidget {
  final AnimeSeries series;
  final Future<void> Function(List<AnimeSeries> series)? onDeleteSeries;

  const AnimeSeriesScreen({
    super.key,
    required this.series,
    this.onDeleteSeries,
  });

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

  Future<void> _deleteSeries() async {
    await widget.onDeleteSeries?.call([widget.series]);
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final series = widget.series;
    final light = Theme.of(context).brightness == Brightness.light;
    return GlassScaffold(
      background: AniGlassTheme.background(
        coverUrl: series.coverUrl,
        light: light,
        style: ThemeService().backgroundStyle,
      ),
      statusBarStyle: light
          ? GlassStatusBarStyle.dark
          : GlassStatusBarStyle.light,
      settings: AniGlassTheme.chromeFor(context),
      headerScrollController: _scrollController,
      headerFadeDistance: 54,
      appBar: GlassAppBar(
        title: Text(series.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        leading: GlassButton(
          quality: GlassQuality.premium,
          settings: AniGlassTheme.chromeFor(context),
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onTap: () => Navigator.pop(context),
        ),
        actions: widget.onDeleteSeries == null
            ? null
            : [
                GlassMenu(
                  settings: AniGlassTheme.chromeFor(context),
                  quality: GlassQuality.premium,
                  menuWidth: 220,
                  items: [
                    GlassMenuItem(
                      title: 'Delete',
                      icon: const Icon(Icons.delete_outline_rounded),
                      isDestructive: true,
                      onTap: _deleteSeries,
                    ),
                  ],
                  triggerBuilder: (context, toggle) => GlassButton(
                    quality: GlassQuality.premium,
                    settings: AniGlassTheme.chromeFor(context),
                    icon: const Icon(Icons.more_horiz_rounded),
                    onTap: toggle,
                  ),
                ),
              ],
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
                12,
              ),
              child: _SeriesHero(series: series),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
              child: _SeriesMetadataPanel(series: series),
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

class _SeriesMetadataPanel extends StatelessWidget {
  final AnimeSeries series;

  const _SeriesMetadataPanel({required this.series});

  @override
  Widget build(BuildContext context) {
    final hasDetails =
        series.scoreLabel != null ||
        series.startYear != null ||
        series.format != null ||
        series.status != null ||
        series.season != null ||
        series.duration != null ||
        series.genres.isNotEmpty ||
        series.description?.isNotEmpty == true;
    if (!hasDetails) return const SizedBox.shrink();

    final textColor = AniGlassTheme.textColor(context);
    final secondaryTextColor = AniGlassTheme.secondaryTextColor(context);
    return GlassCard(
      quality: GlassQuality.premium,
      useOwnLayer: true,
      settings: AniGlassTheme.heroFor(context),
      padding: const EdgeInsets.all(16),
      shape: const LiquidRoundedSuperellipse(borderRadius: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (series.scoreLabel != null)
                _MetaPill(
                  icon: Icons.star_rounded,
                  label: series.scoreLabel!,
                  accent: const Color(0xFFF59E0B),
                ),
              if (series.startYear != null)
                _MetaPill(
                  icon: Icons.calendar_today_rounded,
                  label: '${series.startYear}',
                ),
              if (series.format != null)
                _MetaPill(
                  icon: Icons.movie_filter_rounded,
                  label: _prettyEnum(series.format!),
                ),
              if (series.status != null)
                _MetaPill(
                  icon: Icons.radio_button_checked_rounded,
                  label: _prettyEnum(series.status!),
                ),
              if (series.season != null)
                _MetaPill(
                  icon: Icons.wb_sunny_rounded,
                  label: _prettyEnum(series.season!),
                ),
              if (series.duration != null)
                _MetaPill(
                  icon: Icons.schedule_rounded,
                  label: '${series.duration} min',
                ),
            ],
          ),
          if (series.genres.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final genre in series.genres.take(8))
                  _GenreChip(label: genre),
              ],
            ),
          ],
          if (series.description?.isNotEmpty == true) ...[
            const SizedBox(height: 14),
            Text(
              'Synopsis',
              style: TextStyle(
                color: textColor,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              series.description!,
              maxLines: 7,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: secondaryTextColor,
                height: 1.36,
                fontSize: 13,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? accent;

  const _MetaPill({required this.icon, required this.label, this.accent});

  @override
  Widget build(BuildContext context) {
    final textColor = AniGlassTheme.textColor(context);
    final color = accent ?? textColor;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 15),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: textColor,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GenreChip extends StatelessWidget {
  final String label;

  const _GenreChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return GlassChip(
      quality: GlassQuality.premium,
      settings: AniGlassTheme.chromeFor(context),
      label: label,
      labelStyle: TextStyle(
        color: AniGlassTheme.textColor(context),
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _SeriesHero extends StatelessWidget {
  final AnimeSeries series;

  const _SeriesHero({required this.series});

  @override
  Widget build(BuildContext context) {
    final textColor = AniGlassTheme.textColor(context);
    final secondaryTextColor = AniGlassTheme.secondaryTextColor(context);
    return GlassCard(
      quality: GlassQuality.premium,
      useOwnLayer: true,
      settings: AniGlassTheme.heroFor(context),
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
                    child: _UnknownBadge(label: 'Unknown match'),
                  ),
                Text(
                  series.title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    height: 1.02,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '${series.episodes.length} episodes  -  ${series.fileCount} files',
                  style: TextStyle(color: secondaryTextColor),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UnknownBadge extends StatelessWidget {
  final String label;

  const _UnknownBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    final textColor = AniGlassTheme.textColor(context);
    final borderColor = AniGlassTheme.subtleBorderColor(context);
    final backgroundColor = AniGlassTheme.isLight(context)
        ? Colors.white.withValues(alpha: 0.54)
        : Colors.black.withValues(alpha: 0.34);
    return Align(
      alignment: Alignment.centerLeft,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          child: Text(
            label,
            style: TextStyle(
              color: textColor,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
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
    final textColor = AniGlassTheme.textColor(context);
    final tertiaryTextColor = AniGlassTheme.tertiaryTextColor(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AniGlassTheme.subtleBorderColor(context)),
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
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
                if (files.length > 1)
                  Text(
                    '${files.length} versions',
                    style: TextStyle(color: tertiaryTextColor, fontSize: 12),
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
    final textColor = AniGlassTheme.textColor(context);
    final tertiaryTextColor = AniGlassTheme.tertiaryTextColor(context);
    final subtitle = [
      if (file.releaseGroup != null) file.releaseGroup,
      if (file.resolution != null) file.resolution,
      file.path,
    ].join('  -  ');

    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          AniScalePageRoute(
            page: PlayerScreen(videoPath: file.path, title: file.fileName),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        child: Row(
          children: [
            GlassButton(
              quality: GlassQuality.premium,
              settings: AniGlassTheme.chromeFor(context),
              width: 36,
              height: 36,
              icon: const Icon(Icons.play_arrow_rounded, size: 22),
              onTap: () {
                Navigator.of(context).push(
                  AniScalePageRoute(
                    page: PlayerScreen(
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
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: tertiaryTextColor, fontSize: 12),
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

String _prettyEnum(String value) {
  return value
      .split('_')
      .where((part) => part.isNotEmpty)
      .map(
        (part) => part.length == 1
            ? part.toUpperCase()
            : '${part[0]}${part.substring(1).toLowerCase()}',
      )
      .join(' ');
}

extension _AnimeSeriesDisplay on AnimeSeries {
  String? get scoreLabel {
    final score = averageScore ?? meanScore;
    return score == null ? null : '$score%';
  }
}
