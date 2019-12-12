// File created by
// Lung Razvan <long1eu>
// on 11/12/2019

part of firebase_auth_example;

final Console console = Console();

class Console {
  int _characters = 0;

  void print([Object object]) {
    final String string = _normalize(object);
    stdout.write(string);
    _characters += string.length;
  }

  void printTabbed([Object object, int tabCount = 4]) {
    final String string = _normalize(object);
    stdout //
      ..write(''.padRight(tabCount, ' '))
      ..write(string);
    _characters += string.length;
  }

  void println([Object object]) {
    final String string = _normalize(object);
    stdout.writeln(string);
    _characters += string.length;
  }

  void printlnTabbed([Object object, int tabCount = 4]) {
    final String string = _normalize(object);
    stdout
      ..write(''.padRight(tabCount, ' '))
      ..writeln(string);
    _characters += string.length;
  }

  Future<String> get nextLine {
    print(''.bold.cyan);
    return Future<String>(() => stdin.readLineSync()).whenComplete(() => print(''.reset));
  }

  void removeLastLine() {
    stdout //
      ..write('\x1B[$_characters\D') // move left
      ..write('\x1B[K');
    _characters = 0;
  }

  void moveUp() {
    stdout.write(_moveUpOne);
  }

  String _normalize(Object object) {
    return object == null ? '' : object.toString();
  }

  void clearScreen() {
    stdout //
      ..write('\x1B[2J')
      ..write('\x1B[;H');
  }

  void removeLines([int count = 1]) {
    for (int i = 0; i < count; i++) {
      this
        ..moveUp()
        ..removeLastLine();
    }
  }
}
