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

import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/stage.dart';
import 'package:cloud_firestore_dart/src/proto/google/firestore/v1/index.dart'
    as pb;
import 'package:meta/meta.dart';

/// What the server does when it is asked to explain a pipeline.
///
/// **Preview, Enterprise only**: the Pipelines API is experimental, may change
/// in any release and needs a Firestore Enterprise edition database.
enum PipelineExplainMode {
  /// Run the pipeline and return its results, without an explanation.
  execute('execute'),

  /// Only plan the pipeline: report the plan and return no results.
  explain('explain'),

  /// Run the pipeline, return its results and report the plan with the
  /// statistics of the run.
  analyze('analyze');

  const PipelineExplainMode(this.serverName);

  /// The name the server knows this mode by.
  @internal
  final String serverName;
}

/// The format of `PipelineSnapshot.explainStats`.
///
/// **Preview, Enterprise only**: the Pipelines API is experimental, may change
/// in any release and needs a Firestore Enterprise edition database.
enum PipelineExplainOutputFormat {
  /// Human readable text, read with `PipelineExplainStats.text`.
  text('text');

  const PipelineExplainOutputFormat(this.serverName);

  /// The name the server knows this format by.
  @internal
  final String serverName;
}

/// Asks the server to explain how it runs a pipeline; pass it to
/// `Pipeline.execute`. The explanation is in
/// `PipelineSnapshot.explainStats`.
///
/// The option names (`explain_options` with `mode` and `output_format`) are
/// those of the Node.js server SDK (`@google-cloud/firestore`), which has the
/// same typed option. The Enterprise emulator ignores the option, so the
/// explanation itself was not seen in a test.
///
/// **Preview, Enterprise only**: the Pipelines API is experimental, may change
/// in any release and needs a Firestore Enterprise edition database.
class PipelineExplainOptions {
  /// Explain in [mode] (the server default, `execute`, when null), with the
  /// explanation in [outputFormat] (the server default when null).
  const PipelineExplainOptions({this.mode, this.outputFormat});

  /// What the server does, or null for its default.
  final PipelineExplainMode? mode;

  /// The format of the explanation, or null for the server default.
  final PipelineExplainOutputFormat? outputFormat;

  /// The wire form: a map with `mode` and `output_format`, each only when
  /// set.
  @internal
  pb.Value toProto() {
    final pb.MapValue map = pb.MapValue();
    final PipelineExplainMode? mode = this.mode;
    final PipelineExplainOutputFormat? outputFormat = this.outputFormat;
    if (mode != null) {
      map.fields['mode'] = stringValue(mode.serverName);
    }
    if (outputFormat != null) {
      map.fields['output_format'] = stringValue(outputFormat.serverName);
    }
    return pb.Value()..mapValue = map;
  }

  @override
  String toString() =>
      'PipelineExplainOptions(mode: ${mode?.name}, '
      'outputFormat: ${outputFormat?.name})';
}
