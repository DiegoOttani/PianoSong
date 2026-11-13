import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';

import '../library/web_sources.dart';
import 'parts_screen.dart';
import 'song_detail_screen.dart';
import '../services/app_services.dart';
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
  InAppWebViewController? _web;
  double _progress = 0;
  String? _pageTitle;
  bool _downloading = false;
  bool _hintVisible = true;

  Future<void> _download(
    String url, {
    String? suggestedFilename,
    String? contentDisposition,
    String? userAgent,
  }) async {
    if (_downloading || _web == null) return;
    setState(() => _downloading = true);
    try {
      final raw = await _fetch(url, userAgent: userAgent);
      final midi = extractMidi(raw);
      if (midi == null) {
        throw Exception(
          'O arquivo baixado não é um MIDI. O site pode estar pedindo login, '
          'assinatura ou que você escolha o formato MIDI.',
        );
      }
      var title = titleFromDownload(
        suggestedFilename: suggestedFilename,
        contentDisposition: contentDisposition,
        url: url,
      );
      if (title.isEmpty || RegExp(r'^\d+$').hasMatch(title)) {
        title = _cleanPageTitle(_pageTitle) ?? widget.query;
      }
      if (!mounted) return;
      final saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => PartsScreen(
            bytes: midi,
            suggestedTitle: title,
            source: 'web',
            id: 'web-${DateTime.now().millisecondsSinceEpoch}',
          ),
        ),
      );
      if (saved == true && mounted) {
        final entry = AppServices.of(context).repository.entries.first;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => SongDetailScreen(entry: entry)),
        );
      }
    } catch (e) {
      if (mounted) {
        showError(context, e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  /// Baixa o arquivo na mesma sessão do navegador (mesmos cookies e
  /// identificação), como o próprio navegador faria.
  Future<Uint8List> _fetch(String url, {String? userAgent}) async {
    if (url.startsWith('blob:') || url.startsWith('data:')) {
      // Arquivo gerado pela própria página: lê pelo JavaScript da página.
      final res = await _web!.callAsyncJavaScript(
        functionBody: '''
          const r = await fetch(url);
          const b = await r.blob();
          return await new Promise((ok, fail) => {
            const fr = new FileReader();
            fr.onload = () => ok(fr.result);
            fr.onerror = () => fail('erro ao ler arquivo');
            fr.readAsDataURL(b);
          });
        ''',
        arguments: {'url': url},
      );
      final value = res?.value;
      if (res?.error != null || value is! String) {
        throw Exception(
          'Não consegui ler o arquivo gerado pelo site (${res?.error ?? 'vazio'}).',
        );
      }
      return base64Decode(value.substring(value.indexOf(',') + 1));
    }

    final uri = WebUri(url);
    final cookies = await CookieManager.instance().getCookies(
      url: uri,
      webViewController: _web,
    );
    final referer = (await _web!.getUrl())?.toString();
    final res = await http
        .get(
          Uri.parse(url),
          headers: {
            if (cookies.isNotEmpty)
              'Cookie': cookies.map((c) => '${c.name}=${c.value}').join('; '),
            if (userAgent != null && userAgent.isNotEmpty)
              'User-Agent': userAgent,
            'Referer': ?referer,
          },
        )
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw Exception(
        'O site recusou o download (HTTP ${res.statusCode}). '
        'Talvez precise entrar na conta.',
      );
    }
    return res.bodyBytes;
  }

  String? _cleanPageTitle(String? t) {
    if (t == null) return null;
    final cleaned = t
        .split(RegExp(r'\s[|–-]\s'))
        .first
        .replaceAll(
          RegExp(
            r'\b(midi|download|sheet music|for piano)\b',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return cleaned.isEmpty ? null : cleaned;
  }

  Future<void> _back() async {
    if (_web != null && await _web!.canGoBack()) {
      await _web!.goBack();
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
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _back,
          ),
          actions: [
            IconButton(
              tooltip: 'Fechar',
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(),
            ),
            IconButton(
              tooltip: 'Recarregar',
              icon: const Icon(Icons.refresh),
              onPressed: () => _web?.reload(),
            ),
          ],
          bottom: _progress < 1
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(3),
                  child: LinearProgressIndicator(
                    value: _progress,
                    minHeight: 3,
                  ),
                )
              : null,
        ),
        body: Stack(
          children: [
            InAppWebView(
              initialUrlRequest: URLRequest(
                url: WebUri(widget.source.urlFor(widget.query)),
              ),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                useOnDownloadStart: true,
                useShouldOverrideUrlLoading: true,
                supportMultipleWindows: false,
                thirdPartyCookiesEnabled: true,
              ),
              onWebViewCreated: (c) => _web = c,
              onProgressChanged: (_, p) => setState(() => _progress = p / 100),
              onTitleChanged: (_, t) => _pageTitle = t,
              shouldOverrideUrlLoading: (_, action) async {
                final url = action.request.url?.toString() ?? '';
                if (looksLikeMidiUrl(url)) {
                  _download(url);
                  return NavigationActionPolicy.CANCEL;
                }
                return NavigationActionPolicy.ALLOW;
              },
              onDownloadStartRequest: (_, req) => _download(
                req.url.toString(),
                suggestedFilename: req.suggestedFilename,
                contentDisposition: req.contentDisposition,
                userAgent: req.userAgent,
              ),
            ),
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
                        Text(
                          'Baixando MIDI…',
                          style: TextStyle(color: Colors.white),
                        ),
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
