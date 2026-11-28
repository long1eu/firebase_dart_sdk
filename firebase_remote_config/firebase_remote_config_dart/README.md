# firebase_remote_config_dart

Unofficial pure-Dart client of Firebase Remote Config: fetch, activate, typed reads, custom signals and
realtime updates, on the Dart VM (macOS, Windows, Linux, servers, command-line tools) and the web
(dart2js and dart2wasm). It talks to the Remote Config REST API and gets its installation id and token
from [`firebase_installations_dart`](../../firebase_installations/firebase_installations_dart).

Status: 0.1.0, first release, not published yet. There is no emulator for Remote Config; the tests use a fake
server. The wire format was measured with probe requests against a test project on 2026-11-27; the client itself has not run against production yet. The production verification kit
(`tool/verify_production_remote_config/`) checks a real project.

## Install

Only `firebase_app_dart` is on pub.dev. Depend on the other two from this repository:

```yaml
dependencies:
  firebase_app_dart: ^0.2.0
  firebase_installations_dart:
    git:
      url: https://github.com/long1eu/firebase_dart_sdk
      ref: main
      path: firebase_installations/firebase_installations_dart
  firebase_remote_config_dart:
    git:
      url: https://github.com/long1eu/firebase_dart_sdk
      ref: main
      path: firebase_remote_config/firebase_remote_config_dart
dependency_overrides:
  firebase_installations_dart:
    git:
      url: https://github.com/long1eu/firebase_dart_sdk
      ref: main
      path: firebase_installations/firebase_installations_dart
```

The `ref: main` lines assume the packages have landed on `main` with this change (until then, use the branch
that carries them).

The `dependency_overrides` entry is needed because `firebase_remote_config_dart` asks pub.dev for
`firebase_installations_dart ^0.1.0`, which does not exist there yet; pub refuses one package from two sources.

Once both are published, `dart pub add firebase_remote_config_dart firebase_installations_dart firebase_app_dart`
does the same, and the override goes away.

The app options come from a web app (or any app) registered in your Firebase project; the console has no desktop
app type, so desktop and server programs use the same options.

## Set up

Remote Config needs a `FirebaseInstallations` for the same app, and Installations needs a store. The
store keeps the installation and the Remote Config records (fetched template, active template, fetch
state, throttle, custom signals), so the choice decides what survives a restart:

| Platform | Store | Notes |
|---|---|---|
| VM | `FileKeyValueStore('<directory>')` from `package:firebase_installations_dart/io.dart` | one process per directory; a directory of the user (on Linux and macOS it must be private to the user) |
| Web | `IndexedDbKeyValueStore()` from `package:firebase_installations_dart/web.dart` | shared by the tabs of an origin |
| Tests | `MemoryKeyValueStore()` | a new installation at every start |

```dart
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_remote_config_dart/firebase_remote_config_dart.dart';

final FirebaseApp app = FirebaseApp.withOptions(
  const FirebaseOptions(
    apiKey: '<the API key of the app, 39 characters>',
    appId: '1:1234567890:web:0123456789abcdef',
    projectId: 'my-project',
  ),
);
final FirebaseInstallations installations = FirebaseInstallations(
  app,
  store: MemoryKeyValueStore(),
);
final FirebaseRemoteConfig remoteConfig = FirebaseRemoteConfig(
  app,
  installations: installations,
  defaults: <String, Object>{'welcome_message': 'Hello', 'max_items': 20},
);
```

The constructor sends nothing; it starts loading the stored records (`ensureInitialized()` completes when
they are loaded). Settings are fixed at construction: `minimumFetchInterval` (12 hours), `fetchTimeout`
(60 seconds), `languageCode` (the language of the process or browser; `en` when empty or blank), `httpClient` and `logger`. `fetch`
takes its own `minimumFetchInterval` and `timeout` per call.

`close()` ends `onConfigUpdated`, aborts requests and closes the HTTP client if the instance created it;
it does not close the Installations instance or the store. Both close themselves when the app is
deleted.

## Fetch and activate

`fetch()` stores the server's template as the fetched record and says what happened; `activate()` makes
it the one reads use.

```dart
final FetchResult result = await remoteConfig.fetch();
switch (result) {
  case FetchResult.updated:
    print('A template arrived.');
  case FetchResult.unchanged:
    print('The stored template is current.');
  case FetchResult.cached:
    print('No request: the last fetch is younger than the minimum interval.');
}
final bool activated = await remoteConfig.activate();
print('activated: $activated');
```

