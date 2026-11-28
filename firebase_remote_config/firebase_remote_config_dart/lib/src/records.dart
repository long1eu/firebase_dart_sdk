import 'dart:convert';

import 'package:firebase_remote_config_dart/src/bounded.dart';
import 'package:firebase_remote_config_dart/src/custom_signals.dart';
import 'package:firebase_remote_config_dart/src/json_guard.dart';
import 'package:firebase_remote_config_dart/src/template.dart';
import 'package:firebase_remote_config_dart/src/types.dart';
import 'package:meta/meta.dart';

/// The largest `staleGeneration`; the next increment wraps to 1.
const int maxStaleGeneration = 0x7fffffff;

/// The longest installation id kept in the `meta` record; a longer one is dropped from the record.
const int maxStoredFidLength = 256;

/// How far ahead a stored throttle window may end (5.10).
const Duration maxStoredThrottle = Duration(hours: 24);

/// The `meta` record of 5.10.
@immutable
final class MetaRecord {
  /// Creates a record.
  const MetaRecord({
    this.lastFetchStatus = RemoteConfigFetchStatus.noFetchYet,
    this.lastSuccessfulFetchTime,
    this.staleGeneration = 0,
    this.fid,
  });

  /// The outcome of the last fetch.
  final RemoteConfigFetchStatus lastFetchStatus;

  /// When the last fetch succeeded.
  final DateTime? lastSuccessfulFetchTime;

  /// The stale flag of 5.5: not 0 makes the next fetch skip the cache and the ETag.
  final int staleGeneration;

  /// The installation id the last successful fetch was made with, or null before the first one. An ID
  /// change to another id makes the cache stale; the first id an installation gets does not.
  final String? fid;

  /// A copy with the given fields replaced.
  MetaRecord copyWith({
    RemoteConfigFetchStatus? lastFetchStatus,
    DateTime? lastSuccessfulFetchTime,
    int? staleGeneration,
    String? fid,
  }) {
    return MetaRecord(
      lastFetchStatus: lastFetchStatus ?? this.lastFetchStatus,
      lastSuccessfulFetchTime:
          lastSuccessfulFetchTime ?? this.lastSuccessfulFetchTime,
      staleGeneration: staleGeneration ?? this.staleGeneration,
      fid: fid ?? this.fid,
    );
  }

  /// A copy with [staleGeneration] incremented (wrapping to 1 after [maxStaleGeneration]).
  MetaRecord incrementStale() => copyWith(
    staleGeneration: staleGeneration >= maxStaleGeneration
        ? 1
        : staleGeneration + 1,
  );

  /// The stored text.
  String encode() => jsonEncode(<String, Object?>{
    'v': 1,
    'lastFetchStatus': lastFetchStatus.name,
    'lastSuccessfulFetchTime': ?lastSuccessfulFetchTime?.millisecondsSinceEpoch,
    'staleGeneration': staleGeneration,
    'fid': ?fid,
  });

