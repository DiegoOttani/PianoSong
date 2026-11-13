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

  test('URLs de busca', () {
    expect(WebSource.midiShow.urlFor('great days'),
        'https://www.midishow.com/en/search/result?q=great+days');
    expect(WebSource.museScore.urlFor(''), WebSource.museScore.homeUrl);
    expect(looksLikeMidiUrl('https://a.com/x/song.MID?dl=1'), isTrue);
    expect(looksLikeMidiUrl('https://a.com/x/song.html'), isFalse);
  });
}