`fetchAndActivate()` does both and returns what `activate()` returns. `activate()` returns false when there
is nothing new to activate: the fetched record has the same fetch time as the active one, or the active record is kept. It is kept only when both records have a template version, the active one is higher, its fetch time is not in the future, and it was fetched at most 24 hours before the fetched record, so a tampered template version blocks `activate()` for at most a day. Otherwise the fetched record replaces it; a record without a version replaces any other fetch. A `NO_TEMPLATE` or `EMPTY_CONFIG` answer stores a record with no values, keeping the template version and ETag when the server sends them. The fetched record is the newer of the stored one and the one in memory (the higher version when both have one, else the later fetch time), except that a stored record with a fetch time in the future loses to a different template in memory (a different version, or the stored one has none); memory with the same version counts as the same record, clamped to now when it was loaded. Calls made while a fetch is in flight share it, unless custom signals or the installation changed since that request was built; a realtime retry, which sends no `If-None-Match`, never joins a request that sends one.

## Values

Reads are synchronous and never fail. A key's value comes from the active template, else the defaults,
else it is the static value (`''`, source `ValueSource.valueStatic`). Before the stored records are
loaded, reads answer from the defaults.

```dart
final String message = remoteConfig.getString('welcome_message');
final int maxItems = remoteConfig.getInt('max_items');
final RemoteConfigValue value = remoteConfig.getValue('welcome_message');
print('$message, $maxItems, from ${value.source.name}');
```

The conversions follow the Android SDK:

- `asBool()`: `1`, `true`, `t`, `yes`, `y`, `on` are true; `0`, `false`, `f`, `no`, `n`, `off` and the empty
  text are false (any case, around whitespace); anything else is null.
- `asInt()`: a decimal integer with an optional sign, within 64 bits on the VM and within ±(2^53 − 1) on
  the web; else null.
- `asDouble()`: a finite number; else null (`Infinity` and `NaN` are refused).
- A static value converts to null.

`getBool`, `getInt` and `getDouble` use the active value if it converts, else the default if it converts,
else `false`, `0`, `0.0`. A remote value that is not a number therefore falls back to your default.

