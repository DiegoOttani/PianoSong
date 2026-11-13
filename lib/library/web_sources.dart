import 'dart:typed_data';

/// Sites de MIDI abertos no navegador embutido do app. Quem navega é você;
/// o app só recebe o arquivo quando você toca em "download" no site.
enum WebSource {
  museScore(
    'MuseScore',
    'Arranjos de piano feitos por fãs. Muitos MIDIs só baixam com assinatura.',
    'https://musescore.com/sheetmusic?text={q}',
    'https://musescore.com/sheetmusic',
  ),
  midiShow(
    'MIDIShow',
    'Muito anime e jogo. Pode pedir conta grátis para baixar.',
    'https://www.midishow.com/en/search/result?q={q}',
    'https://www.midishow.com/en',
  ),
  onlineSequencer(
    'Online Sequencer',
    'Transcrições da comunidade. Na música: menu de exportar > MIDI.',
    'https://www.google.com/search?q={q}+site%3Aonlinesequencer.net',
    'https://onlinesequencer.net/sequences',
  ),
  google(
    'Google',
    'Qualquer site com arquivos .mid.',
    'https://www.google.com/search?q={q}+piano+midi+download',
    'https://www.google.com/search?q=piano+midi+download',
  );

  const WebSource(this.label, this.hint, this._searchTemplate, this.homeUrl);

  final String label;
  final String hint;
  final String _searchTemplate;
  final String homeUrl;

  String urlFor(String query) {
    final q = query.trim();
    if (q.isEmpty) return homeUrl;
    return _searchTemplate.replaceAll('{q}', Uri.encodeQueryComponent(q));
  }
}

/// Encontra o conteúdo MIDI nos bytes baixados (aceita .mid e .rmi).
/// Retorna null se não for MIDI (ex.: página de login).
Uint8List? extractMidi(Uint8List bytes) {
  const header = [0x4D, 0x54, 0x68, 0x64]; // "MThd"
  final limit = bytes.length < 128 ? bytes.length - 4 : 124;
  for (var i = 0; i <= limit; i++) {
    if (bytes[i] == header[0] &&
        bytes[i + 1] == header[1] &&
        bytes[i + 2] == header[2] &&
        bytes[i + 3] == header[3]) {
      return i == 0 ? bytes : Uint8List.sublistView(bytes, i);
    }
  }
  return null;
}

/// Distingue downloads de navegações comuns no WebView oficial do Flutter.
///
/// No Android, quando o site inicia um download, o pacote `webview_flutter`
/// avisa como se fosse uma navegação para a mesma URL. Se a navegação for
/// permitida, o WebView tenta abrir a URL, percebe de novo que é download e
/// avisa outra vez. Então: **mesma URL pedida duas vezes em poucos segundos,
/// sem a página ter começado a carregar = download**. Links .mid e blob/data
/// são download direto.
class DownloadDetector {
  DownloadDetector({this.window = const Duration(seconds: 4), DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final Duration window;
  final DateTime Function() _clock;
  final Map<String, DateTime> _pending = {};

  bool isDownload(String url) {
    if (looksLikeMidiUrl(url) || url.startsWith('blob:') || url.startsWith('data:')) {
      return true;
    }
    final now = _clock();
    _pending.removeWhere((_, t) => now.difference(t) > window);
    if (_pending.remove(url) != null) return true;
    _pending[url] = now;
    return false;
  }

  /// A página começou a carregar: era navegação de verdade.
  void pageStarted(String url) => _pending.remove(url);
}

bool looksLikeMidiUrl(String url) {
  final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
  return path.endsWith('.mid') || path.endsWith('.midi') || path.endsWith('.kar');
}

/// Nome do arquivo a partir do Content-Disposition ou da URL, sem extensão.
String titleFromDownload({String? suggestedFilename, String? contentDisposition, String? url}) {
  String? name = suggestedFilename;
  if ((name == null || name.isEmpty) && contentDisposition != null) {
    final m = RegExp(r'''filename\*?=(?:UTF-8'')?"?([^";]+)"?''', caseSensitive: false)
        .firstMatch(contentDisposition);
    if (m != null) name = Uri.decodeComponent(m.group(1)!);
  }
  if ((name == null || name.isEmpty) && url != null && !url.startsWith('blob:')) {
    final segs = Uri.tryParse(url)?.pathSegments ?? const [];
    if (segs.isNotEmpty) name = Uri.decodeComponent(segs.last);
  }
  if (name == null || name.isEmpty) return '';
  return name
      .replaceAll(RegExp(r'\.(mid|midi|kar|rmi)$', caseSensitive: false), '')
      .replaceAll(RegExp(r'[_]+'), ' ')
      .trim();
}
