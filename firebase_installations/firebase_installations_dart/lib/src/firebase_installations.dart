import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_installations_dart/src/backoff.dart';
import 'package:firebase_installations_dart/src/exception.dart';
import 'package:firebase_installations_dart/src/fid.dart';
import 'package:firebase_installations_dart/src/http_rules.dart';
import 'package:firebase_installations_dart/src/log_once.dart';
import 'package:firebase_installations_dart/src/logger.dart';
import 'package:firebase_installations_dart/src/record.dart';
import 'package:firebase_installations_dart/src/rest_client.dart';
import 'package:firebase_installations_dart/src/store/key_value_store.dart';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

final RegExp _apiKeyPattern = RegExp(r'^A[A-Za-z0-9_-]{38}$');
final RegExp _projectIdPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$');
const Set<String> _allowedHeaders = <String>{
  'x-android-package',
  'x-android-cert',
  'x-ios-bundle-identifier',
};
final Uri _defaultOrigin = Uri.parse(
  'https://firebaseinstallations.googleapis.com',
);

/// How old a marker may be and still be fresh.
const Duration _markerMaxAge = Duration(seconds: 15);

/// How far in the future a marker may be and still be fresh (clock skew between tabs).
const Duration _markerMaxSkew = Duration(seconds: 1);

/// How often a waiter re-reads the record when the store does not report changes.
const Duration _pollInterval = Duration(milliseconds: 100);

/// The total time a public call may take.
const Duration _callDeadline = Duration(seconds: 60);

/// The Firebase installation of one app: its installation id (FID) and the auth tokens that prove it.
///
/// The first [getId] creates a FID and stores it; registration with the server starts in the
/// background, and [getToken] waits for it. The record lives in [store] under a key of the app, so the
/// FID survives restarts when the store does (`FileKeyValueStore` on the VM, `IndexedDbKeyValueStore` on
/// the web).
///
/// ```dart
/// final FirebaseInstallations installations = FirebaseInstallations(
///   app,
///   store: FileKeyValueStore('${Platform.environment['HOME']}/.config/my_tool/firebase'),
/// );
/// final String id = await installations.getId();
/// final String token = await installations.getToken();
/// ```
///
/// Concurrent calls of one kind share one operation. Each call fails with `unavailable` after its own
/// 60 s, and the operation behind it stops at its next step once the 60 s of its last caller passed.
/// Errors are [FirebaseInstallationsException]s.
///
/// Several instances can share one record (tabs of a page on one `IndexedDbKeyValueStore`): the one that
/// sends a request writes a marker with its own nonce in the record, the others wait while it is fresh
/// (15 s), and only its owner re-stamps or clears it.
class FirebaseInstallations {
  /// Creates the client of [app]'s installation, stored in [store].
  ///
  /// Throws FirebaseInstallationsException('invalid-app-config') when apiKey, appId or projectId is
  /// missing, apiKey does not match `^A[A-Za-z0-9_-]{38}$` (the format Android and iOS check), appId has
  /// no ':', or projectId does not match `^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$`.
  ///
  /// Throws [ArgumentError] when [headers] has a name other than `X-Android-Package`, `X-Android-Cert` or
  /// `X-Ios-Bundle-Identifier` (case-insensitive) or a value with CR, LF or NUL. Those headers let an API
  /// key restricted to an Android or iOS app accept the requests; they are also sent by Remote Config.
  ///
  /// [httpClient] is used for every request and not closed by [close]; by default the instance creates
  /// one and closes it. [logger] receives log messages (never tokens or the API key). The constructor
  /// reads and sends nothing.
  FirebaseInstallations(
    this.app, {
    required this.store,
    Map<String, String> headers = const <String, String>{},
    http.Client? httpClient,
    InstallationsLogger? logger,
    @visibleForTesting Uri? serverOrigin,
    @visibleForTesting DateTime Function()? clock,
    @visibleForTesting double Function()? random,
    @visibleForTesting Uint8List Function(int length)? randomBytes,
    @visibleForTesting Future<void> Function(Duration duration)? delay,
  }) : headers = Map<String, String>.unmodifiable(_checkHeaders(headers)),
       _ownsClient = httpClient == null,
       _http = httpClient ?? http.Client(),
       _logger = logger,
       _clock = clock ?? DateTime.now,
       _random = random ?? Random().nextDouble,
       _randomBytes = randomBytes ?? _secureBytes,
       _delay = delay ?? Future<void>.delayed {
    try {
      _initialize(logger, serverOrigin);
    } on Object {
      if (_ownsClient) {
        _http.close();
      }
      rethrow;
    }
  }

  void _initialize(InstallationsLogger? logger, Uri? serverOrigin) {
    final FirebaseOptions options = app.options;
    _checkOptions(options);
    _key = 'installations/${app.persistenceKey}';
    _logOnce = LogOnce(
      logger == null
          ? null
          : (String message) => logger(InstallationsLogLevel.warning, message),
    );
    _rest = InstallationsRestClient(
      client: _http,
      origin: checkOrigin(serverOrigin ?? _defaultOrigin),
      apiKey: options.apiKey,
      projectId: options.projectId!,
      appId: options.appId,
      headers: headers,
      clock: _clock,
      delay: _delay,
    );
    _appSubscription = app.onDeleteApp.listen((_) => unawaited(close()));
  }

  /// The app this installation belongs to.
  final FirebaseApp app;

  /// The store holding the installation record. Remote Config stores its records here too.
  final KeyValueStore store;

  /// The restricted-key headers sent with every request (unmodifiable); Remote Config sends them too.
  final Map<String, String> headers;