Remote Config values are public (anyone with the app's API key can fetch them) and untrusted: never put
secrets in them, and check them like any input.

## Custom signals

```dart
await remoteConfig.setCustomSignals(<String, Object?>{
  'subscription_tier': 'pro',
  'app_build': 412,
  'old_signal': null, // removes it
});
```

Values are `String`, `int` or finite `double`, stored and sent as text (`1.0` becomes `"1"`). Limits: at most
100 signals, keys of 1-250 characters, strings of at most 500 characters; a violation throws an
`ArgumentError` and stores nothing. A change makes the next `fetch` skip the cache.

Signals have no effect until the template has a condition that uses them: in the Firebase console, add a
"Custom signal" condition to a parameter. Without one, they are sent and ignored.

Never put emails, names or account ids in signals: they are stored unencrypted and sent on every fetch.

## Realtime updates

Listening to `onConfigUpdated` opens a stream to the server, which announces each newly published
template. The client fetches it (it does not activate it) and the event names the keys that differ from
the active template.

```dart
final StreamSubscription<RemoteConfigUpdate> subscription = remoteConfig.onConfigUpdated.listen(
  (RemoteConfigUpdate update) async {
    print('Updated: ${update.updatedKeys}');
    await remoteConfig.activate();
  },
  onError: (Object error) => print('Realtime: $error'),
);
```

- The stream is open while it has a listener and the app is in the foreground. Cancelling the last
  subscription closes the connection.
- Errors do not end the stream (except `realtime-unavailable`): do not use `cancelOnError` if you want to
  keep receiving updates.
- Feed the app's `onBackgroundChanged` and `onNetworkConnected` (through `PlatformDependencies`); by
  default the app never goes to the background and is always connected. A change of
  `onNetworkConnected` from `false` to `true` clears the failure backoff and reconnects at once, still after the 1 s floor and
  after any pause the server asked for with `retryIntervalSeconds`; a `true` that follows a `true` does nothing.
- On failures the client backs off (seconds for network failures, at most about 7 minutes; minutes for
  server throttling) and keeps trying; after eight failures in a row it adds one `stream-error`. A connection with
  no byte from the server for 330 seconds, counted from sending the request, is closed and reopened.
- After an announcement the client fetches in one chain at a time, until it holds the announced version. An answer
  of "no change" below that version counts as stale. If a chain ends without an up-to-date template (its attempts
  ran out, or a fetch failed or was throttled), the next chain waits 60 seconds. A chain is up to date only when the client holds the announced version.
- Realtime needs the project number: an `appId` of the form `1:<number>:...`, or `messagingSenderId`.

## Offline start

Reads return the defaults until a fetch has succeeded once. `getId()` on the Installations instance works
offline. `fetch` throws `fetch-client-network`, or `installations-error` (with a `network-error` as `cause`)
when the installation is not registered yet; neither starts a throttle window.

## Restricted API keys

A key restricted to Android or iOS apps refuses a desktop program, which sends no package name or bundle id.
Use a key without an application restriction, or give `FirebaseInstallations` the matching `headers`
(`X-Android-Package` and `X-Android-Cert`, or `X-Ios-Bundle-Identifier`; no other names are accepted). Whatever
the restriction, the key must allow the Firebase Installations API, the Firebase Remote Config API and the
Firebase Remote Config Realtime API. A key restricted to HTTP referrers works on the web only. A page with a
Content-Security-Policy needs `https://firebaseinstallations.googleapis.com`,
`https://firebaseremoteconfig.googleapis.com` and `https://firebaseremoteconfigrealtime.googleapis.com` in
`connect-src`. The [guide](../../docs/guides/remote_config.md) has the details.

## Throttling

The client does not send a request while the last successful fetch is younger than the minimum interval
(it answers `FetchResult.cached`). After a 429, 502, 503 or 504 it refuses to fetch for 2 minutes, then 4,
8 and up to 256 minutes on repeated failures; inside that window `fetch` throws `fetch-throttle` at once
and sends nothing. `info.throttledUntil` says when it ends. The window is stored and survives restarts.

`fetch(minimumFetchInterval: Duration.zero)` always sends; avoid it in production, where many installations
fetching at once are throttled by the server.

## Errors

Errors are `FirebaseRemoteConfigException`s (a `FirebaseException` with plugin `firebase_remote_config`):

| Code | When |
|---|---|
| `invalid-app-config` | the app options lack `projectId`, `apiKey` or `appId` |
| `installations-error` | the installation id or token could not be obtained; `cause` is the `FirebaseInstallationsException` |
| `fetch-client-network` | the request did not reach the server or the answer did not arrive |
| `fetch-timeout` | the call took longer than its timeout |
| `fetch-throttle` | inside a throttle window, or the server answered 429; see `throttledUntil` |
| `fetch-client-parse` | the answer is not the expected JSON, or is larger than 8 MiB |
| `fetch-status` | another HTTP status; `httpStatus`, `serverStatus`, `serverMessage` |
| `storage-error` | the store did not start, or a write that must persist failed |
| `stream-error` | realtime: eight failures in a row, a refused request, or an Installations configuration error |
| `realtime-unavailable` | the server disabled realtime for the app; the stream ends |
| `update-message-invalid` | a realtime message could not be read |
| `update-not-fetched` | the fetch after a realtime update failed or did not get the new template |
| `remote-config-closed` | the instance was closed |

Messages never hold tokens, the API key, request bodies or signal values.

## Limits

- Custom signals: at most 100; key 1-250 characters; string value at most 500 characters.
- A stored record over 16 MiB is treated as absent.
- One process owns a VM store directory; a second process gets `storage-error`.
- Two tabs on one IndexedDB store share the installation and the records; each holds its own realtime
  stream, and sees another tab's `activate` only after a reload.
- No encryption at rest.
- An `http.Client` that does not request gzip receives no ETag: fetches work, but the server cannot answer
  "unchanged".

## Differences from FlutterFire

- Settings are constructor arguments, not `setConfigSettings`; defaults too, not `setDefaults`.
- `fetch()` returns a `FetchResult` (FlutterFire returns nothing).
- Values follow Android's conversions (FlutterFire's `asBool` knows only `true` and `1`).
- Realtime works on every platform; on the web no `fetchAndActivate` is needed before listening.
- `getKeysByPrefix`, `reset()` and `asJson()` are not provided.
