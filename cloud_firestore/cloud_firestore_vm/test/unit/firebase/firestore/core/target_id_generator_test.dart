// File created by
// Lung Razvan <long1eu>
// on 27/09/2018

import 'package:cloud_firestore_vm/src/firebase/firestore/core/target_id_generator.dart';
import 'package:test/test.dart';

void main() {
  test('testConstructor', () {
    expect(TargetIdGenerator.forQueryCache(0).nextId, 2);
    expect(TargetIdGenerator.forSyncEngine().nextId, 1);
  });

  test('testIncrement', () {
    TargetIdGenerator gen = TargetIdGenerator(0, 0);
    expect(gen.nextId, 0);
    expect(gen.nextId, 2);
    expect(gen.nextId, 4);
    expect(gen.nextId, 6);

    gen = TargetIdGenerator(0, 46);
    expect(gen.nextId, 46);
    expect(gen.nextId, 48);
    expect(gen.nextId, 50);
    expect(gen.nextId, 52);
    expect(gen.nextId, 54);

    gen = TargetIdGenerator(1, 1);
    expect(gen.nextId, 1);
    expect(gen.nextId, 3);
    expect(gen.nextId, 5);

    gen = TargetIdGenerator(1, 45);
    expect(gen.nextId, 45);
    expect(gen.nextId, 47);
    expect(gen.nextId, 49);
    expect(gen.nextId, 51);
    expect(gen.nextId, 53);
  });
}
