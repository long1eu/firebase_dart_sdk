import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:test/test.dart';

const FirebaseOptions _options = FirebaseOptions(
  apiKey: 'key',
  applicationId: 'app-id',
);

void main() {
  tearDown(FirebaseApp.clearInstancesForTest);

  test('create and get', () {
    final FirebaseApp app = FirebaseApp.withOptions(_options);
    expect(FirebaseApp.instance, same(app));
    expect(FirebaseApp.getInstance(FirebaseApp.defaultAppName), same(app));

    final FirebaseApp other = FirebaseApp.withOptions(_options, name: ' x ');
    expect(other.name, 'x');
    expect(FirebaseApp.getInstance('x'), same(other));
    expect(FirebaseApp.apps, hasLength(2));
  });

  test('creating the same name twice throws', () {
    FirebaseApp.withOptions(_options, name: 'x');
    expect(
      () => FirebaseApp.withOptions(_options, name: 'x'),
      throwsA(isA<StateError>()),
    );
  });

  test('delete removes the app from the registry', () {
    final FirebaseApp app = FirebaseApp.withOptions(_options, name: 'x');
    app.delete();
    expect(FirebaseApp.apps, isEmpty);
    expect(() => app.name, throwsA(isA<StateError>()));
  });

  test('delete is idempotent and emits once', () async {
    final FirebaseApp app = FirebaseApp.withOptions(_options, name: 'x');
    final Future<List<String>> events = app.onDeleteApp.take(1).toList();
    app.delete();
    app.delete();
    expect(await events, <String>['x']);
  });

  test('an app can be re-created after delete', () {
    final FirebaseApp first = FirebaseApp.withOptions(_options);
    first.delete();
    expect(() => FirebaseApp.instance, throwsA(isA<StateError>()));

    final FirebaseApp second = FirebaseApp.withOptions(_options);
    expect(FirebaseApp.instance, same(second));
    expect(identical(first, second), isFalse);
    expect(second.name, FirebaseApp.defaultAppName);
    expect(() => first.name, throwsA(isA<StateError>()));
  });

  test(
    'missing and deleted apps report "doesn\'t exist", not "was deleted"',
    () {
      final FirebaseApp a = FirebaseApp.withOptions(_options, name: 'a');
      FirebaseApp.withOptions(_options, name: 'b').delete();

      expect(
        () => FirebaseApp.getInstance('nope'),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            allOf(
              contains('exist'),
              contains('Available app names: a'),
              isNot(contains('was deleted')),
            ),
          ),
        ),
      );
      expect(
        () => FirebaseApp.getInstance('b'),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            contains('exist'),
          ),
        ),
      );
      expect(a.name, 'a');
    },
  );

  test('using a deleted app says it was deleted', () {
    final FirebaseApp app = FirebaseApp.withOptions(_options, name: 'x');
    app.delete();
    expect(
      () => app.options,
      throwsA(
        isA<StateError>().having(
          (StateError e) => e.message,
          'message',
          contains('was deleted'),
        ),
      ),
    );
  });
}
