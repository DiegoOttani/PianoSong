import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class BitMidiResult {
  const BitMidiResult({
    required this.id,
    required this.name,
    required this.downloadUrl,
    required this.plays,
  });

  final int id;
  final String name;
  final String downloadUrl;
  final int plays;

  /// Nome sem ".mid" e com espaços.
  String get title => name
      .replaceAll(RegExp(r'\.midi?$', caseSensitive: false), '')
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .trim();
}

class BitMidiPage {
  const BitMidiPage(this.results, this.total, this.pageTotal);
  final List<BitMidiResult> results;
  final int total;
  final int pageTotal;
}

/// Cliente da API pública do BitMidi (https://bitmidi.com).
class BitMidiApi {
  BitMidiApi({http.Client? client}) : _client = client ?? http.Client();

  static const _base = 'https://bitmidi.com';
  final http.Client _client;

  Future<BitMidiPage> search(String query, {int page = 0}) async {
    final uri = Uri.parse('$_base/api/midi/search')
        .replace(queryParameters: {'q': query, 'page': '$page'});
    final res = await _client.get(uri).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw Exception('Busca falhou (HTTP ${res.statusCode})');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final result = body['result'] as Map<String, dynamic>;
    final items = (result['results'] as List).cast<Map<String, dynamic>>();
    return BitMidiPage(
      [
        for (final r in items)
          BitMidiResult(
            id: r['id'] as int,
            name: r['name'] as String,
            downloadUrl: r['downloadUrl'] as String,
            plays: (r['plays'] as num?)?.toInt() ?? 0,
          ),
      ],
      (result['total'] as num?)?.toInt() ?? items.length,
      (result['pageTotal'] as num?)?.toInt() ?? 1,
    );
  }

  Future<Uint8List> download(BitMidiResult r) async {
    final res = await _client
        .get(Uri.parse('$_base${r.downloadUrl}'))
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw Exception('Download falhou (HTTP ${res.statusCode})');
    }
    return res.bodyBytes;
  }
}
