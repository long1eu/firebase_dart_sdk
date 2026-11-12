// Pipelines (preview): queries made of stages and expressions that the server
// executes. They need an Enterprise edition database, so this example does
// not use the emulator of FIRESTORE_EMULATOR_HOST but a second one that runs
// in Enterprise edition (tool/start_enterprise_emulator.sh in the repository
// starts one on port 8181):
//
//     FIRESTORE_ENTERPRISE_EMULATOR_HOST=127.0.0.1:8181 dart run example/pipelines.dart
//
// Without that variable the example prints a note and exits.

import 'dart:io';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/pipelines.dart';

import 'common.dart';

Future<void> main() async {
  final String? emulator =
      Platform.environment['FIRESTORE_ENTERPRISE_EMULATOR_HOST'];
  if (emulator == null || emulator.isEmpty) {
    print(
      'Skipped: pipelines need an Enterprise edition database. Start an '
      'Enterprise edition emulator and set '
      'FIRESTORE_ENTERPRISE_EMULATOR_HOST (host:port) to run this example.',
    );
    return;
  }
  final int colon = emulator.lastIndexOf(':');
  final Firestore firestore = await Firestore.instanceFor(
    app: exampleApp(),
    settings: FirestoreSettings(cacheSettings: const MemoryCacheSettings())
        .withEmulator(
          emulator.substring(0, colon),
          int.parse(emulator.substring(colon + 1)),
        ),
  );

  final CollectionReference<Map<String, Object?>> books = firestore.collection(
    scratch('books'),
  );
  final WriteBatch batch = firestore.batch();
  <String, Map<String, Object?>>{
    'dune': {
      'title': 'Dune',
      'genre': 'Science Fiction',
      'published': 1965,
      'rating': 4.6,
      'tags': ['politics', 'desert', 'ecology'],
    },
    'hitchhiker': {
      'title': "The Hitchhiker's Guide to the Galaxy",
      'genre': 'Science Fiction',
      'published': 1979,
      'rating': 4.2,
      'tags': ['comedy', 'space'],
    },
    'rings': {
      'title': 'The Lord of the Rings',
      'genre': 'Fantasy',
      'published': 1954,
      'rating': 4.7,
      'tags': ['adventure', 'magic', 'epic'],
    },
    'pride': {
      'title': 'Pride and Prejudice',
      'genre': 'Romance',
      'published': 1813,
      'rating': 4.5,
      'tags': ['classic', 'love'],
    },
  }.forEach((String id, Map<String, Object?> data) {
    batch.set(books.doc(id), data);
  });
  await batch.commit();

  // A pipeline starts at a source and adds stages; execute() sends it to the
  // server. Expressions are built from field(...) and constant(...).
  PipelineSnapshot snapshot = await firestore
      .pipeline()
      .collection(books)
      .where(
        field(
          'rating',
        ).greaterThan(4.4).and(field('published').greaterThan(1900)),
      )
      .sort([field('rating').descending()])
      .select([
        'title',
        field('title').charLength().as('titleLength'),
        field('tags').arrayLength().as('tagCount'),
      ])
      .execute();
  for (final PipelineResult result in snapshot.results) {
    print('well rated: ${result.data()}');
  }

  // While a pipeline only filters, sorts and limits, a result is a document.
  snapshot = await firestore
      .pipeline()
      .collection(books)
      .where(field('tags').arrayContains('space'))
      .execute();
  print(
    'about space: ${snapshot.results.single.id} '
    '(${snapshot.results.single.ref!.path == books.doc('hitchhiker').path})',
  );

  // Grouped aggregation: one row per genre.
  snapshot = await firestore
      .pipeline()
      .collection(books)
      .aggregate(
        [countAll().as('books'), field('rating').average().as('rating')],
        groups: ['genre'],
      )
      .sort([field('genre').ascending()])
      .execute();
  for (final PipelineResult result in snapshot.results) {
    print(
      '${result.get('genre')}: ${result.get('books')} book(s), '
      'average ${(result.get('rating')! as double).toStringAsFixed(2)}',
    );
  }

  // One row per array element, and a lambda over an array.
  snapshot = await firestore
      .pipeline()
      .collection(books)
      .where(field('title').equal('Dune'))
      .select([
        field(
          'tags',
        ).arrayTransform((Expression tag) => tag.toUpper()).as('tags'),
      ])
      .execute();
  print('upper case tags: ${snapshot.results.single.get('tags')}');

  // An existing query can be converted; it returns the same documents.
  final Query<Map<String, Object?>> query = books
      .where('genre', isEqualTo: 'Science Fiction')
      .orderBy('published', Direction.descending);
  snapshot = await firestore.pipeline().createFrom(query).execute();
  print(
    'query: ${[for (final doc in (await query.get()).docs) doc.id]}, '
    'pipeline: ${[for (final result in snapshot.results) result.id]}',
  );

  // A subquery: for every genre, the titles of its books.
  snapshot = await firestore
      .pipeline()
      .collection(books)
      .distinct(['genre'])
      .define([field('genre').as('genre')])
      .select([
        'genre',
        firestore
            .pipeline()
            .collection(books)
            .where(field('genre').equal(variable('genre')))
            .sort([field('title').ascending()])
            .select(['title'])
            .toArrayExpression()
            .as('titles'),
      ])
      .sort([field('genre').ascending()])
      .execute();
  for (final PipelineResult result in snapshot.results) {
    print('${result.get('genre')}: ${result.get('titles')}');
  }

  // Write stages change documents on the server. With atomic: true all of
  // them are written in one transaction.
  snapshot = await firestore
      .pipeline()
      .collection(books)
      .where(field('published').lessThan(1900))
      .update(transformedFields: [constant(true).as('classic')])
      .execute(atomic: true);
  print(
    'marked as classic: ${snapshot.results.single.get('documents_modified')}',
  );

  await firestore.terminate();
}
