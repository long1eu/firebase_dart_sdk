//
//  Generated code. Do not modify.
//  source: google/firestore/v1/explain_stats.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

import '../../protobuf/any.pb.dart' as $12;

///  Pipeline explain stats.
///
///  Depending on the explain options in the original request, this can contain
///  the optimized plan and / or execution stats.
class ExplainStats extends $pb.GeneratedMessage {
  factory ExplainStats({
    $12.Any? data,
  }) {
    final $result = create();
    if (data != null) {
      $result.data = data;
    }
    return $result;
  }
  ExplainStats._() : super();
  factory ExplainStats.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ExplainStats.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ExplainStats', package: const $pb.PackageName(_omitMessageNames ? '' : 'google.firestore.v1'), createEmptyInstance: create)
    ..aOM<$12.Any>(1, _omitFieldNames ? '' : 'data', subBuilder: $12.Any.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ExplainStats clone() => ExplainStats()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ExplainStats copyWith(void Function(ExplainStats) updates) => super.copyWith((message) => updates(message as ExplainStats)) as ExplainStats;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ExplainStats create() => ExplainStats._();
  ExplainStats createEmptyInstance() => create();
  static $pb.PbList<ExplainStats> createRepeated() => $pb.PbList<ExplainStats>();
  @$core.pragma('dart2js:noInline')
  static ExplainStats getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ExplainStats>(create);
  static ExplainStats? _defaultInstance;

  ///  The format depends on the `output_format` options in the request.
  ///
  ///  Currently there are two supported options: `TEXT` and `JSON`.
  ///  Both supply a `google.protobuf.StringValue`.
  @$pb.TagNumber(1)
  $12.Any get data => $_getN(0);
  @$pb.TagNumber(1)
  set data($12.Any v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasData() => $_has(0);
  @$pb.TagNumber(1)
  void clearData() => clearField(1);
  @$pb.TagNumber(1)
  $12.Any ensureData() => $_ensure(0);
}


const _omitFieldNames = $core.bool.fromEnvironment('protobuf.omit_field_names');
const _omitMessageNames = $core.bool.fromEnvironment('protobuf.omit_message_names');
