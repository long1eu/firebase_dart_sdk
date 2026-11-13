# Pipelines (preview, Enterprise only)

**Preview, Enterprise only.** Pipelines are queries made of stages and expressions that the
server executes. They need a Firestore **Enterprise edition** database, and the API is
experimental: it follows the JS and Android SDKs, which are still changing, and may change in
any release. Everything below was verified against the Enterprise edition emulator only, never
against a production Enterprise database.

## Requirements

- An Enterprise edition database. A Standard edition database, and the emulator in its default
  edition, answer `invalid-argument: ExecutePipeline requires the Database Edition to be
  enterprise`. Start the emulator with `--database-edition enterprise` to try pipelines locally
  (see [The emulator and testing](emulator_and_testing.md)).
- The separate library `package:cloud_firestore_dart/pipelines.dart`, next to the main one. Its
  helper functions have short names (`field`, `constant`, `and`, `or`, `not`, `map`, ...); import
  it with a prefix if they clash with names of your own.

## A first pipeline

```dart
import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/pipelines.dart';

final PipelineSnapshot snapshot = await firestore
    .pipeline()
    .collection('books')
    .where(field('rating').greaterThan(4))
    .sort([field('rating').descending()])
    .limit(10)
    .execute();

for (final PipelineResult result in snapshot.results) {
  print('${result.id}: ${result.data()}');
}
```

A pipeline is immutable: every stage method returns a new pipeline. `execute()` sends it to the
server with one `ExecutePipeline` request.

## What is different from queries

- **Server only.** A pipeline does not read or update the local cache, does not see pending
  writes, fails with `unavailable` while offline, and cannot be listened to. Evaluation against
  the cache and real-time pipelines are not done yet.
- **Results are maps.** A result is a document (`ref`, `id`, `createTime`, `updateTime` are set)
  only while the pipeline filters, sorts and limits. After `select`, `aggregate`, `distinct`,
  `unnest` and similar stages it is a plain map and those are null. There are no typed results;
  converters are ignored.
- **More than queries can do**: computed fields, aggregations with groups, joins through
  subqueries, `union`, `unnest`, and write stages.

## Building blocks

```dart
import 'package:cloud_firestore_dart/pipelines.dart';

// Computed fields and grouped aggregations.
await firestore
    .pipeline()
    .collection('books')
    .addFields([field('title').toUpper().as('upperTitle')])
    .aggregate(
      [countAll().as('count'), field('rating').average().as('averageRating')],
      groups: ['genre'],
    )
    .execute();

// Boolean expressions combine with and / or / not.
await firestore
    .pipeline()
    .collectionGroup('reviews')
    .where(or(field('stars').equal(5), field('featured').equal(true)))
    .select(['title', 'stars'])
    .execute();

// An existing query as a pipeline: the same documents in the same order.
final PipelineSnapshot same = await firestore
    .pipeline()
    .createFrom(users.where('age', isGreaterThanOrEqualTo: 18).orderBy('age'))
    .execute();
```

- **Sources**: `collection`, `collectionGroup`, `database`, `documents`, `literals`,
  `subcollection`, and `createFrom` (a `Query`), `createFromAggregateQuery`,
  `createFromVectorQuery`.
- **Stages**: `where`, `select`, `addFields`, `removeFields`, `sort`, `limit`, `offset`,
  `aggregate`, `distinct`, `findNearest`, `sample`, `union`, `unnest`, `replaceWith`, `define`,
  and the write stages below.
- **Expressions**: comparisons, arithmetic and math, strings and regular expressions, arrays and
  maps, timestamps, vector distances, types and missing values, and the aggregates (`count`,
  `countAll`, `countIf`, `countDistinct`, `sum`, `average`, `minimum`, `maximum`, `first`,
  `last`, `arrayAgg`, ...). The API reference of the library lists them all.
- **Anything this package has no helper for yet**: `FunctionExpression('server_name', [args])`,
  `AggregateFunction('server_name', [args])`, `Pipeline.rawStage(name, args)`, and the
  `rawOptions` parameter of every stage.

## From an existing query

