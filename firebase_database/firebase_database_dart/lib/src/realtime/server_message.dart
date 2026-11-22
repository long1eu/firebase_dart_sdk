/// Decoding the data messages of the server into typed records (owner K): `rtdb_protocol.md` 4
/// (responses) and 5 (pushes), with the hardening of iOS U-I01, U-I05 to U-I11 and threat model
/// T11.
///
/// Paths in pushes arrive without the leading slash; every decoded path goes through
/// [wirePathFromServer]. Merge maps keep their keys as the server sent them
/// (`rtdb_seam_changes.md` A.3).
library;

import 'package:firebase_database_dart/src/core/connection/wire_range_merge.dart';

/// One data message of the server (the `d` of `{"t":"d","d":...}`), decoded.
sealed class ServerMessage {
  /// Constructor for the subclasses.
  const ServerMessage();
}

/// The response to request [r] (4): `{"r":n,"b":{"s":status,"d":data}}`.
///
/// A body that is not an object or a status that is not a string decodes to a response with status
/// `failed` (iOS U-I06, U-I07); a non-integer `r` decodes to [Ignored] (U-I09).
final class Response extends ServerMessage {
  /// Creates the response to [r] with [status] and [data].
  const Response(this.r, this.status, this.data);

  /// The request number.
  final int r;

  /// The status string: `ok` or an error code (9).
  final String status;

  /// The result on `ok`, a human-readable reason otherwise.
  final Object? data;

  @override
  String toString() => 'Response($r, $status)';
}

/// A message the server pushed without a request (5). Every field is validated: malformed pushes
/// decode to [Ignored] and never reach the delegate (iOS U-I08, U-I10, U-I11; threat model T11).
sealed class Push extends ServerMessage {
  /// Constructor for the subclasses.
  const Push();

  /// The wire action (`d`, `m`, `c`, `ac`, `apc`, `sd`).
  String get action;
}

/// A data push: `d` (overwrite) or `m` (merge) at [path] (5).
final class DataPush extends Push {
  /// Creates the push of [data] at [path]; [isMerge] for `m`.
  const DataPush({
    required this.path,
    required this.data,
    required this.isMerge,
    this.tag,
  });

  /// The location as `/a/b` (the server's `a/b` with the slash added), validated as a server
  /// path (T11: no `.#$[]`, no control characters, at most 768 UTF-8 bytes and 32 segments, first
  /// segment not starting with `.`).
  final String path;

  /// The JSON value; for a merge an object of child keys or relative paths to values (null
  /// deletes).
  final Object? data;

  /// Whether this is a merge (`m`).
  final bool isMerge;

  /// The query tag, or null when untagged (a tag of 0 is untagged, 5 Repo.ts:354-410).
  final int? tag;

  @override
  String get action => isMerge ? 'm' : 'd';

  /// Shows the path, not the data (threat model T7).
  @override
  String toString() => 'DataPush($action $path, tag: $tag)';
}

/// A listen revoked by the rules (`c`, 5). Every listen at [path] is cancelled (lead's decision,
/// Android behaviour).
final class ListenRevokedPush extends Push {
  /// Creates the push for [path] with the [queries] the server named.
  const ListenRevokedPush({required this.path, this.queries});

  /// The location as `/a/b` ([wirePathFromServer]).
  final String path;

  /// The query objects of `q`, or null when absent.
  final List<Map<String, Object?>>? queries;

  @override
  String get action => 'c';

  @override
  String toString() => 'ListenRevokedPush($path)';
}

/// Auth revoked (`ac`, 5 and 8.3).
final class AuthRevokedPush extends Push {
  /// Creates the push with [status] and [explanation].
  const AuthRevokedPush({required this.status, required this.explanation});

  /// The status, for example `invalid_token`.
  final String status;

  /// The server's explanation; cut and escaped before it is logged (T7).
  final String explanation;

  @override
  String get action => 'ac';

  @override
  String toString() => 'AuthRevokedPush($status)';
}

/// App Check revoked (`apc`, 5 and 8.3).
final class AppCheckRevokedPush extends Push {
  /// Creates the push with [status] and [explanation].
  const AppCheckRevokedPush({required this.status, required this.explanation});

  /// The status.
  final String status;

  /// The server's explanation; cut and escaped before it is logged (T7).
  final String explanation;

  @override
  String get action => 'apc';

  @override
  String toString() => 'AppCheckRevokedPush($status)';
}

/// Security debug text (`sd`, 5), for the log only.
final class SecurityDebugPush extends Push {
  /// Creates the push with [message].
  const SecurityDebugPush(this.message);

  /// The text; cut and escaped before it is logged (T7).
  final String message;

  @override
  String get action => 'sd';

  @override
  String toString() => 'SecurityDebugPush';
}

/// A data message with an `error` key (5): JS throws, Android ignores; we log it (lead's decision,
/// iOS U-I01).
final class ServerError extends ServerMessage {
  /// Creates the message with the server's [message].
  const ServerError(this.message);

  /// The server's text; cut and escaped before it is logged (T7).
  final String message;

  @override
  String toString() => 'ServerError';
}

/// A range merge (`rm`, 7.4): only after a listen sent a compound hash `ch`.
///
/// The entry shapes are those measured on the emulator (probe, addendum B): `{"e":..}` first,
/// `{"s":..,"e":..}` in the middle, `{"s":..}` last, neither for a single entry, each with `m`. An
/// empty list (a hash match) decodes to [Ignored]: the seam promises a non-empty list.
final class RangeMergePush extends Push {
  /// Creates the push of [merges] at [path].
  const RangeMergePush({required this.path, required this.merges, this.tag});

  /// The location as `/a/b`, validated as [DataPush.path].
  final String path;

  /// The ranges, never empty; their `s`/`e` paths also as `/a/b`.
  final List<WireRangeMerge> merges;

  /// The query tag, or null when untagged.
  final int? tag;

  @override
  String get action => 'rm';

  @override
  String toString() =>
      'RangeMergePush($path, ${merges.length} ranges, tag: $tag)';
}

/// A message that is malformed or of an unknown kind (unknown actions, non-object messages):
/// logged and dropped (iOS U-I05, U-I08, U-I09; test plan B-5.4).
final class Ignored extends ServerMessage {
  /// Creates the record with [why] it was ignored (no server data in it).
  const Ignored(this.why);

  /// Why the message was dropped, for the log.
  final String why;

  @override
  String toString() => 'Ignored($why)';
}

/// Decodes [json], the `d` of a data message. Never throws (test plan idea 3: fuzzed).
ServerMessage decodeServerMessage(Object? json) {
  throw UnimplementedError();
}

/// The seam form of a path the server sent (`rtdb_seam_changes.md` A.3): `a/b` becomes `/a/b`,
/// `""` (the root) becomes `/`; a path that already starts with `/` is kept.
///
/// The server pushes paths without the leading slash (`"p":"ws/a"`, root `""`), while requests may
/// carry one (`rtdb_emulator_probe.md`, "Paths in pushes have no leading slash", measured). The
/// one place where the connection half converts; used for `d`, `m`, `c`, `rm` and the `s`/`e` of
/// range merges. Validation (threat model T11) is separate.
String wirePathFromServer(String serverPath) {
  throw UnimplementedError();
}
