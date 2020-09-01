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
    final String codeName = '${item['codeName']}'.toLowerCase().replaceAll('_', '-');
    buffer
      ..writeln('  /// ${item['doc']}')
      ..writeln(
          '  static final FirebaseAuthError ${item['name']} = FirebaseAuthError._(${item['code']}, \'${_escape(item['message'])}\', \'$codeName\',);');
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
        return FirebaseAuthError._(-1, '\$name\${message.isEmpty ? '' : ' : \$message'}', 'unknown');
    }
  }
  

    FirebaseAuthError._(this.code, String message, this.codeName)
        : assert(code != null),
          assert(codeName != null),
          super(message);
    
  
  final int code;  
  final String codeName;  
''';