`createFrom(query)` converts a `Query` (filters with named arguments or
`Filter.or` / `Filter.and`, orderings, cursors, `limit`, `limitToLast`, collection groups, BSON
operands), `createFromAggregateQuery` an `AggregateQuery` and `createFromVectorQuery` a
`findNearest` query. The integration tests compare each shape with `query.get(Source.server)`.
Known difference: a cursor (`startAt`, `endBefore`, ...) on a field that holds values of
several types only returns the documents whose value has the type of the cursor value; a
classic cursor is a position in the order of all types. The converter of a query is ignored:
pipeline results are maps (as in the JS and Android SDKs, which have no typed pipeline results
either).

## Variables, subqueries and lambdas

```dart
import 'package:cloud_firestore_dart/pipelines.dart';

// A subquery: every author with the number of their books.
await firestore
    .pipeline()
    .collection('authors')
    .define([field('name').as('author')])
    .select([
      'name',
      firestore
          .pipeline()
          .collection('books')
          .where(field('author').equal(variable('author')))
          .aggregate([countAll().as('count')])
          .toScalarExpression()
          .as('books'),
    ])
    .execute();

// A lambda over an array.
await firestore
    .pipeline()
    .collection('books')
    .select([field('tags').arrayFilter((tag) => tag.startsWith('sci')).as('tags')])
    .execute();
```

- **Variables and subqueries**: `define([...])` with `variable(name)`, `currentDocument()`,
  `getField`, `firestore.pipeline().subcollection(path)`, and `toArrayExpression()` /
  `toScalarExpression()` to use a pipeline inside a stage of another one.
- **Lambdas**: `arrayFilter((e) => e.greaterThan(1))`, `arrayTransform`,
  `arrayTransformWithIndex`; the callback builds the expression once, from a variable that
  stands for the element (name it with `alias` when lambdas are nested).

## Write stages

`update`, `delete`, `insert` and `upsert` end a pipeline and change documents on the server.
The result is one row with `documents_modified`.

```dart
import 'package:cloud_firestore_dart/pipelines.dart';

final PipelineSnapshot written = await firestore
    .pipeline()
    .collection('books')
    .where(field('published').lessThan(1900))
    .update(transformedFields: [constant(true).as('classic')])
    .execute(atomic: true); // in one transaction, committed at the end
print(written.results.single.get('documents_modified'));
```

With `execute(atomic: true)` the pipeline runs in a transaction that is committed at the end. The
server demands that for `insert` and `upsert` of documents read from a collection, and after
an aggregation, `unnest`, `union` or a subquery. These writes bypass the local cache and the
write queue: they fail while offline, and cached copies are stale until the server reports the
change. The emulator (v1.22.0) never reports it: listeners and `get(Source.server)` return the
old version until a regular write touches the document, while pipelines read the new one.

## In a transaction

```dart
import 'package:cloud_firestore_dart/pipelines.dart';

final PipelineSnapshot inSnapshot = await firestore.runTransaction(
  (Transaction transaction) => transaction.execute(
    firestore.pipeline().collection('books').where(field('genre').equal('Fantasy')),
  ),
  options: TransactionOptions(readOnly: true),
);
```

Pipelines run only in read-only transactions, in the snapshot that all reads of the transaction
see. Read-write transactions, and pipelines with write stages, are rejected.

## Explain

```dart
import 'package:cloud_firestore_dart/pipelines.dart';

final PipelineSnapshot explained = await firestore
    .pipeline()
    .collection('books')
    .where(field('rating').greaterThan(4))
    .execute(explainOptions: PipelineExplainOptions(mode: PipelineExplainMode.analyze));
print(explained.explainStats);
```

The option names are those of the Node.js server SDK. The emulator ignores them, so no
explanation was seen in a test.

## Beta server features

Full-text search and window functions are beta upstream. They are encoded as the JS SDK encodes
them, but the emulator rejects both, so they were checked for their encoding only:
`search(documentMatches('...'), sort: [score().descending()])`, and
`addWindowFields(WindowSpec(...), [rank().as('rank'), field('n').sum().over(WindowFrame.documents(preceding: 1, following: 1)).as('moving')])`.
The emulator also rejects `geoDistance`. The emulator also denies the `literals` source to clients that are subject to
security rules.

More examples: [`example/pipelines.dart`](../../cloud_firestore/cloud_firestore_dart/example/pipelines.dart).
To run the repository's pipeline tests, see
[The emulator and testing](emulator_and_testing.md#testing-this-repository).
