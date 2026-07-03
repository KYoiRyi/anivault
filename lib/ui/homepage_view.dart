import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:anivault/services/anime_library_service.dart';
import 'package:anivault/services/home_insights_service.dart';
import 'package:anivault/services/watch_history_service.dart';
import 'package:anivault/ui/ani_glass_theme.dart';
import 'package:anivault/ui/player_screen.dart';
import 'package:anivault/ui/page_transition.dart';

class HomepageView extends StatefulWidget {
  final double topPadding;
  final ScrollController? scrollController;
  final ValueChanged<int> onNavigateToLibrary;

  const HomepageView({
    super.key,
    required this.topPadding,
    this.scrollController,
    required this.onNavigateToLibrary,
  });

  @override
  State<HomepageView> createState() => _HomepageViewState();
}

class _HomepageViewState extends State<HomepageView> {
  @override
  void initState() {
    super.initState();
    WatchHistoryService().initialize();
    HomeInsightsService().initialize();
  }

  @override
  Widget build(BuildContext context) {
    final textColor = AniGlassTheme.textColor(context);
    final secondary = AniGlassTheme.secondaryTextColor(context);

    return ListenableBuilder(
      listenable: Listenable.merge([
        WatchHistoryService(),
        AnimeLibraryService(),
        HomeInsightsService(),
      ]),
      builder: (context, _) {
        final lastRecord = WatchHistoryService().getLastWatchedRecord();
        AnimeSeries? lastSeries;
        AnimeEpisodeGroup? lastEpisode;
        AnimeMediaFile? lastFile;
        int remainingCount = 0;
        bool isCompleted = false;

        if (lastRecord != null) {
          lastSeries = AnimeLibraryService().series.firstWhereOrNull(
            (s) => s.id == lastRecord.seriesId,
          );
          if (lastSeries != null) {
            // Find the episode
            final epIndex = lastSeries.episodes.indexWhere(
              (e) => e.number == lastRecord.episodeNumber,
            );
            if (epIndex != -1) {
              lastEpisode = lastSeries.episodes[epIndex];
              remainingCount = lastSeries.episodes.length - epIndex;
              if (lastRecord.progressRatio > 0.9) {
                remainingCount -= 1;
                if (epIndex == lastSeries.episodes.length - 1) {
                  isCompleted = true;
                }
              }
              // Find the file
              if (lastEpisode.files.isNotEmpty) {
                lastFile = lastEpisode.files.firstWhere(
                  (f) => f.path == lastRecord.videoPath,
                  orElse: () => lastEpisode!.files.first,
                );
              }
            }
          }
        }

        final stats = WatchHistoryService().getWeeklyStats();

        return CustomScrollView(
          controller: widget.scrollController,
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(20, widget.topPadding + 76, 20, 16),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildContinueWatchingHeader(textColor),
                    const SizedBox(height: 12),
                    if (lastRecord != null &&
                        lastSeries != null &&
                        lastEpisode != null &&
                        lastFile != null)
                      _buildContinueWatchingCard(
                        context,
                        lastRecord,
                        lastSeries,
                        lastEpisode,
                        lastFile,
                        remainingCount,
                        isCompleted,
                        textColor,
                        secondary,
                      )
                    else
                      _buildEmptyContinueWatchingCard(
                        context,
                        textColor,
                        secondary,
                      ),
                    const SizedBox(height: 28),
                    _buildWeeklyProgressHeader(textColor),
                    const SizedBox(height: 12),
                    _buildWeeklyProgressCard(
                      context,
                      stats,
                      textColor,
                      secondary,
                    ),
                    const SizedBox(height: 28),
                    _buildTodayUpdatesSection(context, textColor, secondary),
                    const SizedBox(height: 28),
                    _buildSeasonProgressSection(context, textColor, secondary),
                    const SizedBox(height: 28),
                    _buildRecommendationsSection(context, textColor, secondary),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildContinueWatchingHeader(Color textColor) {
    return Text(
      '今日继续观看',
      style: TextStyle(
        color: textColor,
        fontSize: 20,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
      ),
    );
  }

  Widget _buildContinueWatchingCard(
    BuildContext context,
    WatchRecord record,
    AnimeSeries series,
    AnimeEpisodeGroup episode,
    AnimeMediaFile file,
    int remainingCount,
    bool isCompleted,
    Color textColor,
    Color secondary,
  ) {
    final progressPct = (record.progressRatio * 100).toInt();
    final remainingText = isCompleted
        ? '已看完本季！🎉'
        : '距离看完本季还有 $remainingCount 集';

    return GlassCard(
      quality: GlassQuality.premium,
      useOwnLayer: true,
      settings: AniGlassTheme.heroFor(context),
      padding: const EdgeInsets.all(18),
      shape: const LiquidRoundedSuperellipse(borderRadius: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Cover art
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  width: 80,
                  height: 112,
                  child: series.coverUrl != null
                      ? Image.network(
                          series.coverUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              _buildFallbackCover(series),
                        )
                      : _buildFallbackCover(series),
                ),
              ),
              const SizedBox(width: 16),
              // Series details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      series.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      episode.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: secondary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Progress bar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: record.progressRatio,
                        minHeight: 6,
                        backgroundColor: textColor.withValues(alpha: 0.12),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          const Color(0xFF0EA5E9), // Light sky blue
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '已播放 $progressPct%',
                          style: TextStyle(
                            color: secondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          '${_formatDuration(record.progressMs)} / ${_formatDuration(record.durationMs)}',
                          style: TextStyle(
                            color: secondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          // Atmospheric tip bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: textColor.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: textColor.withValues(alpha: 0.08)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.auto_awesome_rounded,
                  color: const Color(0xFF0EA5E9),
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        remainingText,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '上次观看于 ${_formatFriendlyTime(record.timestamp)}',
                        style: TextStyle(color: secondary, fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // Action button
          GlassButton.custom(
            quality: GlassQuality.premium,
            settings: AniGlassTheme.chromeFor(context),
            height: 48,
            shape: const LiquidRoundedSuperellipse(borderRadius: 14),
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
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.play_arrow_rounded, color: textColor),
                const SizedBox(width: 8),
                Text(
                  '继续观看',
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyContinueWatchingCard(
    BuildContext context,
    Color textColor,
    Color secondary,
  ) {
    return GlassCard(
      quality: GlassQuality.premium,
      useOwnLayer: true,
      settings: AniGlassTheme.heroFor(context),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 26),
      shape: const LiquidRoundedSuperellipse(borderRadius: 26),
      child: Column(
        children: [
          Icon(
            Icons.movie_creation_outlined,
            size: 48,
            color: textColor.withValues(alpha: 0.36),
          ),
          const SizedBox(height: 16),
          Text(
            '开始您的漫游之旅',
            style: TextStyle(
              color: textColor,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '在媒体库中选择一部动画或导入本地视频文件，您最近的播放记录与本季进度将自动展示在此处。',
            textAlign: TextAlign.center,
            style: TextStyle(color: secondary, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 20),
          GlassButton.custom(
            quality: GlassQuality.premium,
            settings: AniGlassTheme.chromeFor(context),
            height: 44,
            width: 150,
            shape: const LiquidRoundedSuperellipse(borderRadius: 12),
            onTap: () =>
                widget.onNavigateToLibrary(1), // index 1 is Library tab
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.video_library_rounded, size: 16, color: textColor),
                const SizedBox(width: 8),
                Text(
                  '前往媒体库',
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeeklyProgressHeader(Color textColor) {
    return Text(
      '本周追番进度',
      style: TextStyle(
        color: textColor,
        fontSize: 20,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
      ),
    );
  }

  Widget _buildWeeklyProgressCard(
    BuildContext context,
    WatchWeeklyStats stats,
    Color textColor,
    Color secondary,
  ) {
    final comparisonText = stats.changePercentage >= 0
        ? '超过上周 ${stats.changePercentage.toInt()}%'
        : '少于上周 ${stats.changePercentage.abs().toInt()}%';

    final formattedDuration = _formatHoursMins(stats.watchDuration);

    // Goal calculation (Target: 10 episodes or 5 hours. Let's make it 10 episodes).
    final double progress = (stats.episodesWatched / 10.0).clamp(0.0, 1.0);

    return GlassCard(
      quality: GlassQuality.premium,
      useOwnLayer: true,
      settings: AniGlassTheme.heroFor(context),
      padding: const EdgeInsets.all(22),
      shape: const LiquidRoundedSuperellipse(borderRadius: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // Radial Ring
              SizedBox(
                width: 90,
                height: 90,
                child: CustomPaint(
                  painter: RadialProgressPainter(
                    progress: progress,
                    color: const Color(0xFF0EA5E9),
                    backgroundColor: textColor.withValues(alpha: 0.08),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${stats.episodesWatched}',
                          style: TextStyle(
                            color: textColor,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          '集',
                          style: TextStyle(
                            color: secondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 24),
              // Quick Stats List
              Expanded(
                child: Column(
                  children: [
                    _buildStatRow(
                      Icons.schedule_rounded,
                      '总时长',
                      formattedDuration,
                      textColor,
                    ),
                    const SizedBox(height: 8),
                    _buildStatRow(
                      Icons.local_fire_department_rounded,
                      '连续观看',
                      '${stats.consecutiveDays} 天',
                      textColor,
                    ),
                    const SizedBox(height: 8),
                    _buildStatRow(
                      Icons.emoji_events_rounded,
                      '已完结番',
                      '${stats.completedSeriesCount} 部',
                      textColor,
                    ),
                    const SizedBox(height: 8),
                    _buildStatRow(
                      Icons.trending_up_rounded,
                      '对比上周',
                      comparisonText,
                      const Color(0xFF0EA5E9),
                      isAccent: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Narrative message
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: textColor.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: textColor.withValues(alpha: 0.05)),
            ),
            child: Text(
              stats.narrative,
              style: TextStyle(
                color: secondary,
                fontSize: 13,
                height: 1.45,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(
    IconData icon,
    String label,
    String value,
    Color valueColor, {
    bool isAccent = false,
  }) {
    return Row(
      children: [
        Icon(
          icon,
          size: 16,
          color: isAccent
              ? valueColor
              : AniGlassTheme.secondaryTextColor(context),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: AniGlassTheme.secondaryTextColor(context),
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildTodayUpdatesSection(
    BuildContext context,
    Color textColor,
    Color secondary,
  ) {
    final service = HomeInsightsService();
    final updates = service.todayUpdates;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionTitle(
          '今日更新',
          service.refreshing ? '正在后台刷新' : _refreshLabel(service.lastRefresh),
          textColor,
          secondary,
        ),
        const SizedBox(height: 12),
        if (updates.isEmpty)
          _buildInsightEmptyCard(context, '今天还没有抓到更新情报', textColor, secondary)
        else
          SizedBox(
            height: 174,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: updates.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final item = updates[index];
                return _TodayUpdateTile(
                  item: item,
                  textColor: textColor,
                  secondary: secondary,
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildSeasonProgressSection(
    BuildContext context,
    Color textColor,
    Color secondary,
  ) {
    final progress = HomeInsightsService().seasonProgress;
    final seasonName = _seasonName(DateTime.now().month);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionTitle('$seasonName追番进度', '来自本地媒体库', textColor, secondary),
        const SizedBox(height: 12),
        if (progress.isEmpty)
          _buildInsightEmptyCard(
            context,
            '本季度番剧会在入库并识别后显示进度',
            textColor,
            secondary,
          )
        else
          GlassCard(
            quality: GlassQuality.premium,
            useOwnLayer: true,
            settings: AniGlassTheme.heroFor(context),
            padding: const EdgeInsets.all(16),
            shape: const LiquidRoundedSuperellipse(borderRadius: 24),
            child: Column(
              children: [
                for (final item in progress.take(4)) ...[
                  _SeasonProgressRow(
                    item: item,
                    textColor: textColor,
                    secondary: secondary,
                  ),
                  if (item != progress.take(4).last)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Divider(
                        height: 1,
                        color: textColor.withValues(alpha: 0.08),
                      ),
                    ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildRecommendationsSection(
    BuildContext context,
    Color textColor,
    Color secondary,
  ) {
    final recommendations = HomeInsightsService().recommendations;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionTitle('新番推荐', 'AniList + AI Agent', textColor, secondary),
        const SizedBox(height: 12),
        if (recommendations.isEmpty)
          _buildInsightEmptyCard(
            context,
            '后台会自动拉取本季新番并生成推荐理由',
            textColor,
            secondary,
          )
        else
          SizedBox(
            height: 316,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: recommendations.length,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (context, index) {
                return _RecommendationTile(
                  item: recommendations[index],
                  textColor: textColor,
                  secondary: secondary,
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildSectionTitle(
    String title,
    String subtitle,
    Color textColor,
    Color secondary,
  ) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: textColor,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
        ),
        Text(
          subtitle,
          style: TextStyle(
            color: secondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildInsightEmptyCard(
    BuildContext context,
    String message,
    Color textColor,
    Color secondary,
  ) {
    return GlassCard(
      quality: GlassQuality.premium,
      useOwnLayer: true,
      settings: AniGlassTheme.heroFor(context),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      shape: const LiquidRoundedSuperellipse(borderRadius: 22),
      child: Row(
        children: [
          Icon(
            Icons.auto_awesome_rounded,
            color: textColor.withValues(alpha: 0.6),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: secondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _refreshLabel(DateTime? value) {
    if (value == null) return '等待刷新';
    final diff = DateTime.now().difference(value);
    if (diff.inMinutes < 1) return '刚刚更新';
    if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
    return '${diff.inHours} 小时前';
  }

  String _seasonName(int month) {
    if (month <= 3) return '冬季';
    if (month <= 6) return '春季';
    if (month <= 9) return '夏季';
    return '秋季';
  }

  Widget _buildFallbackCover(AnimeSeries series) {
    return Container(
      color: Colors.white.withValues(alpha: 0.05),
      child: Center(
        child: Icon(
          series.isUnknown
              ? Icons.help_outline_rounded
              : Icons.movie_filter_rounded,
          color: Colors.white38,
          size: 32,
        ),
      ),
    );
  }

  String _formatFriendlyTime(int timestamp) {
    final now = DateTime.now();
    final time = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final diff = now.difference(time);

    final String timeStr =
        '${time.hour}:${time.minute.toString().padLeft(2, '0')}';

    if (diff.inMinutes < 1) {
      return '刚刚';
    } else if (diff.inHours < 1) {
      return '${diff.inMinutes} 分钟前';
    } else if (diff.inDays < 1 && now.day == time.day) {
      return '今天 $timeStr';
    } else if (diff.inDays <= 2 &&
        now.subtract(const Duration(days: 1)).day == time.day) {
      return '昨晚 $timeStr';
    } else if (diff.inDays <= 3 &&
        now.subtract(const Duration(days: 2)).day == time.day) {
      return '前天 $timeStr';
    } else {
      return '${time.month}月${time.day}日 $timeStr';
    }
  }

  String _formatDuration(int ms) {
    final s = ms ~/ 1000;
    final m = s ~/ 60;
    final rS = s % 60;
    return '$m:${rS.toString().padLeft(2, '0')}';
  }

  String _formatHoursMins(Duration d) {
    final minutes = d.inMinutes;
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h > 0) {
      return '$h 小时 $m 分';
    }
    return '$m 分钟';
  }
}

class RadialProgressPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color backgroundColor;

  RadialProgressPainter({
    required this.progress,
    required this.color,
    required this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 6;

    final bgPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7;

    final progressPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;

    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.24)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 11
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);

    canvas.drawCircle(center, radius, bgPaint);

    if (progress > 0) {
      final sweepAngle = 2 * math.pi * progress;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        sweepAngle,
        false,
        glowPaint,
      );
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        sweepAngle,
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant RadialProgressPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.backgroundColor != backgroundColor;
  }
}

class _TodayUpdateTile extends StatelessWidget {
  final SeasonalAnimeItem item;
  final Color textColor;
  final Color secondary;

  const _TodayUpdateTile({
    required this.item,
    required this.textColor,
    required this.secondary,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 280,
      child: GlassCard(
        quality: GlassQuality.premium,
        useOwnLayer: true,
        settings: AniGlassTheme.heroFor(context),
        padding: const EdgeInsets.all(14),
        shape: const LiquidRoundedSuperellipse(borderRadius: 22),
        child: Row(
          children: [
            _Poster(url: item.coverUrl, width: 78, height: 118),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      height: 1.12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    item.nextEpisode == null
                        ? '今日放送'
                        : '第 ${item.nextEpisode} 集更新',
                    style: TextStyle(
                      color: secondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _timeLabel(item.airingAt),
                    style: TextStyle(color: secondary, fontSize: 12),
                  ),
                  const Spacer(),
                  _TagWrap(
                    tags: [...item.genres, ...item.tags].take(3).toList(),
                    textColor: textColor,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _timeLabel(DateTime? time) {
    if (time == null) return '时间待定';
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}

class _SeasonProgressRow extends StatelessWidget {
  final SeasonalProgressItem item;
  final Color textColor;
  final Color secondary;

  const _SeasonProgressRow({
    required this.item,
    required this.textColor,
    required this.secondary,
  });

  @override
  Widget build(BuildContext context) {
    final pct = (item.progress * 100).round();
    return Row(
      children: [
        _Poster(url: item.series.coverUrl, width: 48, height: 64),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.series.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: LinearProgressIndicator(
                  value: item.progress,
                  minHeight: 7,
                  backgroundColor: textColor.withValues(alpha: 0.10),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    Color(0xFF38BDF8),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(
          '${item.watchedEpisodes}/${item.totalEpisodes} · $pct%',
          style: TextStyle(
            color: secondary,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _RecommendationTile extends StatelessWidget {
  final SeasonalAnimeItem item;
  final Color textColor;
  final Color secondary;

  const _RecommendationTile({
    required this.item,
    required this.textColor,
    required this.secondary,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 218,
      child: GlassCard(
        quality: GlassQuality.premium,
        useOwnLayer: true,
        settings: AniGlassTheme.heroFor(context),
        padding: EdgeInsets.zero,
        shape: const LiquidRoundedSuperellipse(borderRadius: 24),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 142,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _Poster(url: item.coverUrl, width: 218, height: 142),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Color(0xAA000000)],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 10,
                      child: _TagWrap(
                        tags: [...item.genres, ...item.tags].take(3).toList(),
                        textColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        height: 1.12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      item.averageScore == null
                          ? '本季新番'
                          : 'AniList ${item.averageScore}/100',
                      style: TextStyle(
                        color: secondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      item.reason,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: secondary,
                        fontSize: 12,
                        height: 1.36,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Poster extends StatelessWidget {
  final String? url;
  final double width;
  final double height;

  const _Poster({required this.url, required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: width,
        height: height,
        child: url == null
            ? const ColoredBox(
                color: Color(0xFF111827),
                child: Icon(Icons.movie_filter_rounded, color: Colors.white54),
              )
            : Image.network(
                url!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const ColoredBox(
                  color: Color(0xFF111827),
                  child: Icon(
                    Icons.movie_filter_rounded,
                    color: Colors.white54,
                  ),
                ),
              ),
      ),
    );
  }
}

class _TagWrap extends StatelessWidget {
  final List<String> tags;
  final Color textColor;

  const _TagWrap({required this.tags, required this.textColor});

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final tag in tags.take(3))
          DecoratedBox(
            decoration: BoxDecoration(
              color: textColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: textColor.withValues(alpha: 0.14)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                _localizedTag(tag),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: textColor,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
      ],
    );
  }

  String _localizedTag(String tag) {
    return switch (tag) {
      'Romance' => '纯爱',
      'Fantasy' => '奇幻',
      'Isekai' => '异世界',
      'Comedy' => '喜剧',
      'Drama' => '剧情',
      'Action' => '动作',
      'Slice of Life' => '日常',
      'Music' => '音乐',
      'Supernatural' => '超自然',
      'School' => '校园',
      _ => tag,
    };
  }
}

// Helper extension to mimic collection packages firstWhereOrNull
extension _FirstWhereOrNull<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T element) test) {
    for (var element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}
