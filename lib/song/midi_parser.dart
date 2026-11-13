import 'dart:typed_data';

class MidiFormatException implements Exception {
  MidiFormatException(this.message);
  final String message;
  @override
  String toString() => 'MidiFormatException: $message';
}

/// Uma nota crua do arquivo MIDI, em ticks.
class RawNote {
  const RawNote({
    required this.track,
    required this.channel,
    required this.pitch,
    required this.velocity,
    required this.startTick,
    required this.endTick,
  });

  final int track;
  final int channel;
  final int pitch;
  final int velocity;
  final int startTick;
  final int endTick;
}

class TempoChange {
  const TempoChange(this.tick, this.usPerBeat);
  final int tick;

  /// Microssegundos por semínima.
  final int usPerBeat;
}

class TimeSignature {
  const TimeSignature(this.tick, this.numerator, this.denominator);
  final int tick;
  final int numerator;
  final int denominator;
}

/// Conteúdo de um Standard MIDI File já decodificado.
class RawMidi {
  RawMidi({
    required this.format,
    required this.ticksPerBeat,
    required this.notes,
    required this.tempos,
    required this.timeSignatures,
    required this.trackNames,
    required this.programs,
    required this.lastTick,
  });

  final int format;
  final int ticksPerBeat;
  final List<RawNote> notes;
  final List<TempoChange> tempos;
  final List<TimeSignature> timeSignatures;
  final Map<int, String> trackNames;

  /// Primeiro "program change" visto para cada (track, canal).
  final Map<(int, int), int> programs;
  final int lastTick;

  late final TempoMap tempoMap = TempoMap(ticksPerBeat, tempos);
}

/// Converte ticks em milissegundos respeitando mudanças de andamento.
class TempoMap {
  TempoMap(this.ticksPerBeat, List<TempoChange> changes) {
    final sorted = [...changes]..sort((a, b) => a.tick.compareTo(b.tick));
    if (sorted.isEmpty || sorted.first.tick > 0) {
      sorted.insert(0, const TempoChange(0, 500000)); // 120 BPM padrão
    }
    var ms = 0.0;
    for (var i = 0; i < sorted.length; i++) {
      final c = sorted[i];
      if (i > 0) {
        final prev = _segments.last;
        ms = prev.ms + (c.tick - prev.tick) * prev.usPerBeat / ticksPerBeat / 1000;
      }
      // Mudanças no mesmo tick: vale a última.
      if (_segments.isNotEmpty && _segments.last.tick == c.tick) {
        _segments.removeLast();
      }
      _segments.add((tick: c.tick, ms: ms, usPerBeat: c.usPerBeat));
    }
  }

  final int ticksPerBeat;
  final List<({int tick, double ms, int usPerBeat})> _segments = [];

  ({int tick, double ms, int usPerBeat}) _segmentAt(int tick) {
    var lo = 0, hi = _segments.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_segments[mid].tick <= tick) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return _segments[lo];
  }

  double msAt(int tick) {
    final s = _segmentAt(tick);
    return s.ms + (tick - s.tick) * s.usPerBeat / ticksPerBeat / 1000;
  }

  int usPerBeatAt(int tick) => _segmentAt(tick).usPerBeat;
}

/// Leitor de Standard MIDI Files (formatos 0, 1 e 2).
abstract final class MidiParser {
  static RawMidi parse(Uint8List bytes) {
    final r = _Reader(bytes);
    if (r.readAscii(4) != 'MThd') {
      throw MidiFormatException('Cabeçalho MThd não encontrado');
    }
    final headerLen = r.readUint32();
    final format = r.readUint16();
    final trackCount = r.readUint16();
    final division = r.readUint16();
    r.skip(headerLen - 6);

    var ticksPerBeat = division;
    var smpte = false;
    if (division & 0x8000 != 0) {
      // Divisão SMPTE: ticks por segundo fixos. Tratamos como 1 "beat" = 1s.
      final fps = 256 - (division >> 8);
      final tpf = division & 0xFF;
      ticksPerBeat = fps * tpf;
      smpte = true;
    }
    if (ticksPerBeat <= 0) throw MidiFormatException('Divisão inválida');

    final notes = <RawNote>[];
    final tempos = <TempoChange>[];
    final sigs = <TimeSignature>[];
    final names = <int, String>{};
    final programs = <(int, int), int>{};
    var lastTick = 0;

    var track = 0;
    while (track < trackCount && r.remaining >= 8) {
      final id = r.readAscii(4);
      final len = r.readUint32();
      if (id != 'MTrk') {
        r.skip(len);
        continue;
      }
      final end = r.pos + len;
      if (end > bytes.length) throw MidiFormatException('Track truncada');
      final t = _parseTrack(r, end, track, notes, tempos, sigs, names, programs);
      if (t > lastTick) lastTick = t;
      r.pos = end;
      track++;
    }

    if (smpte) {
      tempos
        ..clear()
        ..add(const TempoChange(0, 1000000));
    }
    notes.sort((a, b) {
      final c = a.startTick.compareTo(b.startTick);
      return c != 0 ? c : a.pitch.compareTo(b.pitch);
    });
    sigs.sort((a, b) => a.tick.compareTo(b.tick));

    return RawMidi(
      format: format,
      ticksPerBeat: ticksPerBeat,
      notes: notes,
      tempos: tempos,
      timeSignatures: sigs,
      trackNames: names,
      programs: programs,
      lastTick: lastTick,
    );
  }

