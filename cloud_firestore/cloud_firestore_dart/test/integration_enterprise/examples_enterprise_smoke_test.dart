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
// Runs example/pipelines.dart as its own process against the Enterprise
// edition emulator (tool/start_enterprise_emulator.sh) and checks that it
// finishes with exit code 0, without an uncaught error and without hanging.
// The other examples run in test/integration/.../examples_smoke_test.dart,
// where this one only prints that it was skipped.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../util/integration_test_util.dart';

void main() {
  test('example/pipelines.dart runs against the enterprise emulator', () async {
    final Process process = await Process.start(
      Platform.resolvedExecutable,
      <String>['run', 'example/pipelines.dart'],
      environment: <String, String>{
        'FIRESTORE_ENTERPRISE_EMULATOR_HOST':
            IntegrationTestUtil.enterpriseEmulatorHost!,
      },
    );
    final Future<String> stdoutText =
        process.stdout.transform(utf8.decoder).join();
    final Future<String> stderrText =
        process.stderr.transform(utf8.decoder).join();

    final int exitCode = await process.exitCode
        .timeout(const Duration(minutes: 2), onTimeout: () {
      process.kill(ProcessSignal.sigkill);
      return -1;
    });
    final String output = await stdoutText;
    final String errors = await stderrText;

    expect(exitCode, 0,
        reason: exitCode == -1
            ? 'The example did not exit within 2 minutes.\n$output\n$errors'
            : 'The example failed.\n$output\n$errors');
    expect(errors, isEmpty, reason: 'The example wrote to stderr.');
    expect(output, isNot(contains('Skipped')));
    // A line of every part of the example.
    expect(output, contains('well rated: '));
    expect(output, contains('Science Fiction: 2 book(s), average 4.40'));
    expect(output,
        contains('query: [hitchhiker, dune], pipeline: [hitchhiker, dune]'));
    expect(output, contains('marked as classic: 1'));
  },
      skip: IntegrationTestUtil.enterpriseEmulatorSkipReason,
      timeout: const Timeout(Duration(minutes: 3)));

  test('example/pipelines.dart only prints a note without the emulator',
      () async {
    final Map<String, String> environment =
        Map<String, String>.of(Platform.environment)
          ..remove('FIRESTORE_ENTERPRISE_EMULATOR_HOST');
    final ProcessResult result = await Process.run(
      Platform.resolvedExecutable,
      <String>['run', 'example/pipelines.dart'],
      environment: environment,
      includeParentEnvironment: false,
    );
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stdout, startsWith('Skipped: '));
  }, timeout: const Timeout(Duration(minutes: 3)));
}
