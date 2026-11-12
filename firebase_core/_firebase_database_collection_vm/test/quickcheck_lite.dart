import 'dart:math';

/// Minimal random-data generators replacing the old `dart_quickcheck`
/// dependency.
class Generator<T> {
  const Generator(this._next);

  final T Function() _next;

  T next() => _next();
}

final Random _random = Random(42);

class PrimitiveGenerators {
  static Generator<int> integers() =>
      Generator<int>(() => _random.nextInt(2000) - 1000);

  static Generator<bool> booleans() =>
      Generator<bool>(_random.nextBool);

  static Generator<int> fixedValuesSingle(int value) =>
      Generator<int>(() => value);
}

class CombinedGeneratorsIterables {
  static Iterable<Map<K, V>> someMaps<K, V>(
      Generator<K> keys, Generator<V> values) {
    return someMapsFromKeysAndValuesOfSize<K, V>(
        keys, values, Generator<int>(() => _random.nextInt(60)));
  }

  static Iterable<Map<K, V>> someMapsFromKeysAndValuesOfSize<K, V>(
      Generator<K> keys, Generator<V> values, Generator<int> size) sync* {
    for (int i = 0; i < 100; i++) {
      final int n = size.next();
      final Map<K, V> map = <K, V>{};
      while (map.length < n) {
        map[keys.next()] = values.next();
      }
      yield map;
    }
  }
}
