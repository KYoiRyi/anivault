import 'package:flutter_test/flutter_test.dart';

import 'package:anivault/services/dmhy_search_service.dart';

void main() {
  test('parses DMHY search rows and next-page navigation', () {
    const html = '''
      <table class="tablesorter"><tbody>
        <tr class="even">
          <td>2026/03/28 18:31 <span style="display:none">duplicate</span></td>
          <td><a>動畫</a></td>
          <td class="title">
            <a href="/topics/view/715756_example.html">[Group] 葬送的芙莉莲 &amp; Frieren - 37</a>
          </td>
          <td><a class="download-arrow arrow-magnet" href="magnet:?xt=urn:btih:ABC&amp;tr=https%3A%2F%2Ftracker.example">&nbsp;</a></td>
          <td>829.7MB</td><td>-</td><td>-</td><td>-</td><td><a>LoliHouse</a></td>
        </tr>
      </tbody></table>
      <a href="/topics/list/page/2?keyword=test">下一頁</a>
    ''';

    final page = DmhySearchService.parse(html);

    expect(page.hasNextPage, isTrue);
    expect(page.results, hasLength(1));
    final result = page.results.single;
    expect(result.title, '[Group] 葬送的芙莉莲 & Frieren - 37');
    expect(result.category, '動畫');
    expect(result.publishedAt, '2026/03/28 18:31');
    expect(result.size, '829.7MB');
    expect(result.publisher, 'LoliHouse');
    expect(
      result.detailsUrl.toString(),
      'https://dmhy.org/topics/view/715756_example.html',
    );
    expect(
      result.magnetUri,
      'magnet:?xt=urn:btih:ABC&tr=https%3A%2F%2Ftracker.example',
    );
  });

  test('ignores rows without a details link or magnet', () {
    final page = DmhySearchService.parse(
      '<table class="tablesorter"><tr><td>header</td></tr></table>',
    );
    expect(page.results, isEmpty);
    expect(page.hasNextPage, isFalse);
  });
}
