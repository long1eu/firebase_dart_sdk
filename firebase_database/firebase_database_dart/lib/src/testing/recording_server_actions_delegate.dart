/// A delegate that records what the connection tells Repo, for tests of a connection (the
/// realtime half's tests and the ServerActions contract). No upstream file.
///
/// Real code, not a stub: it is part of the frozen test support.
library;

import 'package:firebase_database_dart/src/core/connection/server_actions.dart';
import 'package:firebase_database_dart/src/core/connection/wire_range_merge.dart';

/// One call made on a [RecordingServerActionsDelegate], in the order made.
final class DelegateCall {
  /// Records a call.
  const DelegateCall(
    this.method, {
    this.path,
    this.data,
    this.isMerge,
    this.tag,
    this.merges,
    this.status,
    this.explanation,
  });

  /// The method name without the `on` prefix: `dataUpdate`, `rangeMergeUpdate`, `connect`,
  /// `disconnect`, `authStatus`, `appCheckStatus`, `serverShutdown`, `serverInfoUpdate`.
  final String method;

  /// The path of a data or range merge update.
  final String? path;

  /// The data of a data update, or the updates of a server info update.
  final Object? data;

  /// Whether a data update is a merge.
  final bool? isMerge;

  /// The tag of a data or range merge update.
  final int? tag;

  /// The merges of a range merge update.
  final List<WireRangeMerge>? merges;

  /// The status of an auth or App Check status, or the reason of a server shutdown.
  final String? status;

  /// The explanation of an auth or App Check status.
  final String? explanation;

  @override
  String toString() =>
      'DelegateCall($method'
      '${path == null ? '' : ' $path'}'
      '${data == null ? '' : ' $data'}'
      '${isMerge == true ? ' merge' : ''}'
      '${tag == null ? '' : ' t=$tag'}'
      '${status == null ? '' : ' $status'}'
      '${explanation == null ? '' : ' ($explanation)'})';
}

/// A [ServerActionsDelegate] that records every call in [calls].
final class RecordingServerActionsDelegate implements ServerActionsDelegate {
  /// Creates an empty recorder.
  RecordingServerActionsDelegate();

  /// Every call, in order.
  final List<DelegateCall> calls = <DelegateCall>[];

  /// The calls of [method] (see [DelegateCall.method]).
  List<DelegateCall> callsOf(String method) =>
      calls.where((DelegateCall call) => call.method == method).toList();

  /// The method names in order, for checking the order of lifecycle calls.
  List<String> get methods =>
      calls.map((DelegateCall call) => call.method).toList();

  @override
  void onDataUpdate(
    String path,
    Object? data, {
    required bool isMerge,
    int? tag,
  }) => calls.add(
    DelegateCall(
      'dataUpdate',
      path: path,
      data: data,
      isMerge: isMerge,
      tag: tag,
    ),
  );

  @override
  void onRangeMergeUpdate(
    String path,
    List<WireRangeMerge> merges, {
    int? tag,
  }) => calls.add(
    DelegateCall('rangeMergeUpdate', path: path, merges: merges, tag: tag),
  );

  @override
  void onConnect() => calls.add(const DelegateCall('connect'));

  @override
  void onDisconnect() => calls.add(const DelegateCall('disconnect'));

  @override
  void onAuthStatus(String status, {String? explanation}) => calls.add(
    DelegateCall('authStatus', status: status, explanation: explanation),
  );

  @override
  void onAppCheckStatus(String status, {String? explanation}) => calls.add(
    DelegateCall('appCheckStatus', status: status, explanation: explanation),
  );

  @override
  void onServerShutdown(String reason) =>
      calls.add(DelegateCall('serverShutdown', status: reason));

  @override
  void onServerInfoUpdate(Map<String, Object?> updates) =>
      calls.add(DelegateCall('serverInfoUpdate', data: updates));
}
