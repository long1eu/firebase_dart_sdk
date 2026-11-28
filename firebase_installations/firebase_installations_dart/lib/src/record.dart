import 'dart:convert';

import 'package:firebase_installations_dart/src/bounded.dart';
import 'package:firebase_installations_dart/src/fid.dart';
import 'package:meta/meta.dart';

/// The largest stored record read: 64 KiB.
const int installationRecordCap = 64 * 1024;

/// The latest time a stored or server number may name: the end of year 9999, in milliseconds.
const int _maxEpochMillis = 253402300799999;

/// The longest token lifetime accepted: 400 days, in milliseconds.
const int maxTokenLifetimeMillis = 400 * 24 * 60 * 60 * 1000;

/// The longest refresh or auth token accepted from the server or a stored record: 4 KiB.
const int maxTokenLength = 4096;

final RegExp _tokenPattern = RegExp(r'^[\x21-\x7e]+$');
final RegExp _ownerPattern = RegExp(r'^[A-Za-z0-9._-]{1,64}$');

/// Whether [value] can be a refresh or auth token: 1 to 4096 printable ASCII characters (no space), so
/// it fits the record cap and an HTTP header.
bool isValidTokenText(String value) =>
    value.length <= maxTokenLength && _tokenPattern.hasMatch(value);

/// Where an installation is in its registration with the server.
enum InstallationStatus {
  /// Not registered; the FID exists only in the store.
  unregistered,

  /// A create request is (or was) in flight; see [InstallationRecord.registrationStartedAt].
  registering,

  /// Registered: the record holds a refresh token.
  registered,
}

/// The installation record of one app (store key `installations/<app.persistenceKey>`).
@immutable
final class InstallationRecord {
  /// A record with every field given.
  const InstallationRecord({
    required this.fid,
    required this.status,
    this.registrationStartedAt,
    this.registrationOwner,
    this.refreshToken,
    this.token,
    this.tokenCreatedAt,
    this.tokenExpiresIn,
    this.tokenRequestStartedAt,
    this.tokenRequestOwner,
  });

  /// A new unregistered record for [fid].
  const InstallationRecord.unregistered(this.fid)
    : status = InstallationStatus.unregistered,
      registrationStartedAt = null,
      registrationOwner = null,
      refreshToken = null,
      token = null,
      tokenCreatedAt = null,
      tokenExpiresIn = null,
      tokenRequestStartedAt = null,
      tokenRequestOwner = null;

  /// The Firebase installation id.
  final String fid;

  /// The registration status.
  final InstallationStatus status;

  /// When the current create attempt started (the registration marker).
  final DateTime? registrationStartedAt;

  /// The nonce of the attempt that wrote [registrationStartedAt]: only that attempt re-stamps or clears
  /// the marker. Null in a record written before markers had owners (nobody owns such a marker).
  final String? registrationOwner;

  /// The refresh token, set when [status] is registered.
  final String? refreshToken;

  /// The last auth token.
  final String? token;

  /// When [token] was received.
  final DateTime? tokenCreatedAt;

  /// How long [token] lives from [tokenCreatedAt].
  final Duration? tokenExpiresIn;

  /// When the current generate attempt started (the token marker).
  final DateTime? tokenRequestStartedAt;

  /// The nonce of the attempt that wrote [tokenRequestStartedAt]; see [registrationOwner].
  final String? tokenRequestOwner;

  /// The record with the registration marker of [owner] set to [now] and status registering.
  InstallationRecord startRegistration(DateTime now, String owner) =>
      InstallationRecord(
        fid: fid,
        status: InstallationStatus.registering,
        registrationStartedAt: now,
        registrationOwner: owner,
      );

  /// The record back to unregistered, same FID, no marker.
  InstallationRecord toUnregistered() => InstallationRecord.unregistered(fid);

  /// A registered record for [fid] with its tokens.
  static InstallationRecord registered({
    required String fid,
    required String refreshToken,
    required String token,
    required DateTime tokenCreatedAt,
    required Duration tokenExpiresIn,
  }) => InstallationRecord(
    fid: fid,
    status: InstallationStatus.registered,
    refreshToken: refreshToken,
    token: token,
    tokenCreatedAt: tokenCreatedAt,
    tokenExpiresIn: tokenExpiresIn,
  );

