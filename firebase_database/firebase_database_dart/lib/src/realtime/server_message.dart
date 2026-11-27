/// Decoding the data messages of the server into typed records (owner K): `rtdb_protocol.md` 4
/// (responses) and 5 (pushes), with the hardening of iOS U-I01, U-I05 to U-I11 and threat model
/// T11.
///
/// Paths in pushes arrive without the leading slash; every decoded path goes through
/// [wirePathFromServer]. Merge maps keep their keys as the server sent them
/// (`rtdb_seam_changes.md` A.3).
library;

import 'package:firebase_database_dart/src/core/connection/wire_range_merge.dart';
import 'package:firebase_database_dart/src/core/database_error.dart';
import 'package:firebase_database_dart/src/core/util/numbers.dart';
import 'package:firebase_database_dart/src/realtime/connection_timings.dart';
import 'package:firebase_database_dart/src/realtime/realtime_error.dart';

/// One data message of the server (the `d` of `{"t":"d","d":...}`), decoded.
sealed class ServerMessage {
  /// Constructor for the subclasses.
  const ServerMessage();
}

/// The response to request [r] (4): `{"r":n,"b":{"s":status,"d":data}}`.
///
/// A body that is not an object or a status that is not a string decodes to a response with status
/// `failure`, the wire status of `DatabaseErrorCode.operationFailed` (iOS U-I06, U-I07 use
/// `failed`, which the core's vocabulary does not have); an `r` that is not a non-negative whole
/// number ([wholeJsonNumber]) decodes to [Ignored] (U-I09). An `ok` answer whose data holds a
/// non-finite number or an oversized string, or (when the caller flagged the answer) an invalid
/// key, also decodes to `failure` with [dataRefused] (threat model T11). A non-`ok` status and a
/// string [data] are cleaned by [safeServerText]; other data of a non-`ok` answer is dropped. The
/// keys of `ok` data are checked only for flagged answers (`checkAnswerKeys` of
/// [decodeServerMessage]): an `auth` answer echoes token claims such as `https://x/roles`.
final class Response extends ServerMessage {
  /// Creates the response to [r] with [status] and [data]; [dataRefused] when the server answered
  /// `ok` with data that was refused.
  const Response(this.r, this.status, this.data, {this.dataRefused = false});

  /// The request number.
  final int r;

  /// The status string: `ok` or an error code (9).
  final String status;

  /// The result on `ok`, a human-readable reason otherwise.
  final Object? data;

  /// Whether the server answered `ok` with data that is not acceptable (a non-finite number, an
  /// oversized string, or, for an answer the caller flagged, an invalid key): [status] is then
  /// `failure` and [data] null. Set so that the connection can close as for a protocol error.
  final bool dataRefused;

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
///
/// With [isProtocolError] the message broke a rule of threat model T11 (a known message of the
/// wrong shape, a bad path or key, an `r` or `t` that is not a whole number, a non-finite
/// number): the owner closes the connection as a protocol error with backoff (brief, security
/// rule 4). Without it the message is only logged: an unknown action, or an `rm` with an empty
/// list (a compound hash match).
final class Ignored extends ServerMessage {
  /// Creates the record with [why] it was ignored (no server data in it).
  const Ignored(this.why, {this.isProtocolError = false});

  /// Why the message was dropped, for the log.
  final String why;

  /// Whether the message broke a protocol rule and the connection must close.
  final bool isProtocolError;