  static int _parseTrack(
    _Reader r,
    int end,
    int track,
    List<RawNote> notes,
    List<TempoChange> tempos,
    List<TimeSignature> sigs,
    Map<int, String> names,
    Map<(int, int), int> programs,
  ) {
    var tick = 0;
    int? running;
    // chave canal*128+nota -> (tick inicial, velocity)
    final open = <int, (int, int)>{};

    void close(int key, int atTick) {
      final o = open.remove(key);
      if (o == null) return;
      notes.add(RawNote(
        track: track,
        channel: key ~/ 128,
        pitch: key % 128,
        velocity: o.$2,
        startTick: o.$1,
        endTick: atTick > o.$1 ? atTick : o.$1 + 1,
      ));
    }

    while (r.pos < end) {
      tick += r.readVlq();
      var status = r.peek();
      if (status & 0x80 != 0) {
        r.pos++;
      } else {
        if (running == null) throw MidiFormatException('Running status sem status anterior');
        status = running;
      }

      if (status == 0xFF) {
        final type = r.readByte();
        final len = r.readVlq();
        final dataStart = r.pos;
        r.skip(len);
        switch (type) {
          case 0x51 when len >= 3:
            final us = (r.bytes[dataStart] << 16) |
                (r.bytes[dataStart + 1] << 8) |
                r.bytes[dataStart + 2];
            if (us > 0) tempos.add(TempoChange(tick, us));
          case 0x58 when len >= 2:
            sigs.add(TimeSignature(
                tick, r.bytes[dataStart], 1 << r.bytes[dataStart + 1]));
          case 0x03:
            names.putIfAbsent(
                track,
                () => String.fromCharCodes(
                    r.bytes.sublist(dataStart, dataStart + len)).trim());
          case 0x2F:
            r.pos = end;
        }
        running = null;
      } else if (status == 0xF0 || status == 0xF7) {
        r.skip(r.readVlq());
        running = null;
      } else {
        running = status;
        final type = status & 0xF0;
        final ch = status & 0x0F;
        final d1 = r.readByte();
        final d2 = (type == 0xC0 || type == 0xD0) ? 0 : r.readByte();
        switch (type) {
          case 0x90 when d2 > 0:
            final key = ch * 128 + d1;
            close(key, tick); // re-ataque sem note-off
            open[key] = (tick, d2);
          case 0x90 || 0x80:
            close(ch * 128 + d1, tick);
          case 0xC0:
            programs.putIfAbsent((track, ch), () => d1);
        }
      }
    }
    for (final key in open.keys.toList()) {
      close(key, tick);
    }
    return tick;
  }
}

class _Reader {
  _Reader(this.bytes);
  final Uint8List bytes;
  int pos = 0;

  int get remaining => bytes.length - pos;

  void _need(int n) {
    if (pos + n > bytes.length) throw MidiFormatException('Arquivo truncado');
  }

  int peek() {
    _need(1);
    return bytes[pos];
  }

  int readByte() {
    _need(1);
    return bytes[pos++];
  }

  void skip(int n) {
    _need(n);
    pos += n;
  }

  int readUint16() {
    _need(2);
    final v = (bytes[pos] << 8) | bytes[pos + 1];
    pos += 2;
    return v;
  }

  int readUint32() {
    _need(4);
    final v = (bytes[pos] << 24) |
        (bytes[pos + 1] << 16) |
        (bytes[pos + 2] << 8) |
        bytes[pos + 3];
    pos += 4;
    return v;
  }

  String readAscii(int n) {
    _need(n);
    final s = String.fromCharCodes(bytes.sublist(pos, pos + n));
    pos += n;
    return s;
  }

  int readVlq() {
    var value = 0;
    for (var i = 0; i < 4; i++) {
      final b = readByte();
      value = (value << 7) | (b & 0x7F);
      if (b & 0x80 == 0) return value;
    }
    throw MidiFormatException('VLQ inválido');
  }
}