  /// The record with the token marker of [owner] set to [now] (nulls clear it).
  InstallationRecord withTokenRequest(DateTime? now, String? owner) =>
      InstallationRecord(
        fid: fid,
        status: status,
        registrationStartedAt: registrationStartedAt,
        refreshToken: refreshToken,
        token: token,
        tokenCreatedAt: tokenCreatedAt,
        tokenExpiresIn: tokenExpiresIn,
        tokenRequestStartedAt: now,
        tokenRequestOwner: now == null ? null : owner,
      );

  /// The record with a new auth token and no token marker.
  InstallationRecord withToken(
    String token,
    DateTime createdAt,
    Duration expiresIn,
  ) => InstallationRecord(
    fid: fid,
    status: status,
    refreshToken: refreshToken,
    token: token,
    tokenCreatedAt: createdAt,
    tokenExpiresIn: expiresIn,
  );

  /// Whether the record holds a token valid at [now]: created no later than now and living at least one
  /// more hour.
  bool hasValidToken(DateTime now) {
    final DateTime? created = tokenCreatedAt;
    final Duration? expiresIn = tokenExpiresIn;
    if (token == null || created == null || expiresIn == null) {
      return false;
    }
    return !created.isAfter(now) &&
        !created.add(expiresIn).isBefore(now.add(const Duration(hours: 1)));
  }

  /// The JSON text of the record.
  String encode() => jsonEncode(toJson());

  /// The JSON object of the record (times in integer milliseconds since the epoch).
  Map<String, Object?> toJson() => <String, Object?>{
    'v': 1,
    'fid': fid,
    'status': status.name,
    if (registrationStartedAt != null)
      'registrationStartedAt': registrationStartedAt!.millisecondsSinceEpoch,
    if (registrationOwner != null) 'registrationOwner': registrationOwner,
    if (refreshToken != null) 'refreshToken': refreshToken,
    if (token != null) 'token': token,
    if (tokenCreatedAt != null)
      'tokenCreatedAt': tokenCreatedAt!.millisecondsSinceEpoch,
    if (tokenExpiresIn != null)
      'tokenExpiresIn': tokenExpiresIn!.inMilliseconds,
    if (tokenRequestStartedAt != null)
      'tokenRequestStartedAt': tokenRequestStartedAt!.millisecondsSinceEpoch,
    if (tokenRequestOwner != null) 'tokenRequestOwner': tokenRequestOwner,
  };

  /// The record stored as [text], or null when it is missing, longer than 64 KiB of UTF-8, not JSON, of
  /// another version, or fails any check.
  static InstallationRecord? tryParse(String? text) {
    if (text == null ||
        text.length > installationRecordCap ||
        utf8.encode(text).length > installationRecordCap) {
      return null;
    }
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      return null;
    }
    if (json is! Map<String, Object?> || json['v'] != 1) {
      return null;
    }
    return _fromJson(json);
  }

  static InstallationRecord? _fromJson(Map<String, Object?> json) {
    final Object? fid = json['fid'];
    final InstallationStatus? status = _status(json['status']);
    if (fid is! String || !isValidFid(fid) || status == null) {
      return null;
    }
    final _Fields? fields = _Fields.read(json);
    if (fields == null) {
      return null;
    }
    if (status == InstallationStatus.registered &&
        fields.refreshToken == null) {
      return null;
    }
    if (status == InstallationStatus.registering &&
        fields.registrationStartedAt == null) {
      return null;
    }
    final bool registered = status == InstallationStatus.registered;
    final bool registering = status == InstallationStatus.registering;
    return InstallationRecord(
      fid: fid,
      status: status,
      registrationStartedAt: registering ? fields.registrationStartedAt : null,
      registrationOwner: registering ? fields.registrationOwner : null,
      refreshToken: registered ? fields.refreshToken : null,
      token: registered ? fields.token : null,
      tokenCreatedAt: registered ? fields.tokenCreatedAt : null,
      tokenExpiresIn: registered ? fields.tokenExpiresIn : null,
      tokenRequestStartedAt: registered ? fields.tokenRequestStartedAt : null,
      tokenRequestOwner: registered && fields.tokenRequestStartedAt != null
          ? fields.tokenRequestOwner
          : null,
    );
  }

  static InstallationStatus? _status(Object? value) {
    for (final InstallationStatus status in InstallationStatus.values) {
      if (status.name == value) {
        return status;
      }
    }
    return null;
  }

  @override
  String toString() => 'InstallationRecord(${status.name}, <redacted>)';
}