  @override
  String toString() =>
      'Ignored($why${isProtocolError ? ', protocol error' : ''})';
}

/// Decodes [json], the `d` of a data message. Never throws (test plan idea 3: fuzzed).
///
/// The order of the checks is JS's (PersistentConnection.ts:642-656): a message with `r` is a
/// response, one with `error` a [ServerError], one with `a` a [Push]. Every path, key, tag and
/// number of a push is validated (threat model T11) and every path is converted with
/// [wirePathFromServer]. An unknown action is [Ignored] without a protocol error, so a newer server
/// does not break the connection.
///
/// [checkAnswerKeys] is called once for every [Response] with a valid request number, `ok` or
/// not; when it returns true, the data of an `ok` answer must also pass the key rules of
/// [isValidServerData], in the same walk that checks its values. The connection flags its `g`
/// answers this way; other answers are not key-checked (an `auth` answer echoes token claims such
/// as `https://x/roles`). Nesting depth is not checked here: every message reaching this function
/// went through the frame assembler's text scan (`checkJsonDepth`, threat model T10), and the walk
/// itself does not recurse.
ServerMessage decodeServerMessage(
  Object? json, {
  bool Function(int r)? checkAnswerKeys,
}) {
  if (json is! Map<String, Object?>) {
    return const Ignored(
      'data message is not an object',
      isProtocolError: true,
    );
  }
  if (json.containsKey(RealtimeProtocol.requestNumberKey)) {
    return _decodeResponse(json, checkAnswerKeys);
  }
  if (json.containsKey(_errorKey)) {
    final Object? error = json[_errorKey];
    if (error is! String) {
      return const Ignored('error is not a string', isProtocolError: true);
    }
    return ServerError(safeServerText(error));
  }
  final Object? action = json[RealtimeProtocol.actionKey];
  if (action is! String) {
    return const Ignored('action is not a string', isProtocolError: true);
  }
  final Object? body = json[RealtimeProtocol.bodyKey];
  if (body is! Map<String, Object?>) {
    return const Ignored('push body is not an object', isProtocolError: true);
  }
  return switch (action) {
    RealtimeProtocol.pushData => _decodeDataPush(body, isMerge: false),
    RealtimeProtocol.pushMerge => _decodeDataPush(body, isMerge: true),
    RealtimeProtocol.pushListenCancelled => _decodeListenRevoked(body),
    RealtimeProtocol.pushAuthRevoked => _decodeRevoke(body, appCheck: false),
    RealtimeProtocol.pushAppCheckRevoked => _decodeRevoke(body, appCheck: true),
    RealtimeProtocol.pushSecurityDebug => _decodeSecurityDebug(body),
    RealtimeProtocol.pushRangeMerge => _decodeRangeMerge(body),
    _ => const Ignored('unknown action'),
  };
}

/// The seam form of a path the server sent (`rtdb_seam_changes.md` A.3): `a/b` becomes `/a/b`,
/// `""` (the root) becomes `/`; a path that already starts with `/` is kept.
///
/// The server pushes paths without the leading slash (`"p":"ws/a"`, root `""`), while requests may
/// carry one (`rtdb_emulator_probe.md`, "Paths in pushes have no leading slash", measured). The
/// one place where the connection half converts; used for `d`, `m`, `c`, `rm` and the `s`/`e` of
/// range merges. Validation (threat model T11) is separate.
String wirePathFromServer(String serverPath) {
  if (serverPath.startsWith('/')) {
    return serverPath;
  }
  return '/$serverPath';
}

/// Whether [data] is acceptable server data (threat model T11), checked without recursion: JSON
/// values only, finite numbers, strings of at most 10 MiB of UTF-8, and object keys that follow
/// the write rules (non-empty, at most 768 UTF-8 bytes, none of `. # $ [ ] /` or a control
/// character), except `.priority` anywhere and `.value` next to nothing but `.priority`. `.sv`
/// from the server is refused.
///
/// The decoder applies it to push data, and to the data of the answers its caller flags
/// (`checkAnswerKeys` of [decodeServerMessage]); the REST client applies it to its answers. Same
/// walk as the decoder's. Nesting depth is bounded before decoding (the frame assembler's
/// `checkJsonDepth`, the REST client's own depth walk; threat model T10), not here.
bool isValidServerData(Object? data) =>
    _dataProblem(data, checkKeys: true) == null;

const String _errorKey = 'error';
const String _pathKey = 'p';
const String _dataKey = 'd';
const String _tagKey = 't';
const String _queriesKey = 'q';
const String _statusKey = 's';
const String _messageKey = 'msg';
const String _startKey = 's';
const String _endKey = 'e';
const String _mergeKey = 'm';
const String _ok = 'ok';
const String _priorityKey = '.priority';
const String _valueKey = '.value';

String get _failed => DatabaseErrorCode.operationFailed.wireStatus;

Ignored _violation(String why) => Ignored(why, isProtocolError: true);

ServerMessage _decodeResponse(
  Map<String, Object?> json,
  bool Function(int r)? checkAnswerKeys,
) {
  final int? r = wholeJsonNumber(json[RealtimeProtocol.requestNumberKey]);
  if (r == null || r < 0) {
    return _violation('request number is not a non-negative integer');
  }
  // Asked for every response, so a caller that tracks its requests can forget this one.
  final bool checkKeys = checkAnswerKeys?.call(r) ?? false;
  final Object? body = json[RealtimeProtocol.bodyKey];
  if (body is! Map<String, Object?>) {
    return Response(r, _failed, null);
  }
  final Object? status = body[RealtimeProtocol.statusKey];
  if (status is! String) {
    return Response(r, _failed, null);
  }
  final Object? data = body[_dataKey];
  if (status == _ok) {
    if (_dataProblem(data, checkKeys: checkKeys) != null) {
      return Response(r, _failed, null, dataRefused: true);
    }
    return Response(r, status, data);
  }
  return Response(
    r,
    safeServerText(status),
    data is String ? safeServerText(data) : null,
  );
}

ServerMessage _decodeDataPush(
  Map<String, Object?> body, {
  required bool isMerge,
}) {
  final Object? path = body[_pathKey];
  if (path is! String || _pathProblem(path) != null) {
    return _violation('push path is invalid');
  }
  final (bool tagOk, int? tag) = _tag(body);
  if (!tagOk) {
    return _violation('push tag is not a non-negative integer');
  }
  if (!body.containsKey(_dataKey)) {
    return _violation('push has no data');
  }
  final Object? data = body[_dataKey];
  if (isMerge) {
    if (data is! Map<String, Object?>) {
      return _violation('merge data is not an object');
    }
    for (final MapEntry<String, Object?> entry in data.entries) {
      if (entry.key.isEmpty ||
          entry.key.startsWith('/') ||
          _pathProblem('$path/${entry.key}') != null) {
        return _violation('merge key is not a valid relative path');
      }
      if (_dataProblem(entry.value, checkKeys: true) != null) {
        return _violation('merge data is invalid');
      }
    }
  } else if (_dataProblem(data, checkKeys: true) != null) {
    return _violation('push data is invalid');
  }
  return DataPush(
    path: wirePathFromServer(path),
    data: data,
    isMerge: isMerge,
    tag: tag,
  );
}

ServerMessage _decodeListenRevoked(Map<String, Object?> body) {
  final Object? path = body[_pathKey];
  if (path is! String || _pathProblem(path) != null) {
    return _violation('listen revoke path is invalid');
  }
  final Object? queries = body[_queriesKey];
  if (queries == null) {
    return ListenRevokedPush(path: wirePathFromServer(path));
  }
  if (queries is! List<Object?>) {
    return _violation('listen revoke queries are not a list');
  }
  final List<Map<String, Object?>> objects = <Map<String, Object?>>[];
  for (final Object? query in queries) {
    if (query is! Map<String, Object?> ||
        _dataProblem(query, checkKeys: false) != null) {
      return _violation('listen revoke query is not an object');
    }
    objects.add(query);
  }
  return ListenRevokedPush(path: wirePathFromServer(path), queries: objects);
}

ServerMessage _decodeRevoke(
  Map<String, Object?> body, {
  required bool appCheck,
}) {
  final Object? status = body[_statusKey];
  final Object? explanation = body[_dataKey];
  if (status is! String || (explanation != null && explanation is! String)) {
    return _violation('revoke status or explanation is not a string');
  }
  final String cleanStatus = safeServerText(status);
  final String cleanExplanation = safeServerText(
    explanation is String ? explanation : '',
  );
  if (appCheck) {
    return AppCheckRevokedPush(
      status: cleanStatus,
      explanation: cleanExplanation,
    );
  }
  return AuthRevokedPush(status: cleanStatus, explanation: cleanExplanation);
}

ServerMessage _decodeSecurityDebug(Map<String, Object?> body) {
  final Object? message = body[_messageKey];
  if (message is! String) {
    return _violation('security debug message is not a string');
  }
  return SecurityDebugPush(safeServerText(message));
}

ServerMessage _decodeRangeMerge(Map<String, Object?> body) {
  final Object? path = body[_pathKey];
  if (path is! String || _pathProblem(path) != null) {
    return _violation('range merge path is invalid');
  }
  final (bool tagOk, int? tag) = _tag(body);
  if (!tagOk) {
    return _violation('range merge tag is not a non-negative integer');
  }
  final Object? ranges = body[_dataKey];
  if (ranges is! List<Object?>) {
    return _violation('range merge data is not a list');
  }
  if (ranges.isEmpty) {
    return const Ignored('empty range merge');
  }
  final List<WireRangeMerge> merges = <WireRangeMerge>[];
  for (int i = 0; i < ranges.length; i++) {
    final WireRangeMerge? merge = _rangeEntry(ranges[i], i, ranges.length);
    if (merge == null) {
      return _violation('range merge entry is malformed');
    }
    merges.add(merge);
  }
  return RangeMergePush(
    path: wirePathFromServer(path),
    merges: merges,
    tag: tag,
  );
}

/// Entry [index] of [count], in the shapes measured on the emulator (probe, addendum B): a single
/// entry has neither `s` nor `e`; otherwise the first has only `e`, the last only `s`, the middle
/// ones both; every entry has `m` and no other key.
WireRangeMerge? _rangeEntry(Object? entry, int index, int count) {
  if (entry is! Map<String, Object?> || !entry.containsKey(_mergeKey)) {
    return null;
  }
  for (final String key in entry.keys) {
    if (key != _startKey && key != _endKey && key != _mergeKey) {
      return null;
    }
  }
  final bool wantStart = count > 1 && index > 0;
  final bool wantEnd = count > 1 && index < count - 1;
  if (entry.containsKey(_startKey) != wantStart ||
      entry.containsKey(_endKey) != wantEnd) {
    return null;
  }
  final Object? start = entry[_startKey];
  final Object? end = entry[_endKey];
  if (wantStart && (start is! String || _pathProblem(start) != null)) {
    return null;
  }
  if (wantEnd && (end is! String || _pathProblem(end) != null)) {
    return null;
  }
  final Object? data = entry[_mergeKey];
  if (_dataProblem(data, checkKeys: true) != null) {
    return null;
  }
  return WireRangeMerge(
    exclusiveStart: start is String ? wirePathFromServer(start) : null,
    inclusiveEnd: end is String ? wirePathFromServer(end) : null,
    data: data,
  );
}

/// The tag of a push: absent, null and 0 are untagged (5, Repo.ts:354-410); a positive whole
/// number ([wholeJsonNumber]) is the tag; anything else is invalid (the first value false).
(bool, int?) _tag(Map<String, Object?> body) {
  final Object? raw = body[_tagKey];
  if (raw == null) {
    return (true, null);
  }
  final int? tag = wholeJsonNumber(raw);
  if (tag == null || tag < 0) {
    return (false, null);
  }
  return (true, tag == 0 ? null : tag);
}

/// Why [path] is not a valid server path (threat model T11), or null when it is: an optional
/// leading `/`, then segments that are valid keys, at most 32 of them and 768 UTF-8 bytes in all;
/// no empty segment; `.priority` only as the last of two or more segments. The empty path is the
/// root.
String? _pathProblem(String path) {
  final String relative = path.startsWith('/') ? path.substring(1) : path;
  if (relative.isEmpty) {
    return null;
  }
  if (_utf8Exceeds(relative, RealtimeProtocol.maxPathLengthBytes)) {
    return 'too long';
  }
  final List<String> segments = relative.split('/');
  if (segments.length > RealtimeProtocol.maxPathDepth) {
    return 'too deep';
  }
  for (int i = 0; i < segments.length; i++) {
    final String segment = segments[i];
    final bool priorityLeaf =
        segment == _priorityKey && i > 0 && i == segments.length - 1;
    if (!priorityLeaf && !_isValidKeyText(segment)) {
      return 'invalid segment';
    }
  }
  return null;
}

/// Whether [key] is a valid plain key: non-empty, at most 768 UTF-8 bytes, none of `. # $ [ ] /`
/// and no control character (INVALID_KEY_REGEX_, core/util/validation.ts:45).
bool _isValidKeyText(String key) {
  if (key.isEmpty || _utf8Exceeds(key, RealtimeProtocol.maxPathLengthBytes)) {
    return false;
  }
  for (int i = 0; i < key.length; i++) {
    final int unit = key.codeUnitAt(i);
    if (unit < 0x20 || unit == 0x7F || _isForbiddenKeyUnit(unit)) {
      return false;
    }
  }
  return true;
}

/// `.` `#` `$` `[` `]` `/`: compared, not looked up in a set (no hashing per code unit).
bool _isForbiddenKeyUnit(int unit) => switch (unit) {
  0x2E || 0x23 || 0x24 || 0x5B || 0x5D || 0x2F => true,
  _ => false,
};

bool _isValidDataKey(String key, Map<String, Object?> parent) {
  if (key == _priorityKey) {
    return true;
  }
  if (key == _valueKey) {
    return parent.keys.every((String k) => k == _valueKey || k == _priorityKey);
  }
  return _isValidKeyText(key);
}

/// Why [root] is not acceptable server data, or null (see [isValidServerData]); [checkKeys] off
/// checks only the values (answers, query objects). Iterative: no recursion on server input.
String? _dataProblem(Object? root, {required bool checkKeys}) =>
    _DataWalk(checkKeys).run(root);

/// One walk over server data. Leaves are checked where they are found; only lists and maps go on
/// the stack, and map entries are visited with `forEach` (no `MapEntry` per entry, no lookup).
final class _DataWalk {
  _DataWalk(this._checkKeys);

