import 'package:flutter/widgets.dart';

import '../library/bitmidi_api.dart';
import '../library/song_repository.dart';
import 'settings.dart';

/// Serviços do app disponíveis para todas as telas.
class AppServices extends InheritedWidget {
  const AppServices({
    super.key,
    required this.settings,
    required this.repository,
    required this.bitMidi,
    required super.child,
  });

  final Settings settings;
  final SongRepository repository;
  final BitMidiApi bitMidi;

  static AppServices of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppServices>()!;

  @override
  bool updateShouldNotify(AppServices old) => false;
}
