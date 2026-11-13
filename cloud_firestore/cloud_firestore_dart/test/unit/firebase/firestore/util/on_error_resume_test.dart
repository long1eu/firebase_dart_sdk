import 'dart:async';

import 'package:cloud_firestore_dart/src/firebase/firestore/util/on_error_resume.dart.dart';
import 'package:test/test.dart';

Future<void> _pump() => Future<void>.delayed(Duration.zero);

void main() {
  late StreamController<int> source;
  late StreamController<int> recovery;
  late List<Object> errors;
  late List<int> values;
  late bool done;
  late StreamSubscription<int> subscription;

  setUp(() {
    source = StreamController<int>();
    recovery = StreamController<int>();
    errors = <Object>[];
    values = <int>[];
    done = false;
    subscription = source.stream
        .transform(
          OnErrorResumeStreamTransformer<int>((dynamic error) {
            errors.add(error as Object);
            return recovery.stream;
          }),
        )
        .listen(values.add, onDone: () => done = true);
  });

  tearDown(() async {
    await subscription.cancel();
  });

  test('values pass through and done closes the output', () async {
    source
      ..add(1)
      ..add(2);
    await source.close();
    await _pump();
    expect(values, <int>[1, 2]);
    expect(done, isTrue);
    expect(recovery.hasListener, isFalse);
  });

  test('an error switches to the recovery stream', () async {
    source
      ..add(1)
      ..addError(StateError('boom'));
    await _pump();
    expect(errors.single, isA<StateError>());
    expect(source.hasListener, isFalse, reason: 'the source is cancelled');
    expect(recovery.hasListener, isTrue);

    recovery.add(7);
    await recovery.close();
    await _pump();
    expect(values, <int>[1, 7]);
    expect(done, isTrue);
  });

  test('pause and resume reach the source', () async {
    subscription.pause();
    await _pump();
    expect(source.isPaused, isTrue);

    source.add(1);
    await _pump();
    expect(values, isEmpty, reason: 'nothing is delivered while paused');

    subscription.resume();
    await _pump();
    expect(source.isPaused, isFalse);
    expect(values, <int>[1]);
  });

  test(
    'after the switch, pause and resume reach the recovery stream',
    () async {
      source.addError(StateError('boom'));
      await _pump();

      subscription.pause();
      await _pump();
      expect(recovery.isPaused, isTrue);

      recovery.add(3);
      await _pump();
      expect(values, isEmpty);

      subscription.resume();
      await _pump();
      expect(recovery.isPaused, isFalse);
      expect(values, <int>[3]);
    },
  );

  test('cancel cancels the recovery stream', () async {
    source.addError(StateError('boom'));
    await _pump();
    expect(recovery.hasListener, isTrue);
    await subscription.cancel();
    expect(recovery.hasListener, isFalse);
  });

  test('errors of the recovery stream are forwarded', () async {
    final List<Object> outputErrors = <Object>[];
    await subscription.cancel();
    source = StreamController<int>();
    subscription = source.stream
        .transform(
          OnErrorResumeStreamTransformer<int>(
            (dynamic error) => Stream<int>.error(ArgumentError('again')),
          ),
        )
        .listen(values.add, onError: outputErrors.add);
    source.addError(StateError('boom'));
    await _pump();
    await _pump();
    expect(outputErrors.single, isA<ArgumentError>());
  });
}