  /// Reads a stored record, or returns null for a bad one. A `lastSuccessfulFetchTime` later than [now] is
  /// dropped.
  static MetaRecord? tryParse(String? text, DateTime now) {
    final Map<String, Object?>? json = decodeRecord(text);
    if (json == null) {
      return null;
    }
    final RemoteConfigFetchStatus? status = RemoteConfigFetchStatus.values
        .asNameMap()[json['lastFetchStatus']];
    final int? stale = parseBoundedInt(
      json['staleGeneration'],
      min: 0,
      max: maxStaleGeneration,
    );
    if (status == null || stale == null) {
      return null;
    }
    // A bad `fid` drops only that field; the record then counts as made with another id.
    final Object? storedFid = json['fid'];
    final String? fid =
        storedFid is String &&
            storedFid.isNotEmpty &&
            storedFid.length <= maxStoredFidLength
        ? storedFid
        : null;
    DateTime? last;
    if (json.containsKey('lastSuccessfulFetchTime')) {
      final int? millis = parseBoundedInt(
        json['lastSuccessfulFetchTime'],
        min: -maxDateMillis,
        max: maxDateMillis,
      );
      if (millis == null) {
        return null;
      }
      last = DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
      if (last.isAfter(now)) {
        last = null;
      }
    }
    return MetaRecord(
      lastFetchStatus: status,
      lastSuccessfulFetchTime: last,
      staleGeneration: stale,
      fid: fid,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MetaRecord &&
      other.lastFetchStatus == lastFetchStatus &&
      other.lastSuccessfulFetchTime == lastSuccessfulFetchTime &&
      other.staleGeneration == staleGeneration &&
      other.fid == fid;

  @override
  int get hashCode => Object.hash(
    lastFetchStatus,
    lastSuccessfulFetchTime,
    staleGeneration,
    fid,
  );

  @override
  String toString() => 'MetaRecord(<redacted>)';
}

/// The `throttle` record of 5.10: the count of consecutive throttling failures and the end of the window.
@immutable
final class ThrottleRecord {
  /// Creates a record.
  const ThrottleRecord({this.count = 0, this.until});

  /// The largest stored count.
  static const int maxCount = 1000;

  /// Consecutive throttling failures.
  final int count;

  /// The end of the throttle window.
  final DateTime? until;

  /// The stored text.
  String encode() => jsonEncode(<String, Object?>{
    'v': 1,
    'count': count,
    'until': ?until?.millisecondsSinceEpoch,
  });

  /// Reads a stored record, or returns null for a bad one. An `until` later than [now] + 24 h becomes
  /// [now] + 24 h.
  static ThrottleRecord? tryParse(String? text, DateTime now) {
    final Map<String, Object?>? json = decodeRecord(text);
    if (json == null) {
      return null;
    }
    final int? count = parseBoundedInt(json['count'], min: 0, max: maxCount);
    if (count == null) {
      return null;
    }
    DateTime? until;
    if (json.containsKey('until')) {
      final int? millis = parseBoundedInt(
        json['until'],
        min: -maxDateMillis,
        max: maxDateMillis,
      );
      if (millis == null) {
        return null;
      }
      until = DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
      final DateTime latest = now.add(maxStoredThrottle);
      if (until.isAfter(latest)) {
        until = latest;
      }
    }
    return ThrottleRecord(count: count, until: until);
  }

  @override
  bool operator ==(Object other) =>
      other is ThrottleRecord && other.count == count && other.until == until;

  @override
  int get hashCode => Object.hash(count, until);

  @override
  String toString() => 'ThrottleRecord(<redacted>)';
}

/// How far ahead a stored realtime backoff may end; a later time becomes now plus this.
const Duration maxStoredRealtimeBackoff = Duration(hours: 24);

/// The `realtime` record: the realtime client's failure counts and the ends of its waits (the JS SDK's
/// `realtime_backoff_metadata`, `J:storage/storage.ts:59-64`), so a restart keeps backing off.
@immutable
final class RealtimeBackoffRecord {
  /// Creates a record.
  const RealtimeBackoffRecord({
    this.serverFailures = 0,
    this.transportFailures = 0,
    this.serverUntil,
    this.transportUntil,
    this.retryUntil,
  });

  /// The largest stored count.
  static const int maxCount = 1000;

  /// Consecutive server failures (408, 429, 502, 503, 504, and Installations' `too-many-requests`).
  final int serverFailures;

  /// Consecutive transport failures.
  final int transportFailures;

  /// The end of the server-failure wait.
  final DateTime? serverUntil;

  /// The end of the transport-failure wait.
  final DateTime? transportUntil;

  /// The end of the wait the server asked for with `retryIntervalSeconds`.
  final DateTime? retryUntil;

  /// True when the record holds no count and no wait.
  bool get isEmpty =>
      serverFailures == 0 &&
      transportFailures == 0 &&
      serverUntil == null &&
      transportUntil == null &&
      retryUntil == null;

  /// The stored text.
  String encode() => jsonEncode(<String, Object?>{
    'v': 1,
    'serverFailures': serverFailures,
    'transportFailures': transportFailures,
    'serverUntil': ?serverUntil?.millisecondsSinceEpoch,
    'transportUntil': ?transportUntil?.millisecondsSinceEpoch,
    'retryUntil': ?retryUntil?.millisecondsSinceEpoch,
  });

  /// Reads a stored record, or returns null for a bad one. A time that is not after [now] is dropped
  /// (that wait has passed); a time later than [now] plus [maxStoredRealtimeBackoff] becomes that time.
  static RealtimeBackoffRecord? tryParse(String? text, DateTime now) {
    final Map<String, Object?>? json = decodeRecord(text);
    if (json == null) {
      return null;
    }
    final int? server = parseBoundedInt(
      json['serverFailures'],
      min: 0,
      max: maxCount,
    );
    final int? transport = parseBoundedInt(
      json['transportFailures'],
      min: 0,
      max: maxCount,
    );
    if (server == null || transport == null) {
      return null;
    }
    final DateTime latest = now.add(maxStoredRealtimeBackoff);
    final List<DateTime?> times = <DateTime?>[];
    for (final String name in const <String>[
      'serverUntil',
      'transportUntil',
      'retryUntil',
    ]) {
      if (!json.containsKey(name)) {
        times.add(null);
        continue;
      }
      final int? millis = parseBoundedInt(
        json[name],
        min: -maxDateMillis,
        max: maxDateMillis,
      );
      if (millis == null) {
        return null;
      }
      final DateTime time = DateTime.fromMillisecondsSinceEpoch(
        millis,
        isUtc: true,
      );
      times.add(
        !time.isAfter(now)
            ? null
            : time.isAfter(latest)
            ? latest
            : time,
      );
    }
    return RealtimeBackoffRecord(
      serverFailures: server,
      transportFailures: transport,
      serverUntil: times[0],
      transportUntil: times[1],
      retryUntil: times[2],
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RealtimeBackoffRecord &&
      other.serverFailures == serverFailures &&
      other.transportFailures == transportFailures &&
      other.serverUntil == serverUntil &&
      other.transportUntil == transportUntil &&
      other.retryUntil == retryUntil;

  @override
  int get hashCode => Object.hash(
    serverFailures,
    transportFailures,
    serverUntil,
    transportUntil,
    retryUntil,
  );

  @override
  String toString() => 'RealtimeBackoffRecord(<redacted>)';
}

/// The `signals` record of 5.10.
@immutable
final class SignalsRecord {
  /// Creates a record; [signals] is copied into an unmodifiable map.
  SignalsRecord(Map<String, String> signals)
    : signals = Map<String, String>.unmodifiable(signals);

  /// The custom signals, as sent.
  final Map<String, String> signals;

  /// The stored text.
  String encode() => jsonEncode(<String, Object?>{'v': 1, 'signals': signals});

  /// Reads a stored record, or returns null for a bad one, including one over the limits of 5.8.
  static SignalsRecord? tryParse(String? text) {
    final Map<String, Object?>? json = decodeRecord(text);
    if (json == null) {
      return null;
    }
    final Map<String, String>? signals = asStringMap(json['signals']);
    if (signals == null || !withinSignalLimits(signals)) {
      return null;
    }
    return SignalsRecord(signals);
  }

  @override
  String toString() => 'SignalsRecord(<redacted>)';
}
