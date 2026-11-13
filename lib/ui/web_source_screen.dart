import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../library/web_sources.dart';
import '../services/app_services.dart';
import 'parts_screen.dart';
import 'song_detail_screen.dart';
import 'widgets.dart';

/// Navegador dentro do app: você navega no site normalmente e, ao tocar em
/// baixar um MIDI, o arquivo vai direto para a tela de escolher partes.
class WebSourceScreen extends StatefulWidget {
  const WebSourceScreen({super.key, required this.source, required this.query});

  final WebSource source;
  final String query;

  @override
  State<WebSourceScreen> createState() => _WebSourceScreenState();
}

class _WebSourceScreenState extends State<WebSourceScreen> {
  static const _channel = 'PianoSongMidi';

  late final WebViewController _web;
  final _cookies = WebViewCookieManager();
  final _detector = DownloadDetector();
  Completer<String>? _blobResult;
  double _progress = 0;
  bool _downloading = false;
  bool _hintVisible = true;

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(_channel, onMessageReceived: (m) {
        final c = _blobResult;
        if (c != null && !c.isCompleted) c.complete(m.message);
      })
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) => mounted ? setState(() => _progress = p / 100) : null,
        onPageStarted: _detector.pageStarted,
        onNavigationRequest: (req) {
          if (req.isMainFrame && _detector.isDownload(req.url)) {
            _download(req.url);
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
      ))
      ..loadRequest(Uri.parse(widget.source.urlFor(widget.query)));

    final platformCookies = _cookies.platform;
    final platformWeb = _web.platform;
    if (platformCookies is AndroidWebViewCookieManager && platformWeb is AndroidWebViewController) {
      platformCookies.setAcceptThirdPartyCookies(platformWeb, true);
    }
  }

  Future<void> _download(String url) async {
    if (_downloading) return;
    setState(() => _downloading = true);
    try {
      final (raw, disposition) = await _fetch(url);
      final midi = extractMidi(raw);
      if (midi == null) {
        throw Exception('O arquivo baixado não é um MIDI. O site pode estar pedindo login, '
            'assinatura ou que você escolha o formato MIDI.');
      }
      var title = titleFromDownload(contentDisposition: disposition, url: url);
      if (title.isEmpty || RegExp(r'^\d+$').hasMatch(title)) {
        title = _cleanPageTitle(await _web.getTitle()) ?? widget.query;
      }
      if (!mounted) return;
      final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => PartsScreen(
          bytes: midi,
          suggestedTitle: title,
          source: 'web',
          id: 'web-${DateTime.now().millisecondsSinceEpoch}',
        ),
      ));
      if (saved == true && mounted) {
        final entry = AppServices.of(context).repository.entries.first;
        Navigator.of(context)
            .pushReplacement(MaterialPageRoute(builder: (_) => SongDetailScreen(entry: entry)));
      }
    } catch (e) {
      if (mounted) showError(context, e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  /// Baixa o arquivo na mesma sessão do navegador (mesmos cookies e
  /// identificação), como o próprio navegador faria.
  Future<(Uint8List, String?)> _fetch(String url) async {
    if (url.startsWith('blob:') || url.startsWith('data:')) {
      // Arquivo gerado pela própria página: lê pelo JavaScript da página.
      final completer = _blobResult = Completer<String>();
      await _web.runJavaScript('''
        (async () => {
          try {
            const r = await fetch(${jsonEncode(url)});
            const b = await r.blob();
            const fr = new FileReader();
            fr.onload = () => $_channel.postMessage(fr.result);
            fr.onerror = () => $_channel.postMessage('erro:leitura');
            fr.readAsDataURL(b);
          } catch (e) { $_channel.postMessage('erro:' + e); }
        })();
      ''');
      final value = await completer.future.timeout(const Duration(seconds: 20));
      if (value.startsWith('erro:')) {
        throw Exception('Não consegui ler o arquivo gerado pelo site ($value).');
      }
      return (base64Decode(value.substring(value.indexOf(',') + 1)), null);
    }

    final uri = Uri.parse(url);
    final cookies = await _cookies.getCookies(domain: uri);
    final userAgent = await _web.getUserAgent();
    final referer = await _web.currentUrl();
    final res = await http.get(uri, headers: {
      if (cookies.isNotEmpty) 'Cookie': cookies.map((c) => '${c.name}=${c.value}').join('; '),
      'User-Agent': ?userAgent,
      'Referer': ?referer,
    }).timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw Exception('O site recusou o download (HTTP ${res.statusCode}). '
          'Talvez precise entrar na conta.');
    }
    return (res.bodyBytes, res.headers['content-disposition']);
  }

  String? _cleanPageTitle(String? t) {
    if (t == null) return null;
    final cleaned = t
        .split(RegExp(r'\s[|–-]\s'))
        .first
        .replaceAll(RegExp(r'\b(midi|download|sheet music|for piano)\b', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return cleaned.isEmpty ? null : cleaned;
  }

  Future<void> _back() async {
    if (await _web.canGoBack()) {
      await _web.goBack();
    } else if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.source.label),
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: _back),
          actions: [
            IconButton(
              tooltip: 'Fechar',
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(),
            ),
            IconButton(
              tooltip: 'Recarregar',
              icon: const Icon(Icons.refresh),
              onPressed: () => _web.reload(),
            ),
          ],
          bottom: _progress < 1
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(3),
                  child: LinearProgressIndicator(value: _progress, minHeight: 3),
                )
              : null,
        ),
        body: Stack(
          children: [
            WebViewWidget(controller: _web),
            if (_hintVisible)
              Positioned(
                left: 8,
                right: 8,
                bottom: 8,
                child: Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(12),
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  child: ListTile(
                    leading: const Icon(Icons.download),
                    title: const Text('Toque em baixar MIDI no site'),
                    subtitle: Text(widget.source.hint),
                    trailing: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() => _hintVisible = false),
                    ),
                  ),
                ),
              ),
            if (_downloading)
              const Positioned.fill(
                child: ColoredBox(
                  color: Colors.black54,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 12),
                        Text('Baixando MIDI…', style: TextStyle(color: Colors.white)),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
