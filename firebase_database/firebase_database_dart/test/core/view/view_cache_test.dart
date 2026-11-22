// CacheNode (Android `core/view/CacheNode.java`) and ViewCache (JS `core/view/ViewCache.ts`).
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/children_node.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/view/cache_node.dart';
import 'package:firebase_database_dart/src/core/view/view_cache.dart';
import 'package:test/test.dart';

import 'view_helpers.dart';

void main() {
  final Node data = n(<String, Object?>{'a': 1, 'b': 2});

  group('CacheNode', () {
    test('complete and unfiltered: complete everywhere', () {
      final CacheNode c = CacheNode(
        data,
        fullyInitialized: true,
        filtered: false,
      );
      expect(c.isCompleteForPath(Path.empty), isTrue);
      expect(c.isCompleteForPath(Path('z/y')), isTrue);
      expect(c.isCompleteForChild(k('z')), isTrue);
    });

    test('complete but filtered: only for the children it has', () {
      final CacheNode c = CacheNode(
        data,
        fullyInitialized: true,
        filtered: true,
      );
      expect(c.isCompleteForPath(Path.empty), isFalse);
      expect(c.isCompleteForChild(k('a')), isTrue);
      expect(c.isCompleteForPath(Path('a/x')), isTrue);
      expect(c.isCompleteForChild(k('z')), isFalse);
      expect(c.isCompleteForPath(Path('z')), isFalse);
    });

    test('partial: only for the children it has', () {
      final CacheNode c = CacheNode(
        data,
        fullyInitialized: false,
        filtered: false,
      );
      expect(c.isCompleteForPath(Path.empty), isFalse);
      expect(c.isCompleteForChild(k('b')), isTrue);
      expect(c.isCompleteForChild(k('z')), isFalse);
    });

    test('empty and partial: complete nowhere', () {
      final CacheNode c = CacheNode(
        ChildrenNode.empty,
        fullyInitialized: false,
        filtered: false,
      );
      expect(c.isCompleteForPath(Path.empty), isFalse);
      expect(c.isCompleteForChild(k('a')), isFalse);
    });
  });

  group('ViewCache', () {
    final CacheNode partial = CacheNode(
      ChildrenNode.empty,
      fullyInitialized: false,
      filtered: false,
    );
    final ViewCache empty = ViewCache(partial, partial);

    test('complete snaps are null until fully initialised', () {
      expect(empty.completeEventSnap, isNull);
      expect(empty.completeServerSnap, isNull);
    });

    test('updateEventSnap replaces only the event cache', () {
      final ViewCache v = empty.updateEventSnap(
        data,
        complete: true,
        filtered: true,
      );
      expect(v.eventCache.node, data);
      expect(v.eventCache.fullyInitialized, isTrue);
      expect(v.eventCache.filtered, isTrue);
      expect(identical(v.serverCache, partial), isTrue);
      expect(v.completeEventSnap, data);
      expect(v.completeServerSnap, isNull);
    });

    test('updateServerSnap replaces only the server cache', () {
      final ViewCache v = empty.updateServerSnap(
        data,
        complete: true,
        filtered: false,
      );
      expect(v.serverCache.node, data);
      expect(v.serverCache.fullyInitialized, isTrue);
      expect(v.serverCache.filtered, isFalse);
      expect(identical(v.eventCache, partial), isTrue);
      expect(v.completeServerSnap, data);
      expect(v.completeEventSnap, isNull);
    });
  });
}