  final bool _ownsClient;
  final http.Client _http;
  final InstallationsLogger? _logger;
  final DateTime Function() _clock;
  final double Function() _random;
  final Uint8List Function(int length) _randomBytes;
  final Future<void> Function(Duration duration) _delay;
  late final String _key;
  late final LogOnce _logOnce;
  late final InstallationsRestClient _rest;
  late final StreamSubscription<String> _appSubscription;

  final InstallationsBackoff _backoff = InstallationsBackoff();
  final StreamController<String> _idChanges =
      StreamController<String>.broadcast();

  /// The first part of every marker owner this instance writes; see [_newOwner].
  late final String _nonce = base64Url.encode(_secureBytes(12));
  int _claims = 0;
  bool _closed = false;

  /// One entry per public call in flight: it fails the call with `installations-closed`.
  final Set<void Function()> _pendingCalls = <void Function()>{};

  /// The `bad-config` error whose backoff window is running; calls inside the window rethrow it.
  FirebaseInstallationsException? _lastBadConfig;

  /// True once a store call succeeded: a later failure is a transient write failure.
  bool _storeStarted = false;

  /// The last record read or written.
  InstallationRecord? _lastKnown;

  /// The change the store could not take (transient write failure), merged into the stored record by the
  /// next store call.
  _Unsaved? _unsaved;

  StreamSubscription<String>? _changesSubscription;
  final Set<Completer<void>> _waiters = <Completer<void>>{};

  _Shared<String>? _idOperation;
  _Shared<InstallationRecord>? _registerOperation;
  _Shared<({String id, String token})>? _tokenOperation;
  _Shared<({String id, String token})>? _forcedTokenOperation;
  _Shared<void>? _deleteOperation;

  /// The installation id (FID), created and stored on the first call.
  ///
  /// Registration with the server starts in the background; its failure is logged and surfaces at
  /// [getToken]. A configuration failure of the store is thrown (`storage-error`).
  Future<String> getId() => _guard(
    () => _join(_idOperation ??= _share(_getId, () => _idOperation = null)),
  );

  /// A valid auth token of this installation (it lives at least one more hour).
  ///
  /// Waits for the registration. [forceRefresh] asks the server for a new token even when the stored one
  /// is valid.
  Future<String> getToken({bool forceRefresh = false}) async =>
      (await getIdAndToken(forceRefresh: forceRefresh)).token;

  /// A valid auth token and the FID it was issued for, read from one record after the token is obtained,
  /// so the pair always matches (a 401/404 recovery inside the call replaces both).
  Future<({String id, String token})> getIdAndToken({
    bool forceRefresh = false,
  }) {
    if (forceRefresh) {
      return _guard(
        () => _join(
          _forcedTokenOperation ??= _share(
            (_Call call) => _getToken(call, force: true),
            () => _forcedTokenOperation = null,
          ),
        ),
      );
    }
    return _guard(
      () => _join(
        _tokenOperation ??= _share(
          (_Call call) => _getToken(call, force: false),
          () => _tokenOperation = null,
        ),
      ),
    );
  }

  /// Deletes the installation on the server and removes its record.
  ///
  /// Waits for a registration in flight. The next [getId] creates a new FID.
  Future<void> delete() => _guard(
    () => _join(
      _deleteOperation ??= _share(_delete, () => _deleteOperation = null),
    ),
  );

  /// Emits the FID each time this instance creates one or the server assigns a different one. A broadcast
  /// stream; it does not emit the current FID when you listen. It ends at [close].
  ///
  /// A FID created while the store could not be written is emitted too. When the store then turns out
  /// to hold the installation of another instance, that one is used and its FID is emitted.
  Stream<String> get onIdChange => _idChanges.stream;

