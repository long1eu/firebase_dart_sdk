/// Decoding the data messages of the server into typed records (owner K): `rtdb_protocol.md` 4
/// (responses) and 5 (pushes), with the hardening of iOS U-I01, U-I05 to U-I11 and threat model
/// T11.
library;

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

  /// The location, validated as a server path (T11: no `.#$[]`, no control characters, at most 768
  /// UTF-8 bytes and 32 segments, first segment not starting with `.`).
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

  /// The location.
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

/// A message that is malformed or of an unknown kind (`rm`, unknown actions, non-object messages):
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
