import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:piano_song/library/web_sources.dart';
import 'package:piano_song/song/midi_parser.dart';

import 'helpers/midi_builder.dart';

void main() {
  final midi = (MidiBuilder()..track().note(0, 480, 60)).build();

  test('reconhece MIDI puro e dentro de RIFF (.rmi)', () {
    expect(extractMidi(midi), same(midi));
    final riff = Uint8List.fromList([...'RIFF'.codeUnits, 0, 0, 0, 0, ...'RMIDdata'.codeUnits, 0, 0, 0, 0, ...midi]);
    final out = extractMidi(riff)!;
    expect(MidiParser.parse(out).notes.single.pitch, 60);
  });

  test('rejeita página HTML', () {
    expect(extractMidi(Uint8List.fromList('<!DOCTYPE html><html>login</html>'.codeUnits)), isNull);
    expect(extractMidi(Uint8List(0)), isNull);
  });

  test('nome da música a partir do download', () {
    expect(titleFromDownload(suggestedFilename: 'Giorno_Theme.mid'), 'Giorno Theme');
    expect(
        titleFromDownload(contentDisposition: 'attachment; filename="Great Days (piano).midi"'),
        'Great Days (piano)');
    expect(titleFromDownload(url: 'https://x.com/files/Bloody%20Stream.mid?a=1'), 'Bloody Stream');
    expect(titleFromDownload(url: 'blob:https://x.com/abc'), '');
  });

  test('detector: mesma URL repetida sem carregar página = download', () {
    var now = DateTime(2026);
    final d = DownloadDetector(clock: () => now);
    const file = 'https://site.com/download/123';

    // Link comum: navega e a página carrega.
    expect(d.isDownload('https://site.com/musica/123'), isFalse);
    d.pageStarted('https://site.com/musica/123');
    expect(d.isDownload('https://site.com/musica/123'), isFalse, reason: 'voltou à mesma página depois');

    // Download: o WebView repete o pedido sem carregar página.
    expect(d.isDownload(file), isFalse);
    now = now.add(const Duration(milliseconds: 300));
    expect(d.isDownload(file), isTrue);

    // Repetição muito depois não conta.
    expect(d.isDownload('https://site.com/x'), isFalse);
    now = now.add(const Duration(seconds: 10));
    expect(d.isDownload('https://site.com/x'), isFalse);

    expect(d.isDownload('blob:https://site.com/abc'), isTrue);
    expect(d.isDownload('https://site.com/a.mid'), isTrue);
  });

  test('URLs de busca', () {
    expect(WebSource.midiShow.urlFor('great days'),
        'https://www.midishow.com/en/search/result?q=great+days');
    expect(WebSource.museScore.urlFor(''), WebSource.museScore.homeUrl);
    expect(looksLikeMidiUrl('https://a.com/x/song.MID?dl=1'), isTrue);
    expect(looksLikeMidiUrl('https://a.com/x/song.html'), isFalse);
  });
}