  /// Releases the instance: ends [onIdChange], stops listening to the app, and closes the HTTP client if
  /// this instance created it. Pending and later calls fail with `installations-closed`. Idempotent; the
  /// store stays open. Called by the instance itself when the app is deleted.
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    for (final void Function() fail in _pendingCalls.toList()) {
      fail();
    }
    _wakeWaiters();
    // Not awaited: cancelling these broadcast subscriptions takes effect at once, and the futures they
    // return can complete outside the caller's zone (fake_async tests never see them complete).
    unawaited(_appSubscription.cancel());
    unawaited(_changesSubscription?.cancel());
    if (_ownsClient) {
      _http.close();
    }
    // Not awaited: a paused listener would hold the close back.
    unawaited(_idChanges.close());
  }

  // Operations.

  Future<String> _getId(_Call call) async {
    final InstallationRecord record = await _ensureRecord();
    if (record.status != InstallationStatus.registered) {
      unawaited(
        _registerShared().then<void>(
          (_) {},
          onError: (Object error) {
            if (error is _Restart) {
              // The server refused the FID (409, logged where it is handled); the next getId creates
              // a new one, and the backoff holds its registration back.
              return;
            }
            _log(
              InstallationsLogLevel.warning,
              'Registration of the installation failed: ${_describe(error)}',
            );
          },
        ),
      );
    }
    return record.fid;
  }

  /// The stored record, created (new FID, unregistered) when there is none or it fails validation.
  Future<InstallationRecord> _ensureRecord() async {
    final InstallationRecord? stored = await _read();
    if (stored != null) {
      return stored;
    }
    String? created;
    final InstallationRecord? record = await _update((
      InstallationRecord? current,
    ) {
      if (current != null) {
        return current;
      }
      final InstallationRecord fresh = _newRecord();
      created = fresh.fid;
      return fresh;
    });
    if (created != null) {
      _emitId(created!);
    }
    return record!;
  }

  InstallationRecord _newRecord() =>
      InstallationRecord.unregistered(generateFid(_randomBytes));

  /// The shared registration for one more caller. [conflictWindow] is given by the one call that
  /// recovers from a 409: the end of the backoff window that 409 started, which the
  /// registration's create may pass once, when it is sent (see [_register]).
  Future<InstallationRecord> _registerShared({DateTime? conflictWindow}) {
    final _Shared<InstallationRecord> shared = _registerOperation ??= _share(
      _register,
      () => _registerOperation = null,
    );
    if (conflictWindow != null) {
      shared.call.conflictWindow = conflictWindow;
    }
    return _join(shared);
  }

  Future<InstallationRecord> _register(_Call call) async {
    while (true) {
      _checkActive(call);
      final InstallationRecord? before = await _read();
      if (before?.status == InstallationStatus.registered) {
        return before!;
      }
      // The create of a 409 recovery passes the window its 409 started, and no other block: not a
      // 24 h block, and not a window a later failure started. The pass is spent when a create is sent,
      // so a look that only waits on another attempt's marker keeps it.
      final DateTime? conflictWindow = call.conflictWindow;
      final bool retry =
          conflictWindow != null && _backoff.retryAfter == conflictWindow;
      final FirebaseInstallationsException? blocked = retry
          ? null
          : _blockedError(_clock());
      if (blocked != null) {
        throw blocked;
      }
      final _Claim claim = await _claimRegistration();
      switch (claim.action) {
        case _Action.done:
          return claim.record;
        case _Action.wait:
          await _pause();
        case _Action.send:
          call.conflictWindow = null;
          final InstallationRecord? result = await _sendCreate(
            claim.record,
            claim.owner,
          );
          if (result != null) {
            return result;
          }
      }
    }
  }

  /// Claims the registration marker: done when the record is registered, wait while another attempt's
  /// marker is fresh, else send (the marker now belongs to the claim's owner). The clock is read inside
  /// the update, so the freshness test and the stamp use the time the store ran it.
  Future<_Claim> _claimRegistration() async {
    final String owner = _newOwner();
    _Action action = _Action.wait;
    String? created;
    final InstallationRecord? record = await _update((
      InstallationRecord? current,
    ) {
      if (current == null) {
        current = _newRecord();
        created = current.fid;
      }
      final DateTime now = _clock();
      switch (current.status) {
        case InstallationStatus.registered:
          action = _Action.done;
          return current;
        case InstallationStatus.registering
            when _isFresh(current.registrationStartedAt, now):
          action = _Action.wait;
          return current;
        case InstallationStatus.registering:
        case InstallationStatus.unregistered:
          action = _Action.send;
          return current.startRegistration(now, owner);
      }
    });
    if (created != null) {
      _emitId(created!);
    }
    return _Claim(action, record!, owner);
  }

  /// Sends create for [claimed], whose marker [owner] holds; the registered record, or null when the
  /// loop must look again (another attempt took the marker over, or the record changed).
  Future<InstallationRecord?> _sendCreate(
    InstallationRecord claimed,
    String owner,
  ) async {
    final String fid = claimed.fid;
    bool owns(InstallationRecord? c) =>
        c != null &&
        c.fid == fid &&
        c.status == InstallationStatus.registering &&
        c.registrationOwner == owner;
    bool pending(InstallationRecord? c) =>
        c != null && c.fid == fid && c.status == InstallationStatus.registering;
    InstallationRecord? release(InstallationRecord? c) =>
        owns(c) ? c!.toUnregistered() : c;
    final RegisteredInstallation result;
    try {
      result = await _rest.create(
        fid,
        beforeAttempt: _afterFirst(() async {
          final InstallationRecord? record = await _update(
            (InstallationRecord? c) =>
                owns(c) ? c!.startRegistration(_clock(), owner) : c,
          );
          if (!owns(record)) {
            throw const _Superseded();
          }
        }),
      );
    } on _Superseded {
      return null;
    } on FirebaseInstallationsException catch (error) {
      if (error.httpStatus == 409) {
        return _afterConflict(error, owns);
      }
      final FirebaseInstallationsException reported = _afterFailure(
        error,
        create: true,
      );
      await _update(release);
      throw reported;
    } on Object {
      await _update(release);
      rethrow;
    }
    _afterSuccess();
    // Stored also when another attempt took the marker over: the server registered this FID, and that
    // attempt's 409 or failure then finds a registered record and leaves it.
    final InstallationRecord? stored = await _update(
      (InstallationRecord? current) => pending(current)
          ? InstallationRecord.registered(
              fid: result.fid,
              refreshToken: result.refreshToken,
              token: result.token.token,
              tokenCreatedAt: result.token.createdAt,
              tokenExpiresIn: result.token.expiresIn,
            )
          : current,
    );
    if (stored == null ||
        stored.fid != result.fid ||
        stored.refreshToken != result.refreshToken) {
      return null;
    }
    _log(InstallationsLogLevel.info, 'The installation is registered.');
    if (store is MemoryKeyValueStore) {
      _logOnce(
        'memory-store',
        'The installation is kept in a MemoryKeyValueStore: a new installation is created at every '
            'process start. Use FileKeyValueStore or IndexedDbKeyValueStore to keep it.',
      );
    }
    if (result.fid != fid) {
      _emitId(result.fid);
    }
    return stored;
  }

  /// The server answered 409 ([error]) to a create. The attempt that still owns the marker removes the
  /// record, counts a recoverable failure in the backoff and throws [_Restart]; one whose marker was
  /// taken over, or whose FID another attempt registered, leaves the record alone and returns null (the
  /// loop looks again).
  Future<InstallationRecord?> _afterConflict(
    FirebaseInstallationsException error,
    bool Function(InstallationRecord? record) owns,
  ) async {
    bool removed = false;
    await _update((InstallationRecord? c) {
      if (!owns(c)) {
        return c;
      }
      removed = true;
      return null;
    });
    if (removed) {
      _afterFailure(error, create: true);
      _log(
        InstallationsLogLevel.warning,
        'The server refused the installation id (409); a new one will be created.',
      );
      throw _Restart(_backoff.retryAfter);
    }
    return null;
  }

  /// The registered record, registering as needed. A 409 (the server refused the FID) is recovered once
  /// per call with a new FID, whose create is sent despite the backoff window the 409 started; a second
  /// one throws `invalid-response`.
  Future<InstallationRecord> _ensureRegistered(_Call call) async {
    DateTime? conflictWindow;
    while (true) {
      _checkActive(call);
      final InstallationRecord? stored = await _read();
      if (stored?.status == InstallationStatus.registered) {
        return stored!;
      }
      await _ensureRecord();
      try {
        return await _registerShared(conflictWindow: conflictWindow);
      } on _Restart catch (restart) {
        if (call.conflicted) {
          throw const FirebaseInstallationsException(
            code: 'invalid-response',
            message:
                'The Firebase Installations server rejected a new installation id twice.',
            httpStatus: 409,
          );
        }
        call.conflicted = true;
        conflictWindow = restart.window;
      }
    }
  }

  Future<({String id, String token})> _getToken(
    _Call call, {
    required bool force,
  }) async {
    bool recovered = false;
    bool forced = force;
    while (true) {
      final InstallationRecord registered = await _ensureRegistered(call);
      if (!forced && registered.hasValidToken(_clock())) {
        return (id: registered.fid, token: registered.token!);
      }
      final FirebaseInstallationsException? blocked = _blockedError(_clock());
      if (blocked != null) {
        throw blocked;
      }
      final _Claim claim = await _claimToken(registered.fid, forced);
      switch (claim.action) {
        case _Action.done:
          // A forced call never returns a token it did not ask for: when the record changed under it,
          // it looks again and asks for the new installation.
          final InstallationRecord record = claim.record;
          if (!forced &&
              record.status == InstallationStatus.registered &&
              record.hasValidToken(_clock())) {
            return (id: record.fid, token: record.token!);
          }
        case _Action.wait:
          await _pause();
        case _Action.send:
          try {
            final InstallationRecord? result = await _sendGenerate(
              claim.record,
              claim.owner,
            );
            if (result != null) {
              return (id: result.fid, token: result.token!);
            }
          } on _NotFound catch (notFound) {
            if (recovered) {
              throw notFound.error;
            }
            recovered = true;
            forced = true;
          }
      }
    }
  }

  /// Claims the token marker of [fid]: done when another writer stored a valid token (non-forced), wait
  /// while another attempt's marker is fresh (non-forced), else send (the marker now belongs to the
  /// claim's owner). A changed record answers done with it. The clock is read inside the update.
  Future<_Claim> _claimToken(String fid, bool force) async {
    final String owner = _newOwner();
    _Action action = _Action.done;
    final InstallationRecord? record = await _update((
      InstallationRecord? current,
    ) {
      if (current?.fid != fid ||
          current!.status != InstallationStatus.registered) {
        action = _Action.done;
        return current;
      }
      final DateTime now = _clock();
      if (!force && current.hasValidToken(now)) {
        action = _Action.done;
        return current;
      }
      if (!force && _isFresh(current.tokenRequestStartedAt, now)) {
        action = _Action.wait;
        return current;
      }
      action = _Action.send;
      return current.withTokenRequest(now, owner);
    });
    return _Claim(
      record == null ? _Action.done : action,
      record ?? InstallationRecord.unregistered(fid),
      owner,
    );
  }

  /// Sends generate for [claimed], whose token marker [owner] holds; the record with the new token, or
  /// null when the loop must look again. Throws [_NotFound] on 401/404 after removing the record.
  Future<InstallationRecord?> _sendGenerate(
    InstallationRecord claimed,
    String owner,
  ) async {
    final String fid = claimed.fid;
    final String refreshToken = claimed.refreshToken!;
    bool same(InstallationRecord? c) =>
        c != null &&
        c.fid == fid &&
        c.status == InstallationStatus.registered &&
        c.refreshToken == refreshToken;
    bool owns(InstallationRecord? c) =>
        same(c) && c!.tokenRequestOwner == owner;
    InstallationRecord? release(InstallationRecord? c) =>
        owns(c) ? c!.withTokenRequest(null, null) : c;
    final AuthTokenResult result;
    try {
      result = await _rest.generateAuthToken(
        fid,
        refreshToken,
        beforeAttempt: _afterFirst(() async {
          final InstallationRecord? record = await _update(
            (InstallationRecord? c) =>
                owns(c) ? c!.withTokenRequest(_clock(), owner) : c,
          );
          if (!owns(record)) {
            throw const _Superseded();
          }
        }),
      );
    } on _Superseded {
      return null;
    } on FirebaseInstallationsException catch (error) {
      final FirebaseInstallationsException reported = _afterFailure(
        error,
        create: false,
      );
      if (error.code == 'installation-not-found') {
        _log(
          InstallationsLogLevel.warning,
          'The server does not know the installation; creating a new one.',
        );
        await _update((InstallationRecord? c) => same(c) ? null : c);
        throw _NotFound(reported);
      }
      await _update(release);
      throw reported;
    } on Object {
      await _update(release);
      rethrow;
    }
    _afterSuccess();
    final InstallationRecord? stored = await _update((InstallationRecord? c) {
      if (!same(c)) {
        return c;
      }
      final InstallationRecord updated = c!.withToken(
        result.token,
        result.createdAt,
        result.expiresIn,
      );
      // Another attempt's marker stays: only its owner clears it.
      return owns(c)
          ? updated
          : updated.withTokenRequest(
              c.tokenRequestStartedAt,
              c.tokenRequestOwner,
            );
    });
    if (!same(stored) || stored!.token != result.token) {
      return null;
    }
    return stored;
  }

  Future<void> _delete(_Call call) async {
    final Future<InstallationRecord>? registering = _registerOperation?.future;
    if (registering != null) {
      await registering.then<void>((_) {}, onError: (Object _) {});
    }
    while (true) {
      _checkActive(call);
      final InstallationRecord? record = await _read();
      if (record == null) {
        return;
      }
      if (record.status == InstallationStatus.registering &&
          _isFresh(record.registrationStartedAt, _clock())) {
        await _pause();
        continue;
      }
      if (record.status == InstallationStatus.registered) {
        await _rest.delete(record.fid, record.refreshToken!);
      }
      if (await _removeDeleted(record)) {
        _log(InstallationsLogLevel.info, 'The installation is deleted.');
        return;
      }
    }
  }

  /// Removes the record [deleted] was read from, deciding inside the update: false (look again) when a
  /// registration started or finished since the read, so no installation is left on the server. A record
  /// that is gone, or has another FID, counts as removed.
  Future<bool> _removeDeleted(InstallationRecord deleted) async {
    bool done = true;
    await _update((InstallationRecord? c) {
      if (c == null || c.fid != deleted.fid) {
        return c;
      }
      final bool claimed =
          c.status == InstallationStatus.registering &&
          _isFresh(c.registrationStartedAt, _clock());
      final bool registeredSince =
          c.status == InstallationStatus.registered &&
          c.refreshToken != deleted.refreshToken;
      if (claimed || registeredSince) {
        done = false;
        return c;
      }
      return null;
    });
    return done;
  }

  // Backoff.

  /// The error to throw when the backoff forbids a request at [now], else null.
  FirebaseInstallationsException? _blockedError(DateTime now) {
    if (_backoff.isAllowed(now)) {
      return null;
    }
    final DateTime? until = _backoff.retryAfter;
    final FirebaseInstallationsException? badConfig = _lastBadConfig;
    if (badConfig != null) {
      return _withRetryAfter(badConfig, until);
    }
    return FirebaseInstallationsException(
      code: 'too-many-requests',
      message:
          'Requests to the Firebase Installations server are paused after earlier failures.',
      retryAfter: until,
    );
  }

  void _afterSuccess() {
    _backoff.afterSuccess();
    _lastBadConfig = null;
  }

  /// Feeds [error] to the backoff by the rules of its endpoint ([create] or generate); returns it with
  /// `retryAfter` when it is a `bad-config` or `too-many-requests` that started a window.
  FirebaseInstallationsException _afterFailure(
    FirebaseInstallationsException error, {
    required bool create,
  }) {
    final DateTime now = _clock();
    switch (_effectOf(error.httpStatus, create: create)) {
      case _Effect.none:
        return error;
      case _Effect.reset:
        _afterSuccess();
        return error;
      case _Effect.block:
        _backoff.afterUnrecoverableFailure(now);
      case _Effect.slow:
        _backoff.afterRecoverableFailure(now, _random());
    }
    if (error.code != 'bad-config' && error.code != 'too-many-requests') {
      _lastBadConfig = null;
      return error;
    }
    final FirebaseInstallationsException reported = _withRetryAfter(
      error,
      _backoff.retryAfter,
    );
    _lastBadConfig = error.code == 'bad-config' ? reported : null;
    return reported;
  }

  /// What a failed create or generate with [status] does to the backoff. 400 and 403 block for 24 h on
  /// both. 401 and 404 mean a wrong project or key on create (a recoverable failure: nothing is reset)
  /// and a forgotten installation on generate (a reset, the recovery follows). Every other status from
  /// 300 up is a recoverable failure: a 3xx (a refused redirect), and a 409 on create (the FID conflict,
  /// reported by [_afterConflict] when it removes the record). A transport error (null) and a 2xx with
  /// a bad body change nothing.
  static _Effect _effectOf(int? status, {required bool create}) {
    if (status == null || status < 300) {
      return _Effect.none;
    }
    return switch (status) {
      400 || 403 => _Effect.block,
      401 || 404 => create ? _Effect.slow : _Effect.reset,
      _ => _Effect.slow,
    };
  }

  static FirebaseInstallationsException _withRetryAfter(
    FirebaseInstallationsException error,
    DateTime? retryAfter,
  ) => FirebaseInstallationsException(
    code: error.code,
    message: error.message ?? '',
    httpStatus: error.httpStatus,
    serverStatus: error.serverStatus,
    serverMessage: error.serverMessage,
    retryAfter: retryAfter,
    cause: error.cause,
    stackTrace: error.stackTrace,
  );

  // Store access.

  Future<InstallationRecord?> _read() async {
    _checkOpen();
    if (_unsaved != null) {
      // Retries the write: the record kept in memory is merged into the stored one.
      return _update((InstallationRecord? current) => current);
    }
    final String? text;
    try {
      text = await store.read(_key);
    } on Object catch (error, stackTrace) {
      _onStoreFailure(error, stackTrace, read: true);
      return _lastKnown;
    }
    _storeStarted = true;
    _logOnce.reset('store-read');
    final InstallationRecord? record = InstallationRecord.tryParse(text);
    if (text != null && record == null) {
      _logOnce(
        'bad-record',
        'The stored installation record could not be read; a new installation will be created.',
      );
    }
    _lastKnown = record;
    return record;
  }

  /// Applies [transform] to the record atomically; a transform that returns its input writes nothing.
  ///
  /// After a transient write failure a changed result is kept in memory ([_unsaved]); a transform that
  /// returned its input leaves nothing to save. The next call does not overwrite the store with the
  /// kept change: inside the same update it first merges it into the stored record ([_merge]), then
  /// applies [transform] to the outcome.
  Future<InstallationRecord?> _update(
    InstallationRecord? Function(InstallationRecord? current) transform,
  ) async {
    _checkOpen();
    _Unsaved? merged;
    InstallationRecord? base;
    InstallationRecord? next;
    String? adopted;
    bool baseAbsent = false;
    bool ran = false;
    try {
      await store.update(_key, (String? text) {
        final InstallationRecord? stored = InstallationRecord.tryParse(text);
        final _Unsaved? unsaved = merged = _unsaved;
        final InstallationRecord? kept = unsaved == null
            ? stored
            : _withoutRemoved(stored, unsaved.removed);
        final InstallationRecord? start = unsaved == null
            ? stored
            : _merge(kept, unsaved);
        base = start;
        adopted = _adoptedFid(unsaved, start);
        baseAbsent = kept == null;
        ran = true;
        final InstallationRecord? result = next = transform(start);
        return identical(result, stored) ? text : result?.encode();
      });
    } on Object catch (error, stackTrace) {
      _onStoreFailure(error, stackTrace, read: false);
      if (!ran) {
        final _Unsaved? unsaved = merged = _unsaved;
        base = unsaved == null ? _lastKnown : unsaved.record;
        baseAbsent = base == null || (unsaved?.baseAbsent ?? false);
        next = transform(base);
      }
      _lastKnown = next;
      final InstallationRecord? from = base;
      if (!identical(next, from)) {
        // Every earlier unsaved removal is kept: the store may still hold any of those records.
        final List<InstallationRecord> removed =
            merged?.removed ?? const <InstallationRecord>[];
        _unsaved = _Unsaved(
          next,
          baseAbsent: baseAbsent,
          removed: next == null && from != null
              ? <InstallationRecord>[...removed, from]
              : removed,
        );
        _emitAdopted(adopted);
      }
      return next;
    }
    _storeStarted = true;
    _lastKnown = next;
    if (merged != null && identical(_unsaved, merged)) {
      _unsaved = null;
      _logOnce.reset('store-write');
      _log(
        InstallationsLogLevel.info,
        'The installation record is saved again.',
      );
      _emitAdopted(adopted);
    }
    return next;
  }

  /// The FID of [start], the record a store call continues from, when it replaces a FID that [unsaved]
  /// kept only in memory, else null. Such a FID was created by this instance and emitted on
  /// [onIdChange] although the store never held it; [start] is then the record of another instance.
  static String? _adoptedFid(_Unsaved? unsaved, InstallationRecord? start) {
    if (unsaved == null || !unsaved.baseAbsent || start == null) {
      return null;
    }
    return start.fid == unsaved.record?.fid ? null : start.fid;
  }

  /// Emits [fid] (see [_adoptedFid]) once the unsaved change it replaced is given up, so a store call
  /// that has to merge again does not emit it twice.
  void _emitAdopted(String? fid) {
    if (fid != null) {
      _emitId(fid);
    }
  }

  /// [stored] after the removals this instance could not write: null when [stored] is still one of the
  /// records it removed ([removed]), else [stored].
  InstallationRecord? _withoutRemoved(
    InstallationRecord? stored,
    List<InstallationRecord> removed,
  ) {
    if (stored == null) {
      return null;
    }
    for (final InstallationRecord record in removed) {
      if (_isRemoved(stored, record)) {
        return null;
      }
    }
    return stored;
  }

  /// Whether [stored] still is the record this instance removed as [removed].
  ///
  /// It must have the FID of [removed] and be no further along: unregistered, a registration marker of
  /// this instance, the marker [removed] had (same owner, and the same start time or one that is stale
  /// by now), or registered with the refresh token of [removed]. A marker another attempt took over, a
  /// marker its owner stamped again since, and a registration finished since stay.
  bool _isRemoved(InstallationRecord stored, InstallationRecord removed) {
    if (stored.fid != removed.fid) {
      return false;
    }
    final bool sameStatus = stored.status == removed.status;
    switch (stored.status) {
      case InstallationStatus.unregistered:
        return true;
      case InstallationStatus.registering:
        if (_isMine(stored.registrationOwner)) {
          return true;
        }
        if (!sameStatus ||
            stored.registrationOwner != removed.registrationOwner) {
          return false;
        }
        return stored.registrationStartedAt == removed.registrationStartedAt ||
            !_isFresh(stored.registrationStartedAt, _clock());
      case InstallationStatus.registered:
        return sameStatus && stored.refreshToken == removed.refreshToken;
    }
  }

  /// The record to continue from when the store holds [stored] (after [_withoutRemoved]) and this
  /// instance kept [unsaved] in memory after a write failure.
  ///
  /// With nothing stored, the in-memory record applies only when nothing was stored under it either;
  /// otherwise another instance deleted the installation, and it stays deleted. With a stored record, it
  /// applies only when that has the same FID and is not further along; it never replaces another FID.
  InstallationRecord? _merge(InstallationRecord? stored, _Unsaved unsaved) {
    final InstallationRecord? mine = unsaved.record;
    if (stored == null) {
      return unsaved.baseAbsent ? mine : null;
    }
    if (mine == null || stored.fid != mine.fid) {
      return stored;
    }
    return _mergeSameFid(stored, mine);
  }

  /// [_merge] for two records of one FID: the status further along wins (registered, then registering,
  /// then unregistered), except that this instance may always replace a marker it wrote itself. Between
  /// two registered records the stored one wins when its refresh token differs or its auth token is
  /// newer.
  InstallationRecord _mergeSameFid(
    InstallationRecord stored,
    InstallationRecord mine,
  ) {
    if (stored.status != mine.status) {
      final bool storedIsMyMarker =
          stored.status == InstallationStatus.registering &&
          _isMine(stored.registrationOwner);
      return storedIsMyMarker || mine.status.index > stored.status.index
          ? mine
          : stored;
    }
    switch (mine.status) {
      case InstallationStatus.unregistered:
        return stored;
      case InstallationStatus.registering:
        return _isMine(stored.registrationOwner) ? mine : stored;
      case InstallationStatus.registered:
        final DateTime? storedAt = stored.tokenCreatedAt;
        final DateTime? mineAt = mine.tokenCreatedAt;
        final bool storedIsNewer =
            storedAt != null && (mineAt == null || storedAt.isAfter(mineAt));
        return stored.refreshToken != mine.refreshToken || storedIsNewer
            ? stored
            : mine;
    }
  }

  /// Throws `storage-error` for a configuration failure (before any store call succeeded, or an [Error]
  /// such as a closed store); logs a transient write failure once.
  void _onStoreFailure(
    Object error,
    StackTrace stackTrace, {
    required bool read,
  }) {
    if (error is Error) {
      Error.throwWithStackTrace(error, stackTrace);
    }
    if (!_storeStarted) {
      if (error is FirebaseInstallationsException) {
        throw error;
      }
      throw FirebaseInstallationsException(
        code: 'storage-error',
        message: 'The installation store failed (${error.runtimeType}).',
        cause: error,
        stackTrace: stackTrace,
      );
    }
    if (read) {
      _logOnce(
        'store-read',
        'Could not read the installation record (${error.runtimeType}); the last record this '
            'instance knows is used.',
      );
      return;
    }
    _logOnce(
      'store-write',
      'Could not write the installation record (${error.runtimeType}); it is kept in memory and '
          'written again at the next operation.',
    );
  }

  /// Waits until the store reports a change of the record or [_pollInterval] passes. Each waiter has its
  /// own completer, so concurrent waiters all wake on a change.
  Future<void> _pause() async {
    _checkOpen();
    _changesSubscription ??= store.changes.listen((String key) {
      if (key == _key) {
        _wakeWaiters();
      }
    });
    final Completer<void> waiter = Completer<void>();
    void wake() {
      if (!waiter.isCompleted) {
        waiter.complete();
      }
    }

    _waiters.add(waiter);
    unawaited(
      _delay(
        _pollInterval,
      ).then<void>((_) => wake(), onError: (Object _) => wake()),
    );
    await waiter.future;
    _waiters.remove(waiter);
  }

  void _wakeWaiters() {
    for (final Completer<void> waiter in _waiters.toList()) {
      if (!waiter.isCompleted) {
        waiter.complete();
      }
    }
  }

  // Helpers.

  /// [restamp] for every attempt after the first (the claim stamped the marker for the first one).
  static Future<void> Function() _afterFirst(Future<void> Function() restamp) {
    bool first = true;
    return () {
      if (first) {
        first = false;
        return Future<void>.value();
      }
      return restamp();
    };
  }

  /// Starts [operation] as a shared operation with its own deadline ([_Call]); [clear] forgets it when
  /// it completes.
  _Shared<T> _share<T>(
    Future<T> Function(_Call call) operation,
    void Function() clear,
  ) {
    final _Call call = _Call();
    return _Shared<T>(
      call,
      operation(call).whenComplete(() {
        call.end();
        clear();
      }),
    );
  }

  /// The future of [shared] for one more caller. The operation, and the registration in flight that it
  /// may be waiting for, get 60 s from now, so they do not stop before this caller's own deadline.
  Future<T> _join<T>(_Shared<T> shared) {
    shared.call.extend();
    _registerOperation?.call.extend();
    return shared.future;
  }

  /// The operation [start] returns, with the 60 s call deadline and the close signal. Nothing starts
  /// when the instance is closed.
  Future<T> _guard<T>(Future<T> Function() start) {
    if (_closed) {
      return Future<T>.error(_closedError());
    }
    final Completer<T> result = Completer<T>();
    void fail(Object error, [StackTrace? stackTrace]) {
      if (!result.isCompleted) {
        result.completeError(error, stackTrace);
      }
    }

    void onClose() => fail(_closedError());
    final Timer deadline = Timer(_callDeadline, () => fail(_deadlineError()));
    _pendingCalls.add(onClose);
    start().then(
      (T value) {
        if (!result.isCompleted) {
          result.complete(value);
        }
      },
      onError: (Object error, StackTrace stackTrace) =>
          fail(_public(error), stackTrace),
    );
    return result.future.whenComplete(() {
      deadline.cancel();
      _pendingCalls.remove(onClose);
    });
  }

  /// [error] as callers see it: internal signals become `installations-closed` or `unavailable`.
  Object _public(Object error) {
    if (error is _NotFound) {
      return error.error;
    }
    if (error is _Restart || error is _Superseded) {
      return const FirebaseInstallationsException(
        code: 'unavailable',
        message: 'The installation kept changing during the call.',
      );
    }
    return error;
  }

  void _checkOpen() {
    if (_closed) {
      throw _closedError();
    }
  }

  /// Stops a loop of [call]'s operation once the instance is closed or the 60 s of its last caller
  /// passed.
  void _checkActive(_Call call) {
    _checkOpen();
    if (call.expired) {
      throw _deadlineError();
    }
  }

  static FirebaseInstallationsException _closedError() =>
      const FirebaseInstallationsException(
        code: 'installations-closed',
        message: 'The FirebaseInstallations instance was closed.',
      );

  static FirebaseInstallationsException _deadlineError() =>
      const FirebaseInstallationsException(
        code: 'unavailable',
        message: 'The Firebase Installations call took longer than 60 s.',
      );

  /// A new marker owner: this instance's nonce and a counter, so every attempt has its own.
  String _newOwner() => '$_nonce.${_claims++}';

  /// Whether this instance wrote the marker of [owner].
  bool _isMine(String? owner) => owner != null && owner.startsWith('$_nonce.');

  void _emitId(String fid) {
    if (!_idChanges.isClosed) {
      _idChanges.add(fid);
    }
  }

  void _log(InstallationsLogLevel level, String message) {
    _logger?.call(level, message);
  }

  static String _describe(Object error) => error is FirebaseException
      ? '${error.code} (${error.runtimeType})'
      : '${error.runtimeType}';

  static bool _isFresh(DateTime? marker, DateTime now) =>
      marker != null &&
      !marker.isBefore(now.subtract(_markerMaxAge)) &&
      !marker.isAfter(now.add(_markerMaxSkew));

  static Uint8List _secureBytes(int length) {
    final Random random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }

  static Map<String, String> _checkHeaders(Map<String, String> headers) {
    for (final MapEntry<String, String> entry in headers.entries) {
      if (!_allowedHeaders.contains(entry.key.toLowerCase())) {
        throw ArgumentError.value(
          entry.key,
          'headers',
          'only X-Android-Package, X-Android-Cert and X-Ios-Bundle-Identifier are allowed',
        );
      }
      final String value = entry.value;
      if (value.contains('\r') ||
          value.contains('\n') ||
          value.contains('\u0000')) {
        throw ArgumentError.value(
          entry.key,
          'headers',
          'the value must not contain CR, LF or NUL',
        );
      }
    }
    return headers;
  }

  static void _checkOptions(FirebaseOptions options) {
    final String? projectId = options.projectId;
    final String? problem = !_apiKeyPattern.hasMatch(options.apiKey)
        ? 'apiKey is missing or is not an API key'
        : !options.appId.contains(':')
        ? 'appId is missing or is not an app id'
        : projectId == null || !_projectIdPattern.hasMatch(projectId)
        ? 'projectId is missing or malformed'
        : null;
    if (problem != null) {
      throw FirebaseInstallationsException(
        code: 'invalid-app-config',
        message: 'The FirebaseOptions of the app cannot be used: $problem.',
      );
    }
  }
}

