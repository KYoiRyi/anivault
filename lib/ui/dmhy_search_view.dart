import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'package:anivault/services/dmhy_search_service.dart';
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
  List<DmhySearchResult> _results = const [];
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
        _results = response.results;
        _hasNextPage = response.hasNextPage;
      });
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
      if (!mounted) return;
      setState(() {
        _page = nextPage;
        _results = [..._results, ...response.results];
        _hasNextPage = response.hasNextPage;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
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
        else if (_results.isEmpty)
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
              itemCount: _results.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final result = _results[index];
                return _DmhyResultCard(
                  result: result,
                  queued: _queuedMagnets.contains(result.magnetUri),
                  onDownload: () => _enqueue(result),
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

class _DmhyResultCard extends StatelessWidget {
  final DmhySearchResult result;
  final bool queued;
  final VoidCallback onDownload;

  const _DmhyResultCard({
    required this.result,
    required this.queued,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = AniGlassTheme.textColor(context);
    return GlassCard(
      quality: AniGlassTheme.quality,
      useOwnLayer: true,
      settings: AniGlassTheme.chromeFor(context),
      padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
      shape: const LiquidRoundedSuperellipse(borderRadius: 22),
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
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  children: [
                    _Meta(icon: Icons.category_rounded, text: result.category),
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
          const SizedBox(width: 8),
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
