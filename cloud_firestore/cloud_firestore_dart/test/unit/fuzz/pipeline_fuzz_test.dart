// Fuzz: the pipelines surface.
//
//  * Random expression trees, also ill-typed ones (any function name, any
//    number and kind of arguments, odd field paths and constants): building
//    them may reject the input with an ArgumentError, encoding them must not
//    crash, the encoding must survive proto3 JSON (the web transport), and
//    the local evaluator must evaluate them the same way twice or reject
//    them with an UnsupportedExpression.
//  * Hostile Pipeline protos (stages of any name with arguments and options
//    of any shape) through the local executor: rows, a PipelineFailure or an
//    UnsupportedExpression, never another error or a hang.
//  * Hostile ExecutePipelineResponse protos through decodePipelineResponses:
//    a snapshot whose results and explanation can be read, or a clean
//    rejection (see isCleanRejection).
//
// There is no decoder from protos back to Expression or Stage objects; the
// local executor is what reads the encoded stages. There is no snapshot JSON
// of pipeline results.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart'
    show Blob, GeoPoint, Timestamp, VectorValue;
import 'package:cloud_firestore_dart/pipelines.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart'
    as model;
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/evaluation/evaluate_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/evaluation/expression_evaluator.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/evaluation/pipeline_executor.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/expression.dart'
    show PipelineEncoder;
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/pipeline_result.dart'
    show decodePipelineResponses;
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/web/proto3_json.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_dart/src/proto/google/firestore/v1/index.dart'
    as pb;
import 'package:cloud_firestore_dart/src/proto/index.dart' as proto;
import 'package:test/test.dart';

import '../../util/fuzz.dart';
import '../../util/property.dart';
import '../../util/property_model.dart';
import '../../util/property_pipeline.dart';
import '../../util/property_pipeline_stages.dart';
import 'proto_deserializer_fuzz_test.dart' show HostileProtos;

final RemoteSerializer remote = RemoteSerializer(modelDatabaseId);
final PipelineEncoder encoder = PipelineEncoder(modelDatabaseId);
final LocalEvaluation local = LocalEvaluation(modelDatabaseId);

/// Function names the server does not know, or that the generator of
/// property_pipeline.dart leaves out.
const List<String> otherFunctionNames = <String>[
  'array_filter', 'array_transform', 'rand', 'current_timestamp', 'nope', //
  '', 'and', 'or', 'not', 'cond', 'switch_on', 'let', 'map_get', 'xor',
  'exists', 'is_error', 'if_error', 'array', 'map', 'sum', 'count',
  'average', 'string_concat', 'regex_match', 'timestamp_add', 'vector_length',
];

const List<String> oddFieldPaths = <String>[
  'n1',
  's1',
  'a1',
  'm1',
  'zz',
  'nul',
  '__name__',
  'm1.a',
  'a1.0',
  'm1.zz.y',
  'a.b.c.d.e.f',
  '😀',
  'é',
  '`',
  'x y',
  '__create_time__',
  '__update_time__',
];

/// Runs [build], which uses the public API to build an expression. An input
/// the API refuses (an ArgumentError, a FormatException) yields null.
Expression? built(Expression Function() build) {
  return acceptOrReject(build, () => 'building an expression');
}

extension on Gen {
  /// Any constant a user may pass, with the BSON types and references.
  Object? constantValue() {
    switch (below(5)) {
      case 0:
        return value(bson: true, reference: modelReference);
      case 1:
        return valueOfKind(
          pick(
            Kind.values
                .where((Kind k) => k != Kind.ref && k != Kind.any)
                .toList(),
          ),
        );
      case 2:
        return pick(<Object?>[
          double.nan,
          double.infinity,
          -0.0,
          9223372036854775807,
          -9223372036854775808,
          '',
          'a' * 1000,
          const <Object?>[],
          const <String, Object?>{},
          const GeoPoint(90, -180),
          const Timestamp(-62135596800, 0),
          Blob(Uint8List(0)),
          VectorValue(const <double>[]),
        ]);
      default:
        return integer();
    }
  }

  /// A random expression tree, typed or not.
  Expression wildExpression(int depth) {
    for (;;) {
      final Expression? expression = _wild(depth);
      if (expression != null) {
        return expression;
      }
    }
  }

