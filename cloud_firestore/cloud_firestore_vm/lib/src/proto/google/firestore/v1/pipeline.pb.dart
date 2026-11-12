//
//  Generated code. Do not modify.
//  source: google/firestore/v1/pipeline.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

import 'document.pb.dart' as $1;

///  A Firestore query represented as an ordered list of operations / stages.
///
///  This is considered the top-level function which plans and executes a query.
///  It is logically equivalent to `query(stages, options)`, but prevents the
///  client from having to build a function wrapper.
class StructuredPipeline extends $pb.GeneratedMessage {
  factory StructuredPipeline({
    $1.Pipeline? pipeline,
    $core.Map<$core.String, $1.Value>? options,
  }) {
    final $result = create();
    if (pipeline != null) {
      $result.pipeline = pipeline;
    }
    if (options != null) {
      $result.options.addAll(options);
    }
    return $result;
  }
  StructuredPipeline._() : super();
  factory StructuredPipeline.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory StructuredPipeline.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'StructuredPipeline', package: const $pb.PackageName(_omitMessageNames ? '' : 'google.firestore.v1'), createEmptyInstance: create)
    ..aOM<$1.Pipeline>(1, _omitFieldNames ? '' : 'pipeline', subBuilder: $1.Pipeline.create)
    ..m<$core.String, $1.Value>(2, _omitFieldNames ? '' : 'options', entryClassName: 'StructuredPipeline.OptionsEntry', keyFieldType: $pb.PbFieldType.OS, valueFieldType: $pb.PbFieldType.OM, valueCreator: $1.Value.create, valueDefaultOrMaker: $1.Value.getDefault, packageName: const $pb.PackageName('google.firestore.v1'))
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  StructuredPipeline clone() => StructuredPipeline()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  StructuredPipeline copyWith(void Function(StructuredPipeline) updates) => super.copyWith((message) => updates(message as StructuredPipeline)) as StructuredPipeline;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static StructuredPipeline create() => StructuredPipeline._();
  StructuredPipeline createEmptyInstance() => create();
  static $pb.PbList<StructuredPipeline> createRepeated() => $pb.PbList<StructuredPipeline>();
  @$core.pragma('dart2js:noInline')
  static StructuredPipeline getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<StructuredPipeline>(create);
  static StructuredPipeline? _defaultInstance;

  /// Required. The pipeline query to execute.
  @$pb.TagNumber(1)
  $1.Pipeline get pipeline => $_getN(0);
  @$pb.TagNumber(1)
  set pipeline($1.Pipeline v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasPipeline() => $_has(0);
  @$pb.TagNumber(1)
  void clearPipeline() => clearField(1);
  @$pb.TagNumber(1)
  $1.Pipeline ensurePipeline() => $_ensure(0);

  ///  Optional. Optional query-level arguments.
  @$pb.TagNumber(2)
  $core.Map<$core.String, $1.Value> get options => $_getMap(1);
}


const _omitFieldNames = $core.bool.fromEnvironment('protobuf.omit_field_names');
const _omitMessageNames = $core.bool.fromEnvironment('protobuf.omit_message_names');