  final bool _checkKeys;
  final List<Object> _containers = <Object>[];
  Map<String, Object?> _parent = const <String, Object?>{};
  String? _problem;

  String? run(Object? root) {
    _visit(root);
    while (_problem == null && _containers.isNotEmpty) {
      final Object container = _containers.removeLast();
      if (container is List<Object?>) {
        for (final Object? child in container) {
          _visit(child);
          if (_problem != null) {
            break;
          }
        }
      } else if (container is Map<String, Object?>) {
        _parent = container;
        container.forEach(_visitEntry);
      }
    }
    return _problem;
  }

  void _visitEntry(String key, Object? value) {
    if (_problem != null) {
      return;
    }
    if (_checkKeys && !_isValidDataKey(key, _parent)) {
      _problem = 'invalid key';
      return;
    }
    _visit(value);
  }

  void _visit(Object? value) {
    if (value == null || value is bool) {
      return;
    }
    // On the web an infinity also passes `is int`, so finiteness is asked of every number.
    if (value is num) {
      if (!value.isFinite) {
        _problem = 'non-finite number';
      }
    } else if (value is String) {
      if (_utf8Exceeds(value, RealtimeProtocol.maxLeafBytes)) {
        _problem = 'string too long';
      }
    } else if (value is List<Object?> || value is Map<String, Object?>) {
      _containers.add(value);
    } else {
      _problem = 'not a JSON value';
    }
  }
}

/// Whether the UTF-8 encoding of [text] is longer than [limit] bytes, counted only as far as
/// needed (a lone surrogate counts 3 bytes, as its U+FFFD replacement).
bool _utf8Exceeds(String text, int limit) {
  if (text.length * 3 <= limit) {
    return false;
  }
  int bytes = 0;
  for (int i = 0; i < text.length; i++) {
    final int unit = text.codeUnitAt(i);
    if (unit < 0x80) {
      bytes += 1;
    } else if (unit < 0x800) {
      bytes += 2;
    } else if (unit >= 0xD800 &&
        unit <= 0xDBFF &&
        i + 1 < text.length &&
        text.codeUnitAt(i + 1) >= 0xDC00 &&
        text.codeUnitAt(i + 1) <= 0xDFFF) {
      bytes += 4;
      i++;
    } else {
      bytes += 3;
    }
    if (bytes > limit) {
      return true;
    }
  }
  return false;
}