  Expression? _wild(int depth) {
    switch (below(depth > 0 ? 12 : 6)) {
      case 0:
        final Object? value = constantValue();
        return built(() => constant(value));
      case 1:
        final String path = pick(oddFieldPaths);
        return built(() => field(path));
      case 2:
        return variable(pick(const <String>['e', 'i', 'x', '']));
      case 3:
        return expression(pick(Kind.values), 0);
      case 4:
        return built(() => field(pick(const <String>['n1', 's1', 'a1', 'm1'])));
      case 5:
        return constant(integer());
      case 6:
      case 7:
        // Any function with any arguments.
        final String name = chance(75)
            ? pick(functionCatalog).name
            : pick(otherFunctionNames);
        final List<Expression> args = <Expression>[
          for (int i = below(5); i > 0; i--) wildExpression(depth - 1),
        ];
        return built(() => FunctionExpression(name, args));
      case 8:
        // A typed call, which the evaluator mostly computes.
        return call(pick(functionCatalog), depth - 1);
      case 9:
        final List<Expression> elements = <Expression>[
          for (int i = below(4); i > 0; i--) wildExpression(depth - 1),
        ];
        return built(() => array(elements));
      case 10:
        final Map<String, Object?> entries = <String, Object?>{
          for (int i = below(4); i > 0; i--)
            pick(const <String>['a', 'b', '', '__type__', 'value', '😀']):
                wildExpression(depth - 1),
        };
        return built(() => map(entries));
      default:
        return lambda(depth - 1);
    }
  }

  /// A pipeline over [data] from the generator of property_pipeline_stages,
  /// with some of its stage arguments and options replaced by random
  /// expressions and values, or with stages dropped or repeated.
  pb.Pipeline mutatedPipeline(PipelineData data) {
    final pb.Pipeline pipeline = stagePipeline(
      PipelineSource(modelFirestore),
      data,
    ).pipeline.toProto(encoder);
    for (int i = below(4); i > 0 && pipeline.stages.isNotEmpty; i--) {
      final int index = below(pipeline.stages.length);
      final pb.Pipeline_Stage stage = pipeline.stages[index];
      switch (below(7)) {
        case 0:
          if (stage.args.isNotEmpty) {
            stage.args[below(stage.args.length)] = wildExpression(
              3,
            ).toProto(encoder);
          }
          break;
        case 1:
          if (stage.args.isNotEmpty) {
            stage.args[below(stage.args.length)] = hostileValue(2);
          }
          break;
        case 2:
          if (stage.args.isNotEmpty) {
            stage.args.removeAt(below(stage.args.length));
          }
          break;
        case 3:
          stage.args.add(wildExpression(2).toProto(encoder));
          break;
        case 4:
          stage.options[pick(const <String>['limit', 'x', 'distance_field'])] =
              hostileValue(1);
          break;
        case 5:
          if (index > 0) {
            pipeline.stages.removeAt(index);
          }
          break;
        default:
          pipeline.stages.insert(index + 1, stage.deepCopy());
      }
    }
    return pipeline;
  }

  /// A Pipeline proto with stages of any name, and arguments and options of
  /// any shape.
  pb.Pipeline hostilePipeline() {
    pb.Value argument() {
      switch (below(5)) {
        case 0:
          return hostileValue(2);
        case 1:
          return wildExpression(2).toProto(encoder);
        case 2:
          return pb.Value()..fieldReferenceValue = pick(oddFieldPaths);
        case 3:
          return pb.Value()
            ..referenceValue = pick(<String>[
              '/c',
              '/c/d',
              '',
              'c',
              '/',
              '//',
              '/c/d/e',
              '/😀',
            ]);
        default:
          return pb.Value()
            ..stringValue = pick(const <String>['c', 'd', '', '/c', 'e']);
      }
    }

    final List<String> names = PipelineExecutor.supportedStages.toList()
      ..addAll(<String>['nope', '', 'raw', 'sample', 'search']);
    final pb.Pipeline pipeline = pb.Pipeline();
    for (int i = between(0, 5); i > 0; i--) {
      final pb.Pipeline_Stage stage = pb.Pipeline_Stage()
        ..name = i == 0 || chance(80) ? pick(names) : string();
      for (int j = below(4); j > 0; j--) {
        stage.args.add(argument());
      }
      for (int j = below(3); j > 0; j--) {
        stage.options[pick(const <String>['limit', 'distance_measure', 'x'])] =
            argument();
      }
      pipeline.stages.add(stage);
    }
    if (pipeline.stages.isNotEmpty && chance(70)) {
      pipeline.stages.first.name = pick(const <String>[
        'collection', 'collection_group', 'database', 'documents', //
      ]);
    }
    return pipeline;
  }

