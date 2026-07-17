import 'dart:convert';
import 'dart:io';

import 'package:html/parser.dart' as html_parser;

class DmhySearchResult {
  final String title;
  final String category;
  final String publishedAt;
  final String size;
  final String publisher;
  final Uri detailsUrl;
  final String magnetUri;

  const DmhySearchResult({
    required this.title,
    required this.category,
    required this.publishedAt,
    required this.size,
    required this.publisher,
    required this.detailsUrl,
    required this.magnetUri,
  });
}

class DmhySearchPage {
  final List<DmhySearchResult> results;
  final bool hasNextPage;

  const DmhySearchPage({required this.results, required this.hasNextPage});
}

class DmhySearchService {
  static final DmhySearchService _instance = DmhySearchService._internal();
  factory DmhySearchService() => _instance;
  DmhySearchService._internal();

  static final Uri _origin = Uri.parse('https://dmhy.org');

  Future<DmhySearchPage> search(String keyword, {int page = 1}) async {
    final query = keyword.trim();
    if (query.isEmpty) {
      return const DmhySearchPage(results: [], hasNextPage: false);
    }
    if (page < 1) throw ArgumentError.value(page, 'page', 'must be positive');

    final path = page == 1 ? '/topics/list' : '/topics/list/page/$page';
    final uri = _origin.replace(
      path: path,
      queryParameters: {'keyword': query},
    );
    final client = HttpClient();
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 12));
      request.headers.set(HttpHeaders.userAgentHeader, 'AniVault/1.0');
      request.headers.set(
        HttpHeaders.acceptHeader,
        'text/html,application/xhtml+xml',
      );
      final response = await request.close().timeout(
        const Duration(seconds: 12),
      );
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'DMHY search returned HTTP ${response.statusCode}',
          uri: uri,
        );
      }
      final body = await utf8.decoder.bind(response).join();
      return parse(body);
    } finally {
      client.close(force: true);
    }
  }

  static DmhySearchPage parse(String source) {
    final document = html_parser.parse(source);
    final results = <DmhySearchResult>[];
    for (final row in document.querySelectorAll('table.tablesorter tr')) {
      final cells = row.querySelectorAll('td');
      final titleLink = row.querySelector('td.title a[href^="/topics/view/"]');
      final magnetLink = row.querySelector('a.arrow-magnet[href^="magnet:"]');
      if (cells.length < 5 || titleLink == null || magnetLink == null) continue;

      final detailsHref = titleLink.attributes['href'];
      final magnet = magnetLink.attributes['href'];
      if (detailsHref == null || magnet == null || magnet.isEmpty) continue;
      final published = cells.first.text.trim();
      results.add(
        DmhySearchResult(
          title: _compact(titleLink.text),
          category: _compact(cells[1].text),
          publishedAt: published.length >= 16
              ? published.substring(0, 16)
              : published,
          size: _compact(cells[4].text),
          publisher: _compact(cells.last.text),
          detailsUrl: _origin.resolve(detailsHref),
          magnetUri: magnet,
        ),
      );
    }
    final hasNext = document
        .querySelectorAll('a[href*="/topics/list/page/"]')
        .any((link) => link.text.trim() == '下一頁');
    return DmhySearchPage(results: results, hasNextPage: hasNext);
  }

  static String _compact(String value) =>
      value.replaceAll(RegExp(r'\s+'), ' ').trim();
}
