import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'package:anivault/services/dmhy_search_service.dart';
import 'package:anivault/services/dmhy_result_grouper.dart';
import 'package:anivault/services/dmhy_search_organizer.dart';
import 'package:anivault/services/ai_agent_service.dart';
import 'package:anivault/services/torrent_service.dart';
import 'package:anivault/ui/ani_glass_theme.dart';

class DmhySearchView extends StatefulWidget {
  final double topPadding;
  final ScrollController? scrollController;

  const DmhySearchView({
    super.key,
    required this.topPadding,
    this.scrollController,
  });

  @override
  State<DmhySearchView> createState() => _DmhySearchViewState();
}

class _DmhySearchViewState extends State<DmhySearchView> {
  final _queryController = TextEditingController();
  final _queuedMagnets = <String>{};
  List<DmhySearchResult> _rawResults = const [];
  List<DmhyAnimeGroup> _groups = const [];
  String _activeQuery = '';
  String? _error;
  int _page = 1;
  bool _hasNextPage = false;
  bool _loading = false;
  bool _loadingMore = false;

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _queryController.text.trim();
    if (query.isEmpty || _loading) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _activeQuery = query;
      _loading = true;
      _error = null;
      _page = 1;
    });
    try {
      final response = await DmhySearchService().search(query);
      if (!mounted) return;
      setState(() {
        _rawResults = response.results;
        _groups = DmhyResultGrouper().group(response.results);
        _hasNextPage = response.hasNextPage;
      });
      _refineInBackground(response.results, query);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasNextPage || _activeQuery.isEmpty) return;
    setState(() => _loadingMore = true);
    try {
      final nextPage = _page + 1;
      final response = await DmhySearchService().search(
        _activeQuery,
        page: nextPage,
      );
      final rawResults = [..._rawResults, ...response.results];
      if (!mounted) return;
      setState(() {
        _page = nextPage;
        _rawResults = rawResults;
        _groups = DmhyResultGrouper().group(rawResults);
        _hasNextPage = response.hasNextPage;
      });
      _refineInBackground(rawResults, _activeQuery);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _refineInBackground(
    Iterable<DmhySearchResult> results,
    String query,
  ) async {
    final groups = await DmhySearchOrganizer(
      canonicalResolver: AiAgentService().canonicalizeDmhyGroups,
    ).organize(results);
    if (!mounted || query != _activeQuery) return;
    setState(() => _groups = groups);
  }

  Future<void> _enqueue(DmhySearchResult result) async {
    if (_queuedMagnets.contains(result.magnetUri)) return;
    setState(() => _queuedMagnets.add(result.magnetUri));
    try {
      await TorrentService().addMagnet(result.magnetUri);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added to downloads: ${result.title}')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _queuedMagnets.remove(result.magnetUri));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to add download: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final textColor = AniGlassTheme.textColor(context);
    final secondary = AniGlassTheme.secondaryTextColor(context);
    return CustomScrollView(
      controller: widget.scrollController,
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(20, widget.topPadding, 20, 18),
          sliver: SliverToBoxAdapter(
            child: Row(
              children: [
                Expanded(
                  child: GlassCard(
                    quality: AniGlassTheme.quality,
                    useOwnLayer: true,
                    settings: AniGlassTheme.chromeFor(context),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    shape: const LiquidRoundedSuperellipse(borderRadius: 24),
                    child: TextField(
                      controller: _queryController,
                      textInputAction: TextInputAction.search,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: 'Search anime releases',
                        hintStyle: TextStyle(color: secondary),
                        icon: Icon(Icons.search_rounded, color: secondary),
                      ),
                      onSubmitted: (_) => _search(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Tooltip(
                  message: 'Search DMHY',
                  child: GlassButton(
                    quality: AniGlassTheme.quality,
                    settings: AniGlassTheme.chromeFor(context),
                    icon: Icon(
                      _loading ? Icons.hourglass_top_rounded : Icons.search,
                    ),
                    onTap: _search,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_error != null)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            sliver: SliverToBoxAdapter(
              child: Text(
                _error!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.redAccent),
              ),
            ),
          ),
        if (_loading)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: GlassProgressIndicator.circular()),
          )
        else if (_groups.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 100),
                child: Text(
                  _activeQuery.isEmpty
                      ? 'Search releases from DMHY'
                      : 'No matching releases',
                  style: TextStyle(color: secondary, fontSize: 16),
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
            sliver: SliverList.separated(
              itemCount: _groups.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final group = _groups[index];
                return _DmhyAnimeCard(
                  group: group,
                  queuedMagnets: _queuedMagnets,
                  onDownload: _enqueue,
                );
              },
            ),
          ),
        if (_hasNextPage && !_loading)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 130),
            sliver: SliverToBoxAdapter(
              child: GlassButton.custom(
                quality: AniGlassTheme.quality,
                settings: AniGlassTheme.chromeFor(context),
                shape: const LiquidRoundedSuperellipse(borderRadius: 22),
                onTap: _loadMore,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _loadingMore
                          ? Icons.hourglass_top_rounded
                          : Icons.expand_more_rounded,
                      color: textColor,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _loadingMore ? 'Loading' : 'Load more',
                      style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _DmhyAnimeCard extends StatelessWidget {
  final DmhyAnimeGroup group;
  final Set<String> queuedMagnets;
  final ValueChanged<DmhySearchResult> onDownload;

  const _DmhyAnimeCard({
    required this.group,
    required this.queuedMagnets,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = AniGlassTheme.textColor(context);
    return GlassCard(
      quality: AniGlassTheme.quality,
      useOwnLayer: true,
      settings: AniGlassTheme.chromeFor(context),
      padding: EdgeInsets.zero,
      shape: const LiquidRoundedSuperellipse(borderRadius: 22),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: PageStorageKey('anime-${group.normalizedTitle}'),
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          iconColor: textColor,
          collapsedIconColor: textColor,
          title: Text(
            group.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: textColor,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          subtitle: Text(
            '${group.seasons.length} season groups · ${group.releaseCount} releases',
            style: TextStyle(
              color: AniGlassTheme.secondaryTextColor(context),
              fontSize: 12,
            ),
          ),
          children: [
            for (final season in group.seasons)
              _SeasonExpansion(
                season: season,
                queuedMagnets: queuedMagnets,
                onDownload: onDownload,
              ),
          ],
        ),
      ),
    );
  }
}

class _SeasonExpansion extends StatelessWidget {
  final DmhySeasonGroup season;
  final Set<String> queuedMagnets;
  final ValueChanged<DmhySearchResult> onDownload;

  const _SeasonExpansion({
    required this.season,
    required this.queuedMagnets,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = AniGlassTheme.textColor(context);
    return ExpansionTile(
      key: PageStorageKey('season-${season.seasonNumber ?? 0}'),
      dense: true,
      tilePadding: const EdgeInsets.symmetric(horizontal: 8),
      childrenPadding: const EdgeInsets.only(left: 8),
      iconColor: textColor,
      collapsedIconColor: textColor,
      leading: Icon(Icons.video_library_rounded, color: textColor, size: 19),
      title: Text(
        season.seasonNumber == null
            ? 'Season not specified'
            : 'Season ${season.seasonNumber}',
        style: TextStyle(color: textColor, fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        '${season.episodes.length} episode groups',
        style: TextStyle(
          color: AniGlassTheme.secondaryTextColor(context),
          fontSize: 11,
        ),
      ),
      children: [
        for (final episode in season.episodes)
          _EpisodeExpansion(
            episode: episode,
            queuedMagnets: queuedMagnets,
            onDownload: onDownload,
          ),
      ],
    );
  }
}

class _EpisodeExpansion extends StatelessWidget {
  final DmhyEpisodeGroup episode;
  final Set<String> queuedMagnets;
  final ValueChanged<DmhySearchResult> onDownload;

  const _EpisodeExpansion({
    required this.episode,
    required this.queuedMagnets,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = AniGlassTheme.textColor(context);
    return ExpansionTile(
      key: PageStorageKey('episode-${episode.episodeNumber ?? 0}'),
      dense: true,
      tilePadding: const EdgeInsets.symmetric(horizontal: 8),
      childrenPadding: const EdgeInsets.only(left: 12),
      iconColor: textColor,
      collapsedIconColor: textColor,
      leading: Icon(Icons.movie_filter_rounded, color: textColor, size: 18),
      title: Text(
        episode.episodeNumber == null
            ? 'Specials / episode not specified'
            : 'Episode ${episode.episodeNumber}',
        style: TextStyle(color: textColor, fontWeight: FontWeight.w700),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${episode.releases.length}',
            style: TextStyle(
              color: AniGlassTheme.secondaryTextColor(context),
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 6),
          Icon(Icons.expand_more_rounded, color: textColor),
        ],
      ),
      children: [
        for (final release in episode.releases)
          _ReleaseRow(
            result: release,
            queued: queuedMagnets.contains(release.magnetUri),
            onDownload: () => onDownload(release),
          ),
      ],
    );
  }
}

class _ReleaseRow extends StatelessWidget {
  final DmhySearchResult result;
  final bool queued;
  final VoidCallback onDownload;

  const _ReleaseRow({
    required this.result,
    required this.queued,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = AniGlassTheme.textColor(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 0, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 10,
                  runSpacing: 5,
                  children: [
                    _Meta(
                      icon: Icons.schedule_rounded,
                      text: result.publishedAt,
                    ),
                    _Meta(icon: Icons.storage_rounded, text: result.size),
                    if (result.publisher.isNotEmpty)
                      _Meta(icon: Icons.group_rounded, text: result.publisher),
                  ],
                ),
              ],
            ),
          ),
          Tooltip(
            message: queued ? 'Added to downloads' : 'Add to downloads',
            child: IconButton(
              onPressed: queued ? null : onDownload,
              icon: Icon(
                queued ? Icons.download_done_rounded : Icons.download_rounded,
                color: queued ? Colors.greenAccent : textColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  final IconData icon;
  final String text;

  const _Meta({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final secondary = AniGlassTheme.secondaryTextColor(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: secondary),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(color: secondary, fontSize: 11)),
      ],
    );
  }
}
