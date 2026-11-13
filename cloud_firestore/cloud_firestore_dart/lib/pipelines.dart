/// Firestore Pipelines: queries made of stages and expressions that the
/// server executes (Enterprise edition databases only).
///
/// **Preview**: this API is experimental and may change in any release.
///
/// ```dart
/// import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
/// import 'package:cloud_firestore_dart/pipelines.dart';
///
/// final snapshot = await firestore
///     .pipeline()
///     .collection('books')
///     .where(field('rating').greaterThan(4))
///     .aggregate([field('rating').average().as('avg')], groups: ['genre'])
///     .execute();
/// ```
///
/// The helper functions have short names (`field`, `and`, `or`, `not`, ...);
/// import the library with a prefix if they clash with your own names.
library cloud_firestore_dart.pipelines;

export 'src/firebase/firestore/pipeline/explain_options.dart';
export 'src/firebase/firestore/pipeline/expression.dart'
    hide PipelineEncoder, RawValueExpression, fieldOrExpression, toExpression;
export 'src/firebase/firestore/pipeline/functions.dart';
export 'src/firebase/firestore/pipeline/pipeline.dart';
export 'src/firebase/firestore/pipeline/pipeline_result.dart'
    hide decodePipelineResponses;
export 'src/firebase/firestore/pipeline/pipeline_source.dart';
export 'src/firebase/firestore/pipeline/pipeline_transaction.dart';
export 'src/firebase/firestore/pipeline/window.dart';
