import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/keyboard_layout.dart';
import '../core/note.dart';
import '../game/scoring.dart';

enum InputMode {
  microphone('Microfone'),
  touch('Toque na tela');

  const InputMode(this.label);
  final String label;
}

/// Configurações do app, salvas no aparelho.
class Settings extends ChangeNotifier {
  Settings._(this._prefs);

  static Future<Settings> load() async =>
      Settings._(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  KeyboardSize get keyboard => KeyboardSize.fromKeys(_prefs.getInt('keyboard') ?? 61);
  set keyboard(KeyboardSize v) => _setInt('keyboard', v.keys);

  NoteNaming get naming => NoteNaming.values[_prefs.getInt('naming') ?? NoteNaming.solfege.index];
  set naming(NoteNaming v) => _setInt('naming', v.index);

  InputMode get inputMode =>
      InputMode.values[_prefs.getInt('inputMode') ?? InputMode.touch.index];
  set inputMode(InputMode v) => _setInt('inputMode', v.index);

  int get perfectMs => _prefs.getInt('perfectMs') ?? 90;
  set perfectMs(int v) => _setInt('perfectMs', v);

  int get goodMs => _prefs.getInt('goodMs') ?? 180;
  set goodMs(int v) => _setInt('goodMs', v);

  HitWindows get windows => HitWindows(perfectMs: perfectMs, goodMs: goodMs);

  /// Atraso do microfone medido na calibração.
  int get latencyMs => _prefs.getInt('latencyMs') ?? 120;
  set latencyMs(int v) => _setInt('latencyMs', v);

  /// Magnitude típica do ruído ambiente (calibração).
  double get noiseFloor => _prefs.getDouble('noiseFloor') ?? 2e-4;
  set noiseFloor(double v) => _setDouble('noiseFloor', v);

  /// 0.5 (menos sensível) a 2.0 (mais sensível).
  double get sensitivity => _prefs.getDouble('sensitivity') ?? 1.0;
  set sensitivity(double v) => _setDouble('sensitivity', v);

  bool get calibrated => _prefs.getBool('calibrated') ?? false;
  set calibrated(bool v) => _setBool('calibrated', v);

  bool get unlockAll => _prefs.getBool('unlockAll') ?? false;
  set unlockAll(bool v) => _setBool('unlockAll', v);

  bool get beatFlash => _prefs.getBool('beatFlash') ?? true;
  set beatFlash(bool v) => _setBool('beatFlash', v);

  bool get vibrateOnBar => _prefs.getBool('vibrateOnBar') ?? false;
  set vibrateOnBar(bool v) => _setBool('vibrateOnBar', v);

  /// Som de piano ao tocar nas teclas da tela.
  bool get keySound => _prefs.getBool('keySound') ?? true;
  set keySound(bool v) => _setBool('keySound', v);

  /// Tocar sozinho a mão que não está sendo treinada.
  bool get autoOtherHand => _prefs.getBool('autoOtherHand') ?? true;
  set autoOtherHand(bool v) => _setBool('autoOtherHand', v);

  /// Guia: tocar a música inteira junto (para ouvir como deve soar).
  bool get guideSound => _prefs.getBool('guideSound') ?? false;
  set guideSound(bool v) => _setBool('guideSound', v);

  /// 0.0 a 1.0
  double get volume => _prefs.getDouble('volume') ?? 0.9;
  set volume(double v) => _setDouble('volume', v);

  void _setInt(String k, int v) {
    _prefs.setInt(k, v);
    notifyListeners();
  }

  void _setDouble(String k, double v) {
    _prefs.setDouble(k, v);
    notifyListeners();
  }

  void _setBool(String k, bool v) {
    _prefs.setBool(k, v);
    notifyListeners();
  }
}
