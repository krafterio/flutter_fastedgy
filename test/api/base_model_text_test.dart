/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

/// Régression : une moitié de paire de substitution arrivée avec les données
/// (nom de contact tronqué par l'OS, titre coupé par un autre client) fait
/// tomber l'écran qui l'affiche, et le champ de saisie qui la contient au
/// premier retour arrière.
library;

import 'package:flutter_fastedgy/flutter_fastedgy.dart';
import 'package:flutter_test/flutter_test.dart';

class _Item extends BaseModel<_Item> {
  _Item(super.data);

  String? get label => getString('label');
}

void main() {
  final loneHigh = String.fromCharCode(0xD83C);
  final loneLow = String.fromCharCode(0xDF38);

  test('retire les moitiés orphelines', () {
    expect(_Item({'label': 'Marie$loneHigh'}).label, 'Marie');
    expect(_Item({'label': '${loneLow}Marie'}).label, 'Marie');
  });

  test('garde les emojis entiers', () {
    expect(_Item({'label': '🌸 Marie'}).label, '🌸 Marie');
  });

  test('laisse le texte ordinaire intact', () {
    expect(_Item({'label': 'Courses du samedi'}).label, 'Courses du samedi');
    expect(_Item({'label': null}).label, isNull);
  });
}
