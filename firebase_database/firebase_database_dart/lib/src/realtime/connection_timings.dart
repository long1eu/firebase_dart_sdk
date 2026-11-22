/// The constants of the connection half (owner C): timings and limits in [ConnectionTimings],
/// wire strings in [RealtimeProtocol].
///
/// Every value cites its line of `rtdb_protocol.md` section 1 (JS paths relative to
/// `firebase-js-sdk/packages/database/src/`), a decision of the lead (test plan header and 2.4), or
/// the threat model.
library;

/// Timings and limits of one database instance, injected into `RealtimeConnection`,
/// `PersistentConnection` and the units they build (test plan 2.4).
///
/// The defaults are the production values. Integration tests with the chaos proxy pass shrunk
/// values (for example 300 ms) so a scenario takes seconds.
final class ConnectionTimings {
  /// Creates timings; every default is the production value.
  const ConnectionTimings({
    this.maxFrameUnits = 16384,
    this.keepAlive = const Duration(seconds: 45),
    this.connectTimeout = const Duration(seconds: 30),
    this.healthyTimeout = const Duration(seconds: 30),
    this.responsesRequiredToBeHealthy = 2,
    this.extraPingDelay = const Duration(seconds: 5),
    this.bytesSentHealthyOverride = 10 * 1024,
    this.bytesReceivedHealthyOverride = 100 * 1024,
    this.idleProbeAfter = const Duration(seconds: 30),
    this.idleProbeTimeout = const Duration(seconds: 15),
    this.reconnectMin = const Duration(seconds: 1),
    this.reconnectMax = const Duration(seconds: 30),
    this.reconnectMultiplier = 1.3,
    this.reconnectResetAfter = const Duration(seconds: 30),
    this.invalidTokenThreshold = 3,
    this.maxResetsPerAttempt = 3,
    this.forcedRefreshMinInterval = const Duration(seconds: 60),
    this.getTimeout = const Duration(seconds: 3),
    this.requestTimeout = const Duration(seconds: 60),
    this.maxRequestTimeouts = 2,
    this.maxMessageBytes = 256 * 1024 * 1024,
    this.maxJsonDepth = 64,
  });

  /// The largest outgoing frame, in UTF-16 code units: WEBSOCKET_MAX_FRAME_SIZE 16384
  /// (`rtdb_protocol.md` 1.2, realtime/WebSocketConnection.ts:44; Android
  /// WebsocketConnection.java:37-39). The emulator's real limit is 65536 bytes per frame (a larger
  /// frame is closed with 1002; `rtdb_emulator_probe.md` addendum 2 item 5, measured), which 16384
  /// units (at most 49152 UTF-8 bytes) never reach.
  final int maxFrameUnits;

  /// Silence (no send, no receive) after which the keep-alive frame `0` is sent:
  /// WEBSOCKET_KEEPALIVE_INTERVAL 45000 ms (1.2, WebSocketConnection.ts:45,425-435). Must stay
  /// below the server's idle close: the emulator closes a connection that sent no frame for
  /// exactly 120 s (`rtdb_emulator_probe.md`, measured).
  final Duration keepAlive;

  /// How long an attempt may take from opening the socket to the hello: 30000 ms (1.2, Android
  /// WebsocketConnection.java:37-39; LP_CONNECT_TIMEOUT 30000 in 1.6). JS has none for WebSockets.
  final Duration connectTimeout;

  /// Time after the start of a connection by which it must be healthy: healthyTimeout 30000 ms
  /// (1.2, WebSocketConnection.ts:274).
  final Duration healthyTimeout;

  /// Responses (data messages or pongs) that make a connection healthy:
  /// responsesRequiredToBeHealthy 2 (1.2, WebSocketConnection.ts:269).
  final int responsesRequiredToBeHealthy;

  /// Delay after the hello before a control ping is sent to a connection not yet healthy:
  /// DELAY_BEFORE_SENDING_EXTRA_REQUESTS 5000 ms (1.2, realtime/Connection.ts:38).
  final Duration extraPingDelay;

  /// Bytes sent after which an unhealthy connection is left alone: BYTES_SENT_HEALTHY_OVERRIDE
  /// 10 * 1024 (1.2, Connection.ts:43).
  final int bytesSentHealthyOverride;

  /// Bytes received after which a connection counts as healthy: BYTES_RECEIVED_HEALTHY_OVERRIDE
  /// 100 * 1024 (1.2, Connection.ts:44).
  final int bytesReceivedHealthyOverride;

  /// Inbound silence after which a control ping probes the link (the server answers a ping with a
  /// pong at any time, even before the hello; probe addendum 2 item 9, measured): the dead-link
  /// rule of the lead (test plan header and B-3.1i); 30 s is the builder's proposal in test plan
  /// 2.4. Upstream has no inbound timeout (1.2 note, 3.1).
  final Duration idleProbeAfter;

  /// Time a dead-link probe waits for any inbound frame before the connection is closed with
  /// `DisconnectReason.deadLink`: 15 s, proposal of test plan 2.4.
  final Duration idleProbeTimeout;

