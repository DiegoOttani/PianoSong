import 'dart:typed_data';

/// Monta arquivos MIDI pequenos para os testes.
class MidiBuilder {
  MidiBuilder({this.ppq = 480});
  final int ppq;
  final List<TrackBuilder> tracks = [];

  TrackBuilder track() {
    final t = TrackBuilder();
    tracks.add(t);
    return t;
  }

  Uint8List build({int? format}) {
    final out = BytesBuilder();
    out.add('MThd'.codeUnits);
    out.add(_u32(6));
    out.add(_u16(format ?? (tracks.length == 1 ? 0 : 1)));
    out.add(_u16(tracks.length));
    out.add(_u16(ppq));
    for (final t in tracks) {
      final body = t._encode();
      out.add('MTrk'.codeUnits);
      out.add(_u32(body.length));
      out.add(body);
    }
    return out.toBytes();
  }
}

class TrackBuilder {
  final List<(int tick, int order, List<int> bytes)> _events = [];
  bool useRunningStatus = false;

  void name(String n) => _events.add((0, 0, [0xFF, 0x03, ..._vlq(n.length), ...n.codeUnits]));

  void tempo(int tick, double bpm) {
    final us = (60000000 / bpm).round();
    _events.add((tick, 0, [0xFF, 0x51, 0x03, (us >> 16) & 0xFF, (us >> 8) & 0xFF, us & 0xFF]));
  }

  void timeSig(int tick, int num, int den) {
    final pow = {1: 0, 2: 1, 4: 2, 8: 3, 16: 4}[den]!;
    _events.add((tick, 0, [0xFF, 0x58, 0x04, num, pow, 24, 8]));
  }

  void program(int tick, int channel, int program) =>
      _events.add((tick, 1, [0xC0 | channel, program]));

  /// Note-off é escrito como note-on com velocity 0 quando [zeroVelOff].
  void note(int tick, int dur, int pitch, {int channel = 0, int vel = 80, bool zeroVelOff = false}) {
    _events.add((tick, 3, [0x90 | channel, pitch, vel]));
    _events.add((
      tick + dur,
      2,
      zeroVelOff ? [0x90 | channel, pitch, 0] : [0x80 | channel, pitch, 0],
    ));
  }

  List<int> _encode() {
    final sorted = [..._events]..sort((a, b) {
        final c = a.$1.compareTo(b.$1);
        return c != 0 ? c : a.$2.compareTo(b.$2);
      });
    final out = <int>[];
    var last = 0;
    int? running;
    for (final e in sorted) {
      out.addAll(_vlq(e.$1 - last));
      last = e.$1;
      final bytes = e.$3;
      final status = bytes.first;
      if (useRunningStatus && status < 0xF0 && status == running) {
        out.addAll(bytes.sublist(1));
      } else {
        out.addAll(bytes);
        running = status < 0xF0 ? status : null;
      }
    }
    out.addAll([0x00, 0xFF, 0x2F, 0x00]);
    return out;
  }
}

List<int> _u32(int v) => [(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF];
List<int> _u16(int v) => [(v >> 8) & 0xFF, v & 0xFF];

List<int> _vlq(int v) {
  final bytes = [v & 0x7F];
  v >>= 7;
  while (v > 0) {
    bytes.insert(0, (v & 0x7F) | 0x80);
    v >>= 7;
  }
  return bytes;
}