  List<EvaluationInput> documents() => <EvaluationInput>[
    for (int i = between(0, 4); i > 0; i--)
      EvaluationInput(
        local.toModel(pipelineDocument()) as model.ObjectValue,
        key: DocumentKey.fromPathString(
          pick(const <String>['c/a', 'c/b', 'c/d', 'd/a', 'c/a/c/b']),
        ),
      ),
  ];
}

/// How the cases ended, to show that they exercise the evaluator rather than
/// stop at the first check.
final Map<String, int> outcomes = <String, int>{};

void count(String outcome) => outcomes[outcome] = (outcomes[outcome] ?? 0) + 1;

/// Errors with which the local evaluation refuses an expression or pipeline.
bool isEvaluationRefusal(Object error) =>
    error is UnsupportedExpression || error is PipelineFailure;

String describeOutcome(EvaluateResult Function() evaluate) {
  try {
    return describeResult(evaluate());
  } on UnsupportedExpression catch (e) {
    return '$e';
  }
}

void main() {
  test('random expression trees encode, survive proto3 JSON and evaluate', () {
    forAll<Expression>(
      'random expression trees',
      count: cases(1500),
      generate: (Gen gen) => gen.wildExpression(4),
      show: (Expression expression) => '$expression',
      check: (Expression expression) {
        final pb.Value? encoded = acceptOrReject(
          () => expression.toProto(encoder),
          () => '$expression',
        );
        if (encoded == null) {
          return;
        }
        expect(
          expression.toProto(encoder).writeToBuffer(),
          encoded.writeToBuffer(),
          reason: 'the encoding is deterministic',
        );
        final pb.Value fromJson = pb.Value()
          ..mergeFromProto3Json(toFirestoreProto3Json(encoded));
        expect(
          fromJson.writeToBuffer(),
          encoded.writeToBuffer(),
          reason: 'proto3 JSON round trip of $encoded',
        );

        final Gen gen = Gen(encoded.hashCode);
        final List<EvaluationInput> inputs = gen.documents();
        for (final EvaluationInput input in inputs) {
          String evaluate() {
            final ExpressionEvaluator evaluator = ExpressionEvaluator(
              modelDatabaseId,
              now: () => const Timestamp(1700000000, 0),
              random: math.Random(7),
            );
            return describeOutcome(() => evaluator.evaluate(encoded, input));
          }

          final String first = acceptOrReject(evaluate, () => '$encoded')!;
          count(
            first.startsWith('UnsupportedExpression')
                ? 'expression unsupported'
                : first == 'error'
                ? 'expression error'
                : 'expression value',
          );
          expect(evaluate(), first, reason: 'evaluated twice: $encoded');
        }
      },
    );
  });

  test('hostile pipeline protos run locally or are refused', () {
    forAll<(pb.Pipeline, List<EvaluationInput>)>(
      'hostile pipelines',
      count: cases(1500),
      generate: (Gen gen) {
        if (gen.chance(25)) {
          return (gen.hostilePipeline(), gen.documents());
        }
        final PipelineData data = PipelineData('c', 'sub', 'run');
        for (int i = gen.between(1, 6); i > 0; i--) {
          final String path = gen.pick(const <String>[
            'c/a', 'c/b', 'c/d', 'c/e', 'c/a/sub/x', 'c/b/sub/y', 'd/a', //
          ]);
          data.documents[path] = gen.stageDocument(i, 'run');
        }
        return (
          gen.mutatedPipeline(data),
          <EvaluationInput>[
            for (final MapEntry<String, Map<String, Object?>> document
                in data.documents.entries)
              EvaluationInput(
                local.toModel(document.value) as model.ObjectValue,
                key: DocumentKey.fromPathString(document.key),
              ),
          ],
        );
      },
      show: ((pb.Pipeline, List<EvaluationInput>) c) => '${c.$1}',
      check: ((pb.Pipeline, List<EvaluationInput>) c) {
        final pb.Pipeline pipeline = c.$1;
        final PipelineExecutor executor = PipelineExecutor(
          modelDatabaseId,
          now: () => const Timestamp(1700000000, 0),
          random: math.Random(7),
        );
        final List<EvaluationInput> documents = c.$2;
        try {
          for (final EvaluationInput row in executor.execute(
            pipeline,
            documents,
          )) {
            row.fields.toString();
          }
          count('pipeline rows');
        } catch (error, stackTrace) {
          count('pipeline ${error.runtimeType}');
          if (!isEvaluationRefusal(error) &&
              !isCleanRejection(error, stackTrace)) {
            fail(
              'The executor failed with ${error.runtimeType}: $error\n'
              '${stackTrace.toString().split('\n').take(8).join('\n')}',
            );
          }
        }
      },
    );
  });

  test('hostile ExecutePipelineResponses decode or are rejected cleanly', () {
    final Pipeline pipeline = PipelineSource(modelFirestore).collection('c');
    forAll<List<proto.ExecutePipelineResponse>>(
      'hostile pipeline responses',
      count: cases(1500),
      generate: (Gen gen) => <proto.ExecutePipelineResponse>[
        for (int i = gen.between(1, 3); i > 0; i--)
          () {
            final proto.ExecutePipelineResponse response =
                proto.ExecutePipelineResponse();
            if (gen.chance(60)) {
              response.executionTime = gen.chance(10)
                  ? gen.hostileTimestamp()
                  : remote.encodeTimestamp(gen.timestamp());
            }
            for (int j = gen.below(4); j > 0; j--) {
              final pb.Document document = gen.chance(10)
                  ? gen.hostileDocument()
                  : (pb.Document()
                      ..name = gen.pick(const <String>[
                        'projects/project/databases/(default)/documents/c/a',
                        'projects/project/databases/(default)/documents/c/b/d/e',
                        '',
                      ])
                      ..fields.addAll(<String, pb.Value>{
                        for (int k = gen.below(4); k > 0; k--)
                          gen.pick(const <String>[
                            'a',
                            'b',
                            'c',
                            '__type__',
                          ]): gen.chance(90)
                              ? remote.encodeValue(gen.modelValue())
                              : gen.hostileValue(2),
                      }));
              if (gen.chance(20)) {
                document.name = '';
              }
              if (gen.chance(10)) {
                document.updateTime = gen.hostileTimestamp();
              }
              if (gen.chance(5)) {
                document.fields['f'] = pb.Value()
                  ..fieldReferenceValue = gen.pick(oddFieldPaths);
              }
              response.results.add(document);
            }
            if (gen.chance(30)) {
              response.explainStats = pb.ExplainStats()
                ..data = (proto.Any()
                  ..typeUrl = gen.pick(const <String>[
                    'type.googleapis.com/google.protobuf.StringValue',
                    'type.googleapis.com/google.protobuf.Struct',
                    '',
                  ])
                  ..value = gen.chance(50)
                      ? (proto.StringValue()..value = gen.string())
                            .writeToBuffer()
                      : gen.mutateBytes(
                          (proto.StringValue()..value = gen.string())
                              .writeToBuffer(),
                        ));
            }
            if (gen.chance(15)) {
              // Mutated on the wire.
              try {
                return proto.ExecutePipelineResponse.fromBuffer(
                  gen.mutateBytes(response.writeToBuffer()),
                );
                // ignore: avoid_catches_without_on_clauses
              } catch (_) {
                // The protobuf package rejects it before the SDK sees it.
              }
            }
            return response;
          }(),
      ],
      show: (List<proto.ExecutePipelineResponse> responses) =>
          responses.join('\n'),
      check: (List<proto.ExecutePipelineResponse> responses) {
        final PipelineSnapshot? snapshot = acceptOrReject(
          () => decodePipelineResponses(
            pipeline,
            modelFirestore,
            remote,
            responses,
          ),
          () => responses.join('\n'),
        );
        if (snapshot == null) {
          count('response rejected');
          return;
        }
        count('response decoded');
        snapshot.toString();
        snapshot.explainStats?.text;
        for (final PipelineResult result in snapshot.results) {
          result.ref;
          result.createTime;
          result.updateTime;
          final Map<String, Object?> data = result.data();
          for (final String key in data.keys) {
            acceptOrReject(() => result.get(key), () => key);
          }
          expect(pipelineResultEqual(result, result), isTrue);
        }
      },
    );
  });

  // The cases reach the evaluator, the executor and the snapshot: they are
  // not all refused at the first check.
  tearDownAll(() {
    int share(String outcome, String prefix) {
      final int total = outcomes.entries
          .where((MapEntry<String, int> e) => e.key.startsWith(prefix))
          .fold(0, (int sum, MapEntry<String, int> e) => sum + e.value);
      return total == 0 ? 0 : 100 * (outcomes[outcome] ?? 0) ~/ total;
    }

    expect(share('expression value', 'expression'), greaterThan(30));
    expect(share('pipeline rows', 'pipeline'), greaterThan(10));
    expect(share('response decoded', 'response'), greaterThan(20));
  });
}
