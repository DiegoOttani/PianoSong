import 'dart:typed_data';

import 'hand_splitter.dart';
import 'midi_parser.dart';
import 'song_model.dart';

/// Uma "parte" do MIDI: as notas de um canal dentro de uma track.
class MidiPart {
  const MidiPart({
    required this.track,
    required this.channel,
    required this.program,
    required this.noteCount,
    required this.avgPitch,
    required this.name,
  });

  final int track;
  final int channel;
  final int program;
  final int noteCount;
  final double avgPitch;
  final String name;

  (int, int) get id => (track, channel);
  bool get isDrums => channel == 9;
  bool get isPiano => !isDrums && program <= 7;

  static const _families = [
    'Piano', 'Percussão cromática', 'Órgão', 'Violão/Guitarra', 'Baixo',
    'Cordas', 'Conjunto', 'Metais', 'Palhetas', 'Sopros', 'Synth lead',
    'Synth pad', 'Synth efeitos', 'Étnico', 'Percussivo', 'Efeitos',
  ];

  String get instrument => isDrums ? 'Bateria' : _families[(program ~/ 8).clamp(0, 15)];

  String get label => name.isNotEmpty ? '$name ($instrument)' : instrument;
}

abstract final class MidiImporter {
  static RawMidi parse(Uint8List bytes) => MidiParser.parse(bytes);

  static List<MidiPart> parts(RawMidi midi) {
    final byPart = <(int, int), List<RawNote>>{};
    for (final n in midi.notes) {
      byPart.putIfAbsent((n.track, n.channel), () => []).add(n);
    }
    // Programa por canal visto em qualquer track (formato 1 às vezes separa).
    final programByChannel = <int, int>{};
    midi.programs.forEach((k, v) => programByChannel.putIfAbsent(k.$2, () => v));

    final result = [
      for (final e in byPart.entries)
        MidiPart(
          track: e.key.$1,
          channel: e.key.$2,
          program: midi.programs[e.key] ?? programByChannel[e.key.$2] ?? 0,
          noteCount: e.value.length,
          avgPitch: e.value.map((n) => n.pitch).reduce((a, b) => a + b) / e.value.length,
          name: midi.trackNames[e.key.$1] ?? '',
        ),
    ];
    result.sort((a, b) {
      final c = a.track.compareTo(b.track);
      return c != 0 ? c : a.channel.compareTo(b.channel);
    });
    return result;
  }

  /// Partes pré-selecionadas: os pianos; se não houver, a "melodia" mais provável.
  static Set<(int, int)> defaultSelection(List<MidiPart> parts) {
    final pianos = parts.where((p) => p.isPiano).toList();
    if (pianos.isNotEmpty) return {for (final p in pianos) p.id};
    final candidates = parts.where((p) => !p.isDrums).toList();
    if (candidates.isEmpty) return {};
    final melodic = candidates.where((p) => p.avgPitch >= 55).toList();
    final pool = melodic.isNotEmpty ? melodic : candidates;
    pool.sort((a, b) => b.noteCount.compareTo(a.noteCount));
    return {pool.first.id};
  }

  static Song toSong(
    RawMidi midi, {
    required String title,
    Set<(int, int)>? selection,
  }) {
    final allParts = parts(midi);
    final selected = selection ?? defaultSelection(allParts);
    final tm = midi.tempoMap;

    // Duas partes bem separadas em altura: cada uma vira uma mão.
    Map<(int, int), Hand>? handByPart;
    final chosen = allParts.where((p) => selected.contains(p.id)).toList();
    if (chosen.length == 2 && (chosen[0].avgPitch - chosen[1].avgPitch).abs() >= 7) {
      final hi = chosen[0].avgPitch > chosen[1].avgPitch ? chosen[0] : chosen[1];
      handByPart = {for (final p in chosen) p.id: p == hi ? Hand.right : Hand.left};
    }

    var notes = <NoteEvent>[];
    for (final n in midi.notes) {
      final id = (n.track, n.channel);
      if (!selected.contains(id) || n.channel == 9) continue;
      final start = tm.msAt(n.startTick).round();
      final end = tm.msAt(n.endTick).round();
      notes.add(NoteEvent(
        pitch: n.pitch,
        startMs: start,
        durationMs: (end - start).clamp(50, 1 << 30),
        hand: handByPart?[id] ?? Hand.right,
        velocity: n.velocity,
      ));
    }
    notes = _dedupe(notes);
    if (handByPart == null) notes = HandSplitter.split(notes);

    final (beats, bars) = _beatGrid(midi);
    final bpm = 60000000 / tm.usPerBeatAt(0);
    return Song(
      title: title,
      notes: notes,
      beatsMs: beats,
      barsMs: bars,
      initialBpm: double.parse(bpm.toStringAsFixed(1)),
    );
  }

  /// Remove notas repetidas (mesma altura começando quase junto).
  static List<NoteEvent> _dedupe(List<NoteEvent> notes) {
    notes.sort(compareNotes);
    final lastStartByPitch = <int, int>{};
    final out = <NoteEvent>[];
    for (final n in notes) {
      final last = lastStartByPitch[n.pitch];
      if (last != null && n.startMs - last < 15) continue;
      lastStartByPitch[n.pitch] = n.startMs;
      out.add(n);
    }
    return out;
  }

  static (List<int>, List<int>) _beatGrid(RawMidi midi) {
    final tm = midi.tempoMap;
    final sigs = midi.timeSignatures.isEmpty
        ? [const TimeSignature(0, 4, 4)]
        : midi.timeSignatures;
    final beats = <int>[];
    final bars = <int>[];
    var sigIndex = 0;
    var sig = sigs.first.tick == 0 ? sigs.first : const TimeSignature(0, 4, 4);
    if (sigs.first.tick == 0) sigIndex = 1;
    var tick = 0;
    var beatInBar = 0;
    final limit = midi.lastTick + midi.ticksPerBeat * 8;
    while (tick <= limit && beats.length < 100000) {
      while (sigIndex < sigs.length && sigs[sigIndex].tick <= tick) {
        sig = sigs[sigIndex++];
        beatInBar = 0;
      }
      final ms = tm.msAt(tick).round();
      beats.add(ms);
      if (beatInBar == 0) bars.add(ms);
      final beatTicks = (midi.ticksPerBeat * 4 / sig.denominator).round().clamp(1, 1 << 30);
      tick += beatTicks;
      beatInBar = (beatInBar + 1) % (sig.numerator <= 0 ? 4 : sig.numerator);
    }
    return (beats, bars);
  }
}
