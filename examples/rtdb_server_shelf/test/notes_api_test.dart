// Pure tests: nothing here needs a database.

import 'package:rtdb_server_shelf/database_from_env.dart';
import 'package:rtdb_server_shelf/notes_api.dart';
import 'package:test/test.dart';

void main() {
  test('limit defaults, bounds and rejects', () {
    expect(parseLimit(null), defaultLimit);
    expect(parseLimit('5'), 5);
    expect(parseLimit('0'), isNull);
    expect(parseLimit('${maxLimit + 1}'), isNull);
    expect(parseLimit('x'), isNull);
  });

  test('bodies must be JSON objects', () {
    expect(parseObject('{"a":1}'), <String, Object?>{'a': 1});
    expect(parseObject('[1]'), isNull);
    expect(parseObject('nope'), isNull);
  });

  test('server-sent event framing', () {
    expect(
      sseEvent('value', <String, Object?>{'a': 1}),
      'event: value\ndata: {"a":1}\n\n',
    );
  });

  test('the environment must name a backend', () {
    expect(
      () => databaseFromEnvironment(environment: <String, String>{}),
      throwsA(isA<ConfigurationError>()),
    );
    expect(
      () => databaseFromEnvironment(
        environment: <String, String>{'FIREBASE_DATABASE_EMULATOR_HOST': 'x'},
      ),
      throwsA(isA<ConfigurationError>()),
    );
  });
}
