enum Hand { right, left }

/// Uma nota a ser tocada, em milissegundos (no andamento original, 100%).
class NoteEvent {
  const NoteEvent({
    required this.pitch,
    required this.startMs,
    required this.durationMs,
    required this.hand,
    this.velocity = 80,
  });

  final int pitch;
  final int startMs;
  final int durationMs;
  final Hand hand;
  final int velocity;

  int get endMs => startMs + durationMs;

  NoteEvent copyWith({int? pitch, int? startMs, int? durationMs, Hand? hand}) =>
      NoteEvent(
        pitch: pitch ?? this.pitch,
        startMs: startMs ?? this.startMs,
        durationMs: durationMs ?? this.durationMs,
        hand: hand ?? this.hand,
        velocity: velocity,
      );

  Map<String, Object> toJson() =>
      {'p': pitch, 's': startMs, 'd': durationMs, 'h': hand.index, 'v': velocity};

  factory NoteEvent.fromJson(Map<String, dynamic> j) => NoteEvent(
        pitch: j['p'] as int,
        startMs: j['s'] as int,
        durationMs: j['d'] as int,
        hand: Hand.values[j['h'] as int],
        velocity: (j['v'] as int?) ?? 80,
      );

  @override
  String toString() => 'Note($pitch @${startMs}ms +${durationMs}ms ${hand.name})';
}

int compareNotes(NoteEvent a, NoteEvent b) {
  final c = a.startMs.compareTo(b.startMs);
  return c != 0 ? c : a.pitch.compareTo(b.pitch);
}

/// Música pronta para tocar.
class Song {
  Song({
    required this.title,
    required List<NoteEvent> notes,
    this.beatsMs = const [],
    this.barsMs = const [],
    this.initialBpm = 120,
  }) : notes = List<NoteEvent>.unmodifiable(<NoteEvent>[...notes]..sort(compareNotes));

  final String title;
  final List<NoteEvent> notes;

  /// Início de cada tempo (beat), em ms.
  final List<int> beatsMs;

  /// Início de cada compasso, em ms.
  final List<int> barsMs;
  final double initialBpm;

  int get durationMs =>
      notes.isEmpty ? 0 : notes.map((n) => n.endMs).reduce((a, b) => a > b ? a : b);

  int get lowestPitch => notes.map((n) => n.pitch).reduce((a, b) => a < b ? a : b);
  int get highestPitch => notes.map((n) => n.pitch).reduce((a, b) => a > b ? a : b);

  /// Duração aproximada de um tempo perto de [ms].
  int beatLengthAt(int ms) {
    if (beatsMs.length < 2) return (60000 / initialBpm).round();
    var lo = 0, hi = beatsMs.length - 2;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (beatsMs[mid] <= ms) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return beatsMs[lo + 1] - beatsMs[lo];
  }

  Song copyWith({String? title, List<NoteEvent>? notes}) => Song(
        title: title ?? this.title,
        notes: notes ?? this.notes,
        beatsMs: beatsMs,
        barsMs: barsMs,
        initialBpm: initialBpm,
      );

  Map<String, Object> toJson() => {
        'title': title,
        'bpm': initialBpm,
        'beats': beatsMs,
        'bars': barsMs,
        'notes': [for (final n in notes) n.toJson()],
      };

  factory Song.fromJson(Map<String, dynamic> j) => Song(
        title: j['title'] as String,
        initialBpm: (j['bpm'] as num).toDouble(),
        beatsMs: (j['beats'] as List).cast<int>(),
        barsMs: (j['bars'] as List).cast<int>(),
        notes: [
          for (final n in j['notes'] as List) NoteEvent.fromJson(n as Map<String, dynamic>)
        ],
      );
}

/// Agrupa notas que começam juntas (acordes), com tolerância em ms.
List<List<NoteEvent>> groupChords(List<NoteEvent> notes, {int toleranceMs = 40}) {
  final sorted = [...notes]..sort(compareNotes);
  final groups = <List<NoteEvent>>[];
  for (final n in sorted) {
    if (groups.isNotEmpty && n.startMs - groups.last.first.startMs <= toleranceMs) {
      groups.last.add(n);
    } else {
      groups.add([n]);
    }
  }
  return groups;
}
