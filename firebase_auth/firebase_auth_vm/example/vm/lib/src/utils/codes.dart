// File created by
// Lung Razvan <long1eu>
// on 11/12/2019

part of firebase_auth_example;

extension NewString on String {
  String get bold => '$_bold$this';

  String get red => '$_red$this';

  String get green => '$_green$this';

  String get yellow => '$_yellow$this';

  String get cyan => '$_cyan$this';

  String get reverse => '$_reverse$this';

  String get underline => '\x1B[4m$this';

  String get concealed => '\x1B[8m$this';

  String get reset => '${this}$_reset';
}

const String _removeLastLine = '\x1B[1A\x1B[0K';
const String _clearScreen = '\x1B[J';
const String _clearLine = '\x1B[1K';
const String _moveUp = '\x1B[A';
const String _moveUpOne = '\x1B[1A';
const String _moveDown = '\x1B[B';
const String _moveRight = '\x1B[C';
const String _moveLeft = '\x1B[D';

const String saveCursor = '\x1B[s';
const String restoreCursor = '\x1B[u';

final String _bold = hasColor ? '\x1B[1m' : '';
final String _red = hasColor ? '\x1B[31m' : '';
final String _green = hasColor ? '\x1B[32m' : '';
final String _yellow = hasColor ? '\x1B[33m' : '';
final String _cyan = hasColor ? '\x1B[36m' : '';
final String _reverse = hasColor ? '\x1B[7m' : '';
final String _reset = hasColor ? '\x1B[0m' : '';
