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

// Ported from the Android SDK:
// firebase-firestore/src/androidTest/java/com/google/firebase/firestore/RealtimePipelineTest.kt
//
// The cases listen to realtime pipelines (`RealtimePipelineSource`,
// `snapshots()`, `addSnapshotListener`). The Dart SDK has no realtime
// pipelines (design notes, phase 4; the API is internal upstream too), so the
// cases are kept by name and skipped. Their local evaluation (where, sort,
// limit over documents) is covered by the ports of Android's
// pipeline/*Tests.kt under test/unit/firebase/firestore/pipeline/realtime/.

// ignore_for_file: lines_longer_than_80_chars

import 'package:test/test.dart' show group, test;

const String noRealtimePipeline =
    'The Dart SDK has no realtime pipelines (no RealtimePipelineSource, '
    'snapshots() or addSnapshotListener on pipelines; phase 4 of the design).';

void main() {
  group('RealtimePipelineTest', () {
    test('testBasicAsyncStream', () {}, skip: noRealtimePipeline);
    test('testResultChanges', () {}, skip: noRealtimePipeline);
    test('testCanListenToCache', () {}, skip: noRealtimePipeline);
    test('testCanListenToMetadataOnlyChanges', () {}, skip: noRealtimePipeline);
    test(
      'testCanReadServerTimestampEstimateProperly',
      () {},
      skip: noRealtimePipeline,
    );
    test(
      'testCanEvaluateServerTimestampEstimateProperly',
      () {},
      skip: noRealtimePipeline,
    );
    test(
      'testCanReadServerTimestampPreviousProperly',
      () {},
      skip: noRealtimePipeline,
    );
    test(
      'testCanEvaluateServerTimestampPreviousProperly',
      () {},
      skip: noRealtimePipeline,
    );
    test(
      'testCanReadServerTimestampNoneProperly',
      () {},
      skip: noRealtimePipeline,
    );
    test(
      'testCanEvaluateServerTimestampNoneProperly',
      () {},
      skip: noRealtimePipeline,
    );
    test(
      'testSamePipelineWithDifferentOptions',
      () {},
      skip: noRealtimePipeline,
    );
    test('testLogicalAnd', () {}, skip: noRealtimePipeline);
    test('testLogicalOr', () {}, skip: noRealtimePipeline);
    test('testLogicalXor', () {}, skip: noRealtimePipeline);
    test('testNotFunction', () {}, skip: noRealtimePipeline);
    test('testEqAny', () {}, skip: noRealtimePipeline);
    test('testNotEqAny', () {}, skip: noRealtimePipeline);
    test('testIsAbsent', () {}, skip: noRealtimePipeline);
    test('testExists', () {}, skip: noRealtimePipeline);
    test('testIsNanAndIsNotNan', () {}, skip: noRealtimePipeline);
    test('testIsNullAndIsNotNull', () {}, skip: noRealtimePipeline);
    test('testStrConcat', () {}, skip: noRealtimePipeline);
    test('testToLower', () {}, skip: noRealtimePipeline);
    test('testToUpper', () {}, skip: noRealtimePipeline);
    test('testTrim', () {}, skip: noRealtimePipeline);
    test('testCharLength', () {}, skip: noRealtimePipeline);
    test('testByteLength', () {}, skip: noRealtimePipeline);
    test('testReverse', () {}, skip: noRealtimePipeline);
    test('testStrContains', () {}, skip: noRealtimePipeline);
    test('testStartsWith', () {}, skip: noRealtimePipeline);
    test('testEndsWith', () {}, skip: noRealtimePipeline);
    test('testLike', () {}, skip: noRealtimePipeline);
    test('testRegexContains', () {}, skip: noRealtimePipeline);
    test('testRegexFind', () {}, skip: noRealtimePipeline);
    test('testRegexFindAll', () {}, skip: noRealtimePipeline);
    test('testRegexMatch', () {}, skip: noRealtimePipeline);
    test('testAdd', () {}, skip: noRealtimePipeline);
    test('testSubtract', () {}, skip: noRealtimePipeline);
    test('testMultiply', () {}, skip: noRealtimePipeline);
    test('testDivide', () {}, skip: noRealtimePipeline);
    test('testMod', () {}, skip: noRealtimePipeline);
    test('testPow', () {}, skip: noRealtimePipeline);
    test('testAbs', () {}, skip: noRealtimePipeline);
    test('testExp', () {}, skip: noRealtimePipeline);
    test('testLn', () {}, skip: noRealtimePipeline);
    test('testLog10', () {}, skip: noRealtimePipeline);
    test('testLog', () {}, skip: noRealtimePipeline);
    test('testSqrt', () {}, skip: noRealtimePipeline);
    test('testRound', () {}, skip: noRealtimePipeline);
    test('testCeil', () {}, skip: noRealtimePipeline);
    test('testFloor', () {}, skip: noRealtimePipeline);
    test('testTimestampAdd', () {}, skip: noRealtimePipeline);
    test('testTimestampSub', () {}, skip: noRealtimePipeline);
    test('testUnixSecondsToTimestamp', () {}, skip: noRealtimePipeline);
    test('testUnixMillisToTimestamp', () {}, skip: noRealtimePipeline);
    test('testTimestampToUnixSeconds', () {}, skip: noRealtimePipeline);
    test('testTimestampToUnixMillis', () {}, skip: noRealtimePipeline);
    test('testTimestampToUnixMicros', () {}, skip: noRealtimePipeline);
    test('testUnixMicrosToTimestamp', () {}, skip: noRealtimePipeline);
    test('testArrayContains', () {}, skip: noRealtimePipeline);
    test('testArrayContainsAny', () {}, skip: noRealtimePipeline);
    test('testArrayLength', () {}, skip: noRealtimePipeline);
    test('testArrayFirst', () {}, skip: noRealtimePipeline);
    test('testArrayFirstN', () {}, skip: noRealtimePipeline);
    test('testArrayLast', () {}, skip: noRealtimePipeline);
    test('testArrayLastN', () {}, skip: noRealtimePipeline);
    test('testArrayMinimum', () {}, skip: noRealtimePipeline);
    test('testArrayMinimumN', () {}, skip: noRealtimePipeline);
    test('testArrayMaximum', () {}, skip: noRealtimePipeline);
    test('testArrayMaximumN', () {}, skip: noRealtimePipeline);
    test('testArrayIndexOf', () {}, skip: noRealtimePipeline);
    test('testArrayIndexOfEdgeCases', () {}, skip: noRealtimePipeline);
    test('testArrayLastIndexOf', () {}, skip: noRealtimePipeline);
    test('testArrayIndexOfAll', () {}, skip: noRealtimePipeline);
    test('testSubstring', () {}, skip: noRealtimePipeline);
  });
}