  /// Upper bound of the first reconnect delay: RECONNECT_MIN_DELAY 1000 ms (1.3,
  /// core/PersistentConnection.ts:45).
  final Duration reconnectMin;

  /// Cap of the reconnect delay: 30 s, the lead's decision (test plan header). JS uses
  /// RECONNECT_MAX_DELAY_DEFAULT 300000 ms and 30000 ms for admins (1.3,
  /// PersistentConnection.ts:46-47); Android 30000 (1.3, RetryHelper.java:89-92).
  final Duration reconnectMax;

  /// Growth of the delay bound per failed attempt: RECONNECT_DELAY_MULTIPLIER 1.3 (1.3,
  /// PersistentConnection.ts:48).
  final double reconnectMultiplier;

  /// Connection age after which the delay goes back to [reconnectMin]:
  /// RECONNECT_DELAY_RESET_TIMEOUT 30000 ms (1.3, PersistentConnection.ts:49).
  final Duration reconnectResetAfter;

  /// Consecutive `invalid_token`/`permission_denied` auth failures after which the delay is set to
  /// the cap and a warning is logged: INVALID_TOKEN_THRESHOLD 3 (1.3, PersistentConnection.ts:53).
  final int invalidTokenThreshold;

  /// Server resets (`r`) followed within one connection attempt before it fails into the backoff:
  /// threat model T2.
  final int maxResetsPerAttempt;

  /// Minimum time between two forced token refreshes of one provider: threat model T14.
  final Duration forcedRefreshMinInterval;

  /// How long a `get` waits for a connection before it falls back to the cache or fails: 3 s, the
  /// lead's decision (Android GET_CONNECT_TIMEOUT; JS waits forever, `rtdb_protocol.md` 12 Q16).
  final Duration getTimeout;

  /// How long a request that expects an answer waits for it before the connection is closed and
  /// replayed: the server answers a request it cannot parse with a control error `e` that has no
  /// request id, or not at all (`rtdb_emulator_probe.md`, measured; lead's decision). The timer
  /// arms only when the request is sent on a connected socket, never while it waits offline. 60 s
  /// is a proposal, NOT MEASURED; the liveness pings already prove that the link is up.
  final Duration requestTimeout;

  /// Timeouts on live connections after which a request fails with status `network_error`
  /// (`DatabaseErrorCode.networkError`) and is not replayed again: 2, the lead's decision. Before
  /// that, a timeout closes the connection and the request is replayed after the reconnect.
  final int maxRequestTimeouts;

  /// Largest inbound message, counted while its frames arrive: 256 MiB, threat model T9 (to be
  /// confirmed by the probe of its open item 5).
  final int maxMessageBytes;

  /// Deepest JSON nesting accepted from the server (envelope 4 + data 32 + wrappers + margin):
  /// threat model T10.
  final int maxJsonDepth;
}

/// The wire strings of protocol 5 (`rtdb_protocol.md` 1.1, 1.2, 1.3, 4.10 and 5).
///
/// Almost everything is a static constant. The one string that differs between servers is an
/// instance field ([unappCheck]); build the instance with [RealtimeProtocol.new] from
/// `RepoInfo.isUsingEmulator`.
final class RealtimeProtocol {
  /// The wire strings for a production database or, with [isUsingEmulator], the emulator.
  const RealtimeProtocol({required bool isUsingEmulator})
    : unappCheck = isUsingEmulator ? 'unappcheck' : 'unappeck';

  /// PROTOCOL_VERSION `5` (1.1, realtime/Constants.ts:18).
  static const String protocolVersion = '5';

  /// VERSION_PARAM `v` (1.1, Constants.ts:20).
  static const String versionParam = 'v';

  /// LAST_SESSION_PARAM `ls` (1.1, Constants.ts:33).
  static const String lastSessionParam = 'ls';

  /// APPLICATION_ID_PARAM `p` (1.1, Constants.ts:35); on the web only (2.3).
  static const String applicationIdParam = 'p';

  /// APP_CHECK_TOKEN_PARAM `ac` (1.1, Constants.ts:37); on the web only (2.3, threat model T25).
  static const String appCheckTokenParam = 'ac';

  /// The namespace query parameter `ns` (2.2, 2.3; RepoInfo.ts:103-109,139).
  static const String namespaceParam = 'ns';

  /// The WebSocket path `/.ws` (1.1, core/RepoInfo.ts:129).
  static const String webSocketPath = '/.ws';

  /// The app id upgrade header on the VM (2.3, Android WebsocketConnection.java:188-191).
  static const String appIdHeader = 'X-Firebase-GMPID';

  /// The App Check upgrade header on the VM (2.3, Android WebsocketConnection.java:188-191).
  static const String appCheckHeader = 'X-Firebase-AppCheck';

  /// The environment variable of the emulator host, read only by an explicit helper (1.1,
  /// api/Database.ts:69; threat model T3).
  static const String emulatorHostVariable = 'FIREBASE_DATABASE_EMULATOR_HOST';

  /// Suffix of the default host `<projectId>-default-rtdb.firebaseio.com` (1.1,
  /// api/Database.ts:135).
  static const String defaultHostSuffix = '-default-rtdb.firebaseio.com';

