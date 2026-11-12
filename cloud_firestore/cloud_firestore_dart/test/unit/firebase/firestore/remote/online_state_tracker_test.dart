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

import 'dart:async';

import 'package:cloud_firestore_dart/src/firebase/firestore/core/online_state.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/online_state_tracker.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/timer_task.dart';
import 'package:grpc/grpc.dart';
import 'package:test/test.dart';

/// Unit tests for [OnlineStateTracker]. Upstream covers this class through the
/// spec tests and the RemoteStore tests; these exercise the heuristics (one
/// failure or a 10 second timeout moves the client offline) in isolation.
void main() {
  late TaskScheduler scheduler;
  late List<OnlineState> states;
  late OnlineStateTracker tracker;

  setUp(() {
    scheduler = TaskScheduler('online-state-test');
    states = <OnlineState>[];
    tracker = OnlineStateTracker(scheduler, (OnlineState state) async {
      states.add(state);
    });
  });

  tearDown(() {
    scheduler.getTask(TaskId.onlineStateTimeout)?.cancel();
  });

  test('starts unknown and does not broadcast the unchanged state', () async {
    await tracker.handleWatchStreamStart();
    expect(states, isEmpty);
    expect(scheduler.getTask(TaskId.onlineStateTimeout), isNotNull);
  });

  test('moves offline when the timeout elapses', () async {
    await tracker.handleWatchStreamStart();
    scheduler.runUntil(TaskId.onlineStateTimeout);
    await Future<void>.delayed(Duration.zero);

    expect(states, <OnlineState>[OnlineState.offline]);
    expect(scheduler.getTask(TaskId.onlineStateTimeout), isNull);
  });

  test('moves offline after the first stream failure', () async {
    await tracker.handleWatchStreamStart();
    await tracker.handleWatchStreamFailure(const GrpcError.unavailable());

    expect(states, <OnlineState>[OnlineState.offline]);
    // The timer is cleared when going offline because of failures.
    expect(scheduler.getTask(TaskId.onlineStateTimeout), isNull);
  });

  test('updateState(online) cancels the timeout', () async {
    await tracker.handleWatchStreamStart();
    await tracker.updateState(OnlineState.online);

    expect(states, <OnlineState>[OnlineState.online]);
    expect(scheduler.getTask(TaskId.onlineStateTimeout), isNull);
  });

  test('a failure while online moves to unknown, not offline', () async {
    await tracker.handleWatchStreamStart();
    await tracker.updateState(OnlineState.online);
    await tracker.handleWatchStreamFailure(const GrpcError.unavailable());

    expect(states, <OnlineState>[OnlineState.online, OnlineState.unknown]);
    expect(scheduler.getTask(TaskId.onlineStateTimeout), isNull);
  });

  test('a restarted stream after a failure while online arms the timeout',
      () async {
    await tracker.handleWatchStreamStart();
    await tracker.updateState(OnlineState.online);
    await tracker.handleWatchStreamFailure(const GrpcError.unavailable());
    await tracker.handleWatchStreamStart();

    expect(scheduler.getTask(TaskId.onlineStateTimeout), isNotNull);
    scheduler.runUntil(TaskId.onlineStateTimeout);
    await Future<void>.delayed(Duration.zero);
    expect(states.last, OnlineState.offline);
  });

  test('further starts after a failure do not re-arm the timeout', () async {
    await tracker.handleWatchStreamStart();
    await tracker.handleWatchStreamFailure(const GrpcError.unavailable());
    await tracker.handleWatchStreamStart();

    expect(scheduler.getTask(TaskId.onlineStateTimeout), isNull);
    expect(states, <OnlineState>[OnlineState.offline]);
  });

  test('updateState resets the failure counter and the timer', () async {
    await tracker.handleWatchStreamStart();
    await tracker.handleWatchStreamFailure(const GrpcError.unavailable());
    await tracker.updateState(OnlineState.unknown);
    expect(states, <OnlineState>[OnlineState.offline, OnlineState.unknown]);

    await tracker.handleWatchStreamStart();
    expect(scheduler.getTask(TaskId.onlineStateTimeout), isNotNull);
  });

  test('repeated identical states are broadcast once', () async {
    await tracker.updateState(OnlineState.online);
    await tracker.updateState(OnlineState.online);
    await tracker.updateState(OnlineState.offline);
    await tracker.updateState(OnlineState.offline);

    expect(states, <OnlineState>[OnlineState.online, OnlineState.offline]);
  });
}
