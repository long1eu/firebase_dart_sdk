// File created by
// Lung Razvan <long1eu>
// on 26/11/2019

import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  final StringBuffer buffer = StringBuffer();
  final List<dynamic> data = jsonDecode(File('./lib/src/util/errors.json').readAsStringSync());

  buffer.writeln(header);
  for (dynamic item in data) {
    buffer.writeln('''      case \'${item['codeName']}\':
        return ${item['name']};''');
  }

  buffer.writeln(defaultValue);

  for (dynamic item in data) {
    buffer
      ..writeln('  /// ${item['doc']}')
      ..writeln(
          '  static const FirebaseAuthError ${item['name']} = FirebaseAuthError._(${item['code']}, \'${_escape(item['message'])}\',);');
  }
  buffer.writeln('''\n  @override
  String toString() => 'FirebaseAuthError(\$code, \$message)';
}''');
  final File file = File('./lib/src/util/errors.dart')..writeAsStringSync(buffer.toString());
  final ProcessResult result = Process.runSync('dartfmt', <String>[file.absolute.path, '-l', '120']);
  file.writeAsStringSync(result.stdout.toString());
}

String _escape(String item) {
  if (item == null) {
    return null;
  }
  return item.replaceAll('\'', '\\\'');
}

const String header = '''part of firebase_auth_vm;
class FirebaseAuthError extends FirebaseError {    
  factory FirebaseAuthError(String name, String message) {
    switch (name) {''';

const String defaultValue = '''      default:
        return FirebaseAuthError._(-1, '\$name\${message.isEmpty ? '' : ' : \$message'}');
    }
  }
  

    const FirebaseAuthError._(this.code, String message)
        : assert(code != null),
          super(message);
    
  
  final int code;  
''';