  /// Longest frame that can be a frame count: 6 characters (1.2, WebSocketConnection.ts:320).
  static const int maxFrameCountLength = 6;

  /// The keep-alive frame (1.2, WebSocketConnection.ts:425-435).
  static const String keepAliveFrame = '0';

  /// Envelope key of the message type (1.2, realtime/Connection.ts:52-62).
  static const String typeKey = 't';

  /// Envelope key of the payload (1.2, Connection.ts:52-62).
  static const String dataKey = 'd';

  /// Message type of data messages (3.1).
  static const String dataMessage = 'd';

  /// Message type of control messages (3.1).
  static const String controlMessage = 'c';

  /// Control type: server hello (1.2, 3.2).
  static const String controlHello = 'h';

  /// Control type: shutdown (1.2, 3.3).
  static const String controlShutdown = 's';

  /// Control type: reset to another host (1.2, 3.3).
  static const String controlReset = 'r';

  /// Control type: server error text (1.2, 3.3).
  static const String controlError = 'e';

  /// Control type: pong (1.2, 3.3).
  static const String controlPong = 'o';

  /// Control type: ping, sent by the client (1.2, 3.4).
  static const String controlPing = 'p';

  /// Control type: long-poll switch ack, ignored (1.2, 3.3).
  static const String controlSwitchAck = 'a';

  /// Control type: long-poll end of transmission, ignored (1.2, 3.3).
  static const String controlEndTransmission = 'n';

  /// Request key of the request number (4, PersistentConnection.ts:175-192).
  static const String requestNumberKey = 'r';

  /// Request key of the action (4).
  static const String actionKey = 'a';

  /// Request key of the body (4).
  static const String bodyKey = 'b';

  /// Response body key of the status (4, PersistentConnection.ts:642-651).
  static const String statusKey = 's';

  /// Action `q` listen (4.1).
  static const String listen = 'q';

  /// Action `n` unlisten (4.2).
  static const String unlisten = 'n';

  /// Action `g` get (4.3).
  static const String get = 'g';

  /// Action `p` put (4.4).
  static const String put = 'p';

  /// Action `m` merge (4.4a).
  static const String merge = 'm';

  /// Action `o` onDisconnect put (4.5).
  static const String onDisconnectPut = 'o';

  /// Action `om` onDisconnect merge (4.5).
  static const String onDisconnectMerge = 'om';

  /// Action `oc` onDisconnect cancel (4.5).
  static const String onDisconnectCancel = 'oc';

  /// Action `auth`: a JWT with `iat` (4.6).
  static const String auth = 'auth';

  /// Action `gauth`: any other credential, such as the emulator's `owner` (4.6).
  static const String gauth = 'gauth';

  /// Action `unauth` (4.7).
  static const String unauth = 'unauth';

  /// Action `appcheck` (4.8).
  static const String appCheck = 'appcheck';

  /// Action removing App Check (4.8). The emulator knows `unappcheck` (Android's spelling) and
  /// answers `unappeck` with a control error (`rtdb_emulator_probe.md`, measured). Production uses
  /// `unappeck`, the spelling of the JS SDK (PersistentConnection.ts:371); that production accepts
  /// it is UNVERIFIED (no production probe yet). Stats (`s`, 4.9) are not sent, so there is no
  /// constant for them (`rtdb_seam_changes.md` D).
  final String unappCheck;

  /// Push `d`: data set (5).
  static const String pushData = 'd';

  /// Push `m`: data merge (5).
  static const String pushMerge = 'm';

  /// Push `c`: listen cancelled (5).
  static const String pushListenCancelled = 'c';

  /// Push `ac`: auth revoked (5).
  static const String pushAuthRevoked = 'ac';

  /// Push `apc`: App Check revoked (5).
  static const String pushAppCheckRevoked = 'apc';

  /// Push `sd`: security debug text (5).
  static const String pushSecurityDebug = 'sd';

  /// Push `rm`: range merge, ignored (no compound hash is sent; 5, 7.4).
  static const String pushRangeMerge = 'rm';

  /// Interrupt reason of a server shutdown, never cleared: SERVER_KILL_INTERRUPT_REASON (1.3,
  /// PersistentConnection.ts:50).
  static const String serverKillInterruptReason = 'server_kill';

  /// Interrupt reason of goOffline: INTERRUPT_REASON `repo_interrupt` (1.3, core/Repo.ts:111).
  static const String repoInterruptReason = 'repo_interrupt';

  /// Deepest path the server may name: MAX_PATH_DEPTH 32 (1.4, core/util/Path.ts:23; threat model
  /// T11).
  static const int maxPathDepth = 32;

  /// Longest path in UTF-8 bytes: MAX_PATH_LENGTH_BYTES 768 (1.4, Path.ts:26; T11).
  static const int maxPathLengthBytes = 768;

  /// Longest leaf string in UTF-8 bytes: MAX_LEAF_SIZE_ 10 MiB (1.4, core/util/validation.ts:56;
  /// T11).
  static const int maxLeafBytes = 10 * 1024 * 1024;
}
