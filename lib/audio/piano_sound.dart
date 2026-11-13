import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

import 'piano_synth.dart';

/// Toca notas de piano com o SoLoud (baixa latência, várias notas juntas).
/// Os sons são gerados no primeiro uso, em segundo plano.
class PianoSound {
  PianoSound._();
  static final instance = PianoSound._();

  final _sources = <int, AudioSource>{};
  final _loading = <int>{};
  bool _initStarted = false;
  bool get ready => SoLoud.instance.isInitialized;

  /// Inicia o motor de áudio e prepara as notas da faixa [lowest]..[highest].
  Future<void> prepare(int lowest, int highest) async {
    try {
      if (!_initStarted) {
        _initStarted = true;
        await SoLoud.instance.init(channels: Channels.mono);
        SoLoud.instance.setMaxActiveVoiceCount(48);
      }
      if (!ready) return;
      // Gera do centro para fora: as notas mais usadas ficam prontas antes.
      final order = [for (var m = lowest; m <= highest; m++) m]
        ..sort((a, b) => (a - 64).abs().compareTo((b - 64).abs()));
      final todo = order.where((m) => !_sources.containsKey(m) && _loading.add(m)).toList();
      const batch = 8;
      for (var i = 0; i < todo.length; i += batch) {
        final chunk = todo.sublist(i, (i + batch).clamp(0, todo.length));
        final wavs = await Isolate.run(() => [for (final m in chunk) PianoSynth.renderWav(m)]);
        for (var j = 0; j < chunk.length; j++) {
          _sources[chunk[j]] = await SoLoud.instance.loadMem('piano_${chunk[j]}.wav', wavs[j]);
          _loading.remove(chunk[j]);
        }
      }
    } catch (e) {
      debugPrint('PianoSound: $e');
    }
  }

  /// Toca a nota e retorna o handle (para soltar depois), ou null se ainda
  /// não estiver pronta.
  SoundHandle? noteOn(int midi, {double volume = 1.0}) {
    final src = _sources[midi];
    if (src == null || !ready) return null;
    try {
      return SoLoud.instance.play(src, volume: volume);
    } catch (_) {
      return null;
    }
  }

  /// Solta a nota com um fade curto (como o abafador do piano).
  void noteOff(SoundHandle? handle, {Duration fade = const Duration(milliseconds: 180)}) {
    if (handle == null || !ready) return;
    try {
      SoLoud.instance.fadeVolume(handle, 0, fade);
      SoLoud.instance.scheduleStop(handle, fade);
    } catch (_) {}
  }

  /// Toca a nota por um tempo e solta sozinha.
  void playFor(int midi, Duration length, {double volume = 1.0}) {
    final h = noteOn(midi, volume: volume);
    if (h == null) return;
    try {
      SoLoud.instance.scheduleStop(h, length + const Duration(milliseconds: 200));
      Future<void>.delayed(length, () => noteOff(h));
    } catch (_) {}
  }

  @visibleForTesting
  static Uint8List wavFor(int midi) => PianoSynth.renderWav(midi);
}
