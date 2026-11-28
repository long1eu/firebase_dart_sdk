import 'package:firebase_transport_dart/firebase_transport_dart.dart';
import 'package:test/test.dart';

void main() {
  test('an id logs once', () {
    final List<String> logged = <String>[];
    final LogOnce once = LogOnce(logged.add);
    once('a', 'first');
    once('a', 'second');
    once('a', 'third');
    expect(logged, <String>['first']);
  });

  test('different ids each log', () {
    final List<String> logged = <String>[];
    final LogOnce once = LogOnce(logged.add);
    once('a', 'one');
    once('b', 'two');
    expect(logged, <String>['one', 'two']);
  });

  test('a null sink drops every message and does not throw', () {
    final LogOnce once = LogOnce(null);
    once('a', 'first');
    once('a', 'second');
    once.reset('a');
    once('a', 'third');
  });

  test('the 257th id is not logged', () {
    final List<String> logged = <String>[];
    final LogOnce once = LogOnce(logged.add);
    for (int i = 0; i < 256; i++) {
      once('id$i', 'message $i');
    }
    expect(logged, hasLength(256));
    once('id256', 'message 256');
    expect(logged, hasLength(256));
    expect(logged, isNot(contains('message 256')));
  });

  test('a full helper still drops a known id, as before', () {
    final List<String> logged = <String>[];
    final LogOnce once = LogOnce(logged.add);
    for (int i = 0; i < 256; i++) {
      once('id$i', 'message $i');
    }
    once('id0', 'again');
    expect(logged, hasLength(256));
  });

  test('reset makes an id log again', () {
    final List<String> logged = <String>[];
    final LogOnce once = LogOnce(logged.add);
    once('a', 'first');
    once.reset('a');
    once('a', 'second');
    once('a', 'third');
    expect(logged, <String>['first', 'second']);
  });

  test('reset of an id never seen does nothing', () {
    final List<String> logged = <String>[];
    final LogOnce once = LogOnce(logged.add);
    once.reset('never');
    once('never', 'first');
    once('never', 'second');
    expect(logged, <String>['first']);
  });

  test(
    'with 256 ids full, a reset id logs again and a new id is still dropped',
    () {
      final List<String> logged = <String>[];
      final LogOnce once = LogOnce(logged.add);
      for (int i = 0; i < 256; i++) {
        once('id$i', 'message $i');
      }
      once.reset('id7');
      once('id7', 'again');
      expect(logged, hasLength(257));
      expect(logged.last, 'again');
      once('id7', 'third');
      expect(logged, hasLength(257));
      once('new', 'new message');
      expect(logged, hasLength(257));
      expect(logged, isNot(contains('new message')));
    },
  );
}
