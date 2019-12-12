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

const String _tab = '    ';
const String _removeLastLine = '\x1B[1A\x1B[0K';
const String _clearScreen = '\x1B[J';
const String _clearLine = '\x1B[1K';
const String _moveUp = '\x1B[A';
const String _moveUpOne = '\x1B[1A';
const String _moveDown = '\x1B[B';
const String _moveRight = '\x1B[C';
const String _moveLeft = '\x1B[D';

final String _bold = hasColor ? '\x1B[1m' : ''; // used for shard titles
final String _red = hasColor ? '\x1B[31m' : ''; // used for errors
final String _green = hasColor ? '\x1B[32m' : ''; // used for section titles, commands
final String _yellow = hasColor ? '\x1B[33m' : ''; // unused
final String _cyan = hasColor ? '\x1B[36m' : ''; // used for paths
final String _reverse = hasColor ? '\x1B[7m' : ''; // used for clocks
final String _reset = hasColor ? '\x1B[0m' : '';

const String hideCursor = '\x9B\x3F\x32\x35\x6C';
const String showCursor = '\x9B\x3F\x32\x35\x68';
