// File created by
// Lung Razvan <long1eu>
// on 27/09/2018

import 'package:firebase_firestore/src/firebase/firestore/core/target_id_generator.dart';
import 'package:test/test.dart';

void main() {
  test('testConstructor', () {
    expect(TargetIdGenerator.getLocalStoreIdGenerator(0).nextId(), 2);
    expect(TargetIdGenerator.getSyncEngineGenerator(0).nextId(), 1);
  });

  test('testSkipPast', () {
    TargetIdGenerator gen = TargetIdGenerator(1, -1);
    expect(1, gen.nextId());

    gen = TargetIdGenerator(1, 2);
    expect(gen.nextId(), 3);

    gen = TargetIdGenerator(1, 4);
    expect(gen.nextId(), 5);

    for (int i = 4; i < 12; i++) {
      final TargetIdGenerator gen0 = TargetIdGenerator(0, i);
      final TargetIdGenerator gen1 = TargetIdGenerator(1, i);
      expect(gen0.nextId(), i + 2 & ~1);
      expect(gen1.nextId(), i + 1 | 1);
    }

    gen = TargetIdGenerator(1, 12);
    expect(gen.nextId(), 13);

    gen = TargetIdGenerator(0, 22);
    expect(gen.nextId(), 24);
  });

  test('testIncrement', () {
    TargetIdGenerator gen = TargetIdGenerator(0, 0);
    expect(gen.nextId(), 2);
    expect(gen.nextId(), 4);
    expect(gen.nextId(), 6);

    gen = TargetIdGenerator(0, 46);
    expect(gen.nextId(), 48);
    expect(gen.nextId(), 50);
    expect(gen.nextId(), 52);
    expect(gen.nextId(), 54);

    gen = TargetIdGenerator(1, 0);
    expect(gen.nextId(), 1);
    expect(gen.nextId(), 3);
    expect(gen.nextId(), 5);

    gen = TargetIdGenerator(1, 46);
    expect(gen.nextId(), 47);
    expect(gen.nextId(), 49);
    expect(gen.nextId(), 51);
    expect(gen.nextId(), 53);
  });
}