/// The optional fields of a stored record, each checked; null when one is present and malformed.
final class _Fields {
  const _Fields({
    required this.registrationStartedAt,
    required this.registrationOwner,
    required this.refreshToken,
    required this.token,
    required this.tokenCreatedAt,
    required this.tokenExpiresIn,
    required this.tokenRequestStartedAt,
    required this.tokenRequestOwner,
  });

  final DateTime? registrationStartedAt;
  final String? registrationOwner;
  final String? refreshToken;
  final String? token;
  final DateTime? tokenCreatedAt;
  final Duration? tokenExpiresIn;
  final DateTime? tokenRequestStartedAt;
  final String? tokenRequestOwner;

  static _Fields? read(Map<String, Object?> json) {
    final _Optional<DateTime> registration = _time(
      json,
      'registrationStartedAt',
    );
    final _Optional<String> registrationOwner = _text(
      json,
      'registrationOwner',
      _ownerPattern.hasMatch,
    );
    final _Optional<String> requestOwner = _text(
      json,
      'tokenRequestOwner',
      _ownerPattern.hasMatch,
    );
    final _Optional<String> refreshToken = _text(
      json,
      'refreshToken',
      isValidTokenText,
    );
    final _Optional<String> token = _text(json, 'token', isValidTokenText);
    final _Optional<DateTime> created = _time(json, 'tokenCreatedAt');
    final _Optional<DateTime> requested = _time(json, 'tokenRequestStartedAt');
    final _Optional<Duration> expiresIn = _duration(json, 'tokenExpiresIn');
    if (!registration.ok ||
        !registrationOwner.ok ||
        !requestOwner.ok ||
        !refreshToken.ok ||
        !token.ok ||
        !created.ok ||
        !requested.ok ||
        !expiresIn.ok) {
      return null;
    }
    final int tokenParts = <Object?>[
      token.value,
      created.value,
      expiresIn.value,
    ].where((Object? part) => part != null).length;
    if (tokenParts != 0 && tokenParts != 3) {
      return null;
    }
    return _Fields(
      registrationStartedAt: registration.value,
      registrationOwner: registrationOwner.value,
      refreshToken: refreshToken.value,
      token: token.value,
      tokenCreatedAt: created.value,
      tokenExpiresIn: expiresIn.value,
      tokenRequestStartedAt: requested.value,
      tokenRequestOwner: requestOwner.value,
    );
  }

  static _Optional<String> _text(
    Map<String, Object?> json,
    String key,
    bool Function(String value) isValid,
  ) {
    final Object? value = json[key];
    if (value == null) {
      return const _Optional<String>(null);
    }
    if (value is! String || !isValid(value)) {
      return const _Optional<String>.bad();
    }
    return _Optional<String>(value);
  }

  static _Optional<DateTime> _time(Map<String, Object?> json, String key) {
    final Object? value = json[key];
    if (value == null) {
      return const _Optional<DateTime>(null);
    }
    final int? millis = parseBoundedInt(value, min: 0, max: _maxEpochMillis);
    if (millis == null) {
      return const _Optional<DateTime>.bad();
    }
    return _Optional<DateTime>(
      DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true),
    );
  }

  static _Optional<Duration> _duration(Map<String, Object?> json, String key) {
    final Object? value = json[key];
    if (value == null) {
      return const _Optional<Duration>(null);
    }
    final int? millis = parseBoundedInt(
      value,
      min: 1000,
      max: maxTokenLifetimeMillis,
    );
    if (millis == null) {
      return const _Optional<Duration>.bad();
    }
    return _Optional<Duration>(Duration(milliseconds: millis));
  }
}

/// A field that is absent ([value] null), present and valid, or present and malformed (not [ok]).
final class _Optional<T> {
  const _Optional(this.value) : ok = true;
  const _Optional.bad() : value = null, ok = false;

  final T? value;
  final bool ok;
}
