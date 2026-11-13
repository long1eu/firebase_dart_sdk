// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'package:cloud_firestore_dart/src/firebase/firestore/firestore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/expression.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/pipeline_source.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/window.dart';

/// Adds [pipeline] to [Firestore]. Importing
/// `package:cloud_firestore_dart/pipelines.dart` makes it available.
///
/// **Preview, Enterprise only**: the Pipelines API is experimental, may change
/// in any release and needs a Firestore Enterprise edition database.
extension FirestorePipelines on Firestore {
  /// Starts a pipeline query: choose a source on the returned
  /// [PipelineSource], add stages and call `execute()`.
  ///
  /// ```dart
  /// final snapshot = await firestore
  ///     .pipeline()
  ///     .collection('books')
  ///     .where(field('rating').greaterThan(4))
  ///     .execute();
  /// ```
  ///
  /// Pipelines need a Firestore **Enterprise edition** database and are
  /// always executed by the server (no cache, no offline support, no
  /// listeners).
  ///
  /// **Preview, Enterprise only**: the Pipelines API is experimental, may change
  /// in any release and needs a Firestore Enterprise edition database.
  PipelineSource pipeline() => PipelineSource(this);
}

/// A reference to the field [nameOrPath]: a dot-separated `String` or a
/// `FieldPath`.
Field field(Object nameOrPath) => Field.of(nameOrPath);

/// The fixed [value]: `null`, `bool`, `int`, `double`, `String`, `DateTime`,
/// `Timestamp`, `GeoPoint`, `Blob`, `VectorValue`, `DocumentReference`, or
/// lists and maps of those.
Constant constant(Object? value) => Constant(value);

/// Whether all of the conditions hold.
BooleanExpression and(
  BooleanExpression first,
  BooleanExpression second, [
  List<BooleanExpression> more = const <BooleanExpression>[],
]) => first.and(second, more);

/// Whether at least one of the conditions holds.
BooleanExpression or(
  BooleanExpression first,
  BooleanExpression second, [
  List<BooleanExpression> more = const <BooleanExpression>[],
]) => first.or(second, more);

/// Whether an odd number of the conditions hold.
BooleanExpression xor(
  BooleanExpression first,
  BooleanExpression second, [
  List<BooleanExpression> more = const <BooleanExpression>[],
]) => first.xor(second, more);

/// The negation of [condition].
BooleanExpression not(BooleanExpression condition) => condition.not();

/// [thenValue] if [condition] holds, [elseValue] otherwise.
FunctionExpression conditional(
  BooleanExpression condition,
  Object? thenValue,
  Object? elseValue,
) => condition.conditional(thenValue, elseValue);

/// Counts all inputs of an aggregation.
AggregateFunction countAll() => AggregateFunction('count');

/// Counts the inputs for which [condition] holds.
AggregateFunction countIf(BooleanExpression condition) => condition.countIf();

/// An array built from [elements], which may be values or expressions.
FunctionExpression array(List<Object?> elements) =>
    FunctionExpression('array', elements);

/// A map built from [entries], whose values may be values or expressions.
FunctionExpression map(Map<String, Object?> entries) =>
    toExpression(entries) as FunctionExpression;

/// The time at which the server evaluates the pipeline.
FunctionExpression currentTimestamp() =>
    FunctionExpression('current_timestamp');

/// A random number between 0 (inclusive) and 1 (exclusive).
FunctionExpression rand() => FunctionExpression('rand');

/// Whether none of the conditions holds.
BooleanExpression nor(
  BooleanExpression first,
  BooleanExpression second, [
  List<BooleanExpression> more = const <BooleanExpression>[],
]) => first.nor(second, more);

/// The result that follows the first condition that holds.
///
/// [others] continues the list of condition/result pairs and may end with a
/// single default result:
///
/// ```dart
/// switchOn(field('n').equal(1), 'one', [field('n').equal(2), 'two', 'many']);
/// ```
FunctionExpression switchOn(
  BooleanExpression condition,
  Object? result, [
  List<Object?> others = const <Object?>[],
]) => FunctionExpression('switch_on', <Object?>[condition, result, ...others]);

/// A reference to the variable [name], defined with `Pipeline.define` in this
/// pipeline or in a pipeline that contains this one as a subquery.
VariableExpression variable(String name) => VariableExpression(name);

/// The document that the enclosing stage is processing, as a map. Useful in
/// `Pipeline.define` to hand the outer document to a subquery.
FunctionExpression currentDocument() => FunctionExpression('current_document');

/// Whether the document matches the full-text search [query] (a `String` in
/// the search query language, or an expression that evaluates to one).
///
/// Only allowed in the query of `Pipeline.search`:
///
/// ```dart
/// firestore.pipeline().collection('restaurants').search(
///   documentMatches('waffles OR pancakes'),
///   sort: [score().descending()],
/// );
/// ```
///
/// **Not verified against a backend**: the Enterprise emulator does not
/// support search.
BooleanExpression documentMatches(Object query) =>
    BooleanExpression(FunctionExpression('document_matches', <Object?>[query]));

/// The relevance of the document to the text conditions (such as
/// [documentMatches]) of the enclosing `Pipeline.search` query; 0 when the
/// query has none. Only allowed in a `search` stage.
///
/// **Not verified against a backend**: the Enterprise emulator does not
/// support search.
FunctionExpression score() => FunctionExpression('score');

/// The rank of the current input in its window partition, by the sort order
/// of the window; tied inputs share a rank. For `Pipeline.addWindowFields`.
///
/// **Beta**: window functions are a preview feature of the server.
WindowFunction rank() => WindowFunction('rank');