enum _Action { done, wait, send }

/// What a failed request does to the backoff: nothing, a reset, the 24 h block, or the growing wait.
enum _Effect { none, reset, block, slow }

final class _Claim {
  const _Claim(this.action, this.record, this.owner);

  final _Action action;
  final InstallationRecord record;

  /// The owner written with the marker when [action] is send.
  final String owner;
}

/// The change the store could not take: [record] is the record this instance continued with (null when
/// it removed the record).
final class _Unsaved {
  const _Unsaved(
    this.record, {
    required this.baseAbsent,
    required this.removed,
  });

  final InstallationRecord? record;

  /// Whether nothing was stored under [record] when it was made. Only then may [record] fill an empty
  /// store; otherwise an empty store means another instance deleted the installation.
  final bool baseAbsent;

  /// The records this instance removed and the store may still hold, oldest first. A removal is applied
  /// again only while the stored record still is one of them; see `_withoutRemoved`.
  final List<InstallationRecord> removed;
}

/// A shared operation: its [future] and the [call] that carries its deadline.
final class _Shared<T> {
  const _Shared(this.call, this.future);

  final _Call call;
  final Future<T> future;
}

/// The deadline and the 409 count of one shared operation. [expired] turns true 60 s after its last
/// caller joined; the loops of the operation check it, so an operation never outlives its callers'
/// deadlines for long, and never stops before the deadline of a caller that joined late.
final class _Call {
  _Call() {
    extend();
  }

  Timer? _timer;

  /// True once 60 s passed since the last caller joined.
  bool expired = false;

  /// True once the operation recovered from one 409 on create.
  bool conflicted = false;

  /// On the call of a registration: the end of the backoff window a 409 started, set by the call that
  /// recovers from that 409. The registration sends its next create although that window is running,
  /// and clears this when it sends one.
  DateTime? conflictWindow;

  /// Gives the operation 60 s from now: a caller joined.
  void extend() {
    _timer?.cancel();
    expired = false;
    _timer = Timer(_callDeadline, () => expired = true);
  }

  /// Stops the deadline timer when the operation completes.
  void end() => _timer?.cancel();
}

/// The record changed under an attempt: the loop looks again.
final class _Superseded implements Exception {
  const _Superseded();
}

/// The server answered 409 to create: the record was removed and callers restart.
final class _Restart implements Exception {
  const _Restart(this.window);

  /// The end of the backoff window the 409 started.
  final DateTime? window;
}

/// The server answered 401/404 to generate; the record was removed.
final class _NotFound implements Exception {
  const _NotFound(this.error);

  final FirebaseInstallationsException error;
}
