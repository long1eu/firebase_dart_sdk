# Remote Config

`firebase_remote_config_dart` is the Remote Config client of this repository: pure Dart, the REST protocol of the
Firebase JS SDK, no plugin and no native code, on the Dart VM (macOS, Windows, Linux) and the web (dart2js and
dart2wasm). It builds on `firebase_installations_dart`, which gives the app an installation id and an auth token;
both packages are at 0.1.0. This guide covers how to set the two up on each platform, what the store is for,
defaults, fetch and activate, values, custom signals, realtime updates, throttling, errors, and the security rules
the clients follow. How they compare with the official SDKs is in [remote_config_parity.md](../remote_config_parity.md)
and [installations_parity.md](../installations_parity.md); why they differ is in
[remote_config_decisions.md](../remote_config_decisions.md).

There is no Remote Config emulator and no Installations emulator in the Firebase CLI. The wire format (requests,
headers, answers) was measured with probe requests against a test project on 2026-11-27;
the client itself has not run against a production project yet. The
[production kit](../../tool/verify_production_remote_config/README.md) runs checks against your own project. It does
not cover web, throttling, custom signals, restricted keys or long-running realtime streams.

## What you add

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

The lifecycle sample under [Realtime updates](#realtime-updates) also imports `package:rxdart/rxdart.dart`; add
`rxdart` if you use it.

`firebase_remote_config_dart` depends on `firebase_installations_dart` and re-exports `FirebaseInstallations`,
`FirebaseInstallationsException`, `KeyValueStore` and `MemoryKeyValueStore`. You import
`package:firebase_installations_dart/io.dart` for the file store on the VM, or `.../web.dart` for the IndexedDB
store in a browser. No Flutter dependency; Dart 3.8 or later.

## Set up

Three objects, created in this order, once per app:

1. a `KeyValueStore`: where the installation and the Remote Config records are kept;
2. a `FirebaseInstallations`, given the store;
3. a `FirebaseRemoteConfig`, given the Installations instance.

The `FirebaseApp` needs the `apiKey`, `appId` and `projectId` of an app registered in your project (project
settings, "Your apps"). The console has no "desktop app" type: a desktop or server program uses the options of a web
app (or any other app) of the project. Realtime updates also need the project number: it is the second field of the
app id (`1:<number>:web:<hash>`) when that field is all digits, otherwise the `messagingSenderId` option of
`FirebaseOptions` (also all digits). In the samples below, replace the placeholder values with your own.

On the Dart VM, with the file store:

```dart
import 'dart:io';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_installations_dart/io.dart';
import 'package:firebase_remote_config_dart/firebase_remote_config_dart.dart';

Future<void> onTheVm() async {
  final FirebaseApp app = FirebaseApp.withOptions(
    const FirebaseOptions(
      apiKey: 'AIzaSyDummyDummyDummyDummyDummyDummyDum', // placeholder: use your own key
      appId: '1:123456789012:web:0123456789abcdef',
      projectId: 'my-project',
    ),
  );
  final String home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';
  final FileKeyValueStore store = FileKeyValueStore('$home/.my_app/firebase');
  final FirebaseInstallations installations = FirebaseInstallations(app, store: store);
  final FirebaseRemoteConfig remoteConfig = FirebaseRemoteConfig(
    app,
    installations: installations,
    defaults: const <String, Object>{'welcome_message': 'Hello', 'new_checkout': false},
  );

  await remoteConfig.fetchAndActivate();
  print(remoteConfig.getString('welcome_message'));

  await remoteConfig.close();
  await installations.close();
  await store.close();
}
```

In a browser, the store is IndexedDB:

```dart
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_installations_dart/web.dart';
import 'package:firebase_remote_config_dart/firebase_remote_config_dart.dart';

Future<void> inTheBrowser(FirebaseApp app) async {
  final KeyValueStore store = IndexedDbKeyValueStore();
  final FirebaseInstallations installations = FirebaseInstallations(app, store: store);
  final FirebaseRemoteConfig remoteConfig = FirebaseRemoteConfig(app, installations: installations);
  await remoteConfig.fetchAndActivate();
}
```

On Windows `HOME` is not set, so the sample falls back to `USERPROFILE`; keep the store under the user's profile,
not under the working directory (which `'.'` would give).

Constructing the objects sends nothing and reads nothing from the network. `FirebaseRemoteConfig` starts loading its
stored records at once; `ensureInitialized()` completes when they are loaded. Reads made before that answer from the
defaults, as the JS SDK does.

`FirebaseInstallations` throws `FirebaseInstallationsException('invalid-app-config')` when the API key, app id or
project id is missing or malformed (the API key must start with `A` and have 39 characters, as the Android and iOS
SDKs check), and `FirebaseRemoteConfig` throws `FirebaseRemoteConfigException('invalid-app-config')` when one is
missing. Neither client keeps a global instance: two objects are two clients, and you decide who owns them. Closing
a `FirebaseRemoteConfig` does not close its `FirebaseInstallations`; close both when you are done, or delete the
app, which closes them.

## The store

The store holds the installation (its id and its tokens) and the Remote Config records. **Without a store that
survives a restart, every start of the program creates a new installation**, and a percentage rollout can place the
same user in a different group each time. That is why the `store` argument is required and has no default.

| Store | Where | What it is |
|---|---|---|
| `FileKeyValueStore(directory)` | the VM (`io.dart`) | One file per key, written to a temporary file and renamed. The directory is created, made private to the user (`chmod 700`; Linux and macOS) and owned by one process through an OS lock. |
| `IndexedDbKeyValueStore()` | the web (`web.dart`) | One IndexedDB database, `firebase_dart_kv` by default. Tabs of one origin share the installation. |
| `MemoryKeyValueStore()` | anywhere | A map. For tests and one-shot scripts. `FirebaseInstallations` logs one warning when it first registers an installation in a memory store, if you gave it a `logger`; with no logger nothing is printed. |

Rules for the file store:

- **One process per directory.** A second process that opens the same directory gets `storage-error` ("the store
  directory is in use by another process"). Two isolates of one process must not use the same directory either:
  on POSIX the OS lock does not separate them, and a second store for the same directory in one isolate throws
  `StateError`. Give each process its own directory.
- **The directory must be private.** The store runs `chmod 700` on Linux and macOS and refuses to start (with
  `storage-error`) if that fails or the directory is still readable by others. On Windows there is no chmod: use a
  directory inside the user profile.
- A file over 16 MiB (64 KiB for the installation record) is treated as absent. A record that does not parse, or
  fails its checks, is treated as absent too: a corrupt or edited store never stops the app, and the next write
  repairs it.
- **There is no encryption at rest.** The installation record holds the refresh token. A process of the same user
  on a desktop, and any script of a web origin, can read it. Keep it out of backups you share.

Several tabs on one IndexedDB store share the installation and the records; each tab holds its own realtime stream,
and sees another tab's `activate` only after it reads the store again (a reload).

## Defaults

`defaults` are what a read returns for a key the server did not send. They are fixed at construction:

```dart
final FirebaseRemoteConfig withDefaults = FirebaseRemoteConfig(
  app,
  installations: installations,
  defaults: const <String, Object>{
    'welcome_message': 'Hello',
    'max_items': 20,
    'ratio': 0.5,
    'new_checkout': false,
  },
);
```

A value must be a `String`, `bool`, `int` or finite `double`, and a key must not be empty; anything else throws an
`ArgumentError`. The map is read back as `remoteConfig.defaults`, unmodifiable, each value a `RemoteConfigValue`
with the source `valueDefault`.

## Fetch and activate

A fetch asks the server for the template that applies to this installation and stores it. The values do not change
for the app until `activate()`, so a screen does not change under the user in the middle of a session.

```dart
Future<void> refresh(FirebaseRemoteConfig remoteConfig) async {
  final FetchResult result = await remoteConfig.fetch();
  switch (result) {
    case FetchResult.updated:
      print('A new template was stored.');
    case FetchResult.unchanged:
      print('The server says the template has not changed.');
    case FetchResult.cached:
      print('The last fetch is recent enough; no request was sent.');
  }
  final bool activated = await remoteConfig.activate();
  print(activated ? 'New values are active.' : 'Nothing new to activate.');
}
```

- `fetch()` returns a `FetchResult`: `updated`, `unchanged` (the server answered `NO_CHANGE` to the stored ETag) or
  `cached` (no request was sent).
- `activate()` returns `true` only when it made the fetched template the active one. A second call returns `false`.
  It does not replace a record with the same fetch time, nor an active record with a higher template version than the
  fetched one (when both have a version). An empty template (`NO_TEMPLATE` or `EMPTY_CONFIG`) has no version and always
  replaces the active record. The active record is kept only if its fetch time is not in the future and it was
  fetched at most 24 hours before the fetched one.
- `fetchAndActivate()` does both and returns what `activate()` returned, also after a `cached` or `unchanged`
  fetch.

**The cache.** No request is sent while the last successful fetch is younger than `minimumFetchInterval` (12 hours
by default), unless nothing has been stored yet. Set it in the constructor, or per call:

```dart
Future<void> forceRefresh(FirebaseRemoteConfig remoteConfig) async {
  await remoteConfig.fetch(
    minimumFetchInterval: const Duration(minutes: 5),
    timeout: const Duration(seconds: 20),
  );
}
```

`Duration.zero` always sends a request but never bypasses the throttle (below). **Do not use it in production:** a
fleet of clients that fetch at every start is throttled by the server and by the client, and the template only
changes when you publish.

A fetch skips the cache by itself after `setCustomSignals` changes the stored signals, and after the installation id
changes, so the next fetch evaluates the template for the new situation.

**One deadline.** The constructor argument `fetchTimeout` (60 s by default) and the per-call argument `timeout` of
`fetch()` set it; it covers the whole call, the Installations requests included. Calls made while one is in flight
share its request, unless the stored custom signals or the installation id changed after the request was built.

The constructor takes the settings by these names:

```dart
FirebaseRemoteConfig configured(FirebaseApp app, FirebaseInstallations installations) {
  return FirebaseRemoteConfig(
    app,
    installations: installations,
    minimumFetchInterval: const Duration(hours: 1),
    fetchTimeout: const Duration(seconds: 30),
    languageCode: 'en-US',
  );
}
```

**Language.** The request carries the language of the device (`Platform.localeName` on the VM, `navigator.language`
in a browser, reduced to a BCP 47 tag such as `en-US`), or the `languageCode` argument of the constructor; an empty or blank value sends `en`.

## Values

```dart
void readValues(FirebaseRemoteConfig remoteConfig) {
  final String message = remoteConfig.getString('welcome_message');
  final bool checkout = remoteConfig.getBool('new_checkout');
  final int items = remoteConfig.getInt('max_items');
  final double ratio = remoteConfig.getDouble('ratio');

  final RemoteConfigValue value = remoteConfig.getValue('welcome_message');
  print('$message ${value.source.name} ${value.asBool()} $checkout $items $ratio');

  for (final MapEntry<String, RemoteConfigValue> entry in remoteConfig.getAll().entries) {
    print('${entry.key} = ${entry.value.text} (${entry.value.source.name})');
  }
}
```

A read returns the active (fetched and activated) value, else the default, else a static value: `''`, `false`,
`0`, `0.0`. `ValueSource` says which: `valueRemote`, `valueDefault` or `valueStatic`. `getAll()` is the union of the
active and the default keys.

The rules for turning text into a type are Android's:

- `asBool()`: after trimming, case-insensitive, `1`, `true`, `t`, `yes`, `y`, `on` give `true`; `0`, `false`, `f`,
  `no`, `n`, `off` and the empty string give `false`; any other text gives `null`.
- `asInt()`: trimmed text of the form `[+-]?[0-9]+` within 64 bits on the VM and within ±(2^53 − 1) on the web, else
  `null` (so a value between 2^53 and 2^63 reads as an integer on the VM and as `null` on the web). `asDouble()`: the trimmed text parsed as a finite double, else `null`.
- A `valueStatic` value converts to `null`.
- `getBool`, `getInt` and `getDouble` fall through: the active value if it converts, else the default if it
  converts, else `false`, `0`, `0.0`. A malformed remote value therefore falls back to your default instead of
  becoming `false`.

The JS SDK turns every unknown string into `false` and accepts `0x10` and `Infinity` as numbers, and FlutterFire
treats only `true` and `1` as true; code ported from either should be checked against the list above.

`remoteConfig.info` has the state of the last fetch: `lastFetchStatus` (`noFetchYet`, `success`, `failure`,
`throttled`), `lastSuccessfulFetchTime`, `throttledUntil`, `activeTemplateVersion` and `fetchedTemplateVersion`.

**Values are public and untrusted.** Anyone who has your API key and app id (both ship in an app) can fetch the
template. Do not store secrets in it, and treat every value as input: a remote string you put in a URL or a query
needs the same checks as a string from a user.

## Custom signals

Custom signals are values the app sends so that conditions in the template can use them (for example, a plan or a
build channel). They have no visible effect until the template has a condition that uses them: in the Firebase
console, add a "Custom signal" condition to a parameter. Without one, the signals are sent and ignored.

```dart
Future<void> tell(FirebaseRemoteConfig remoteConfig) async {
  await remoteConfig.setCustomSignals(<String, Object?>{
    'plan': 'pro',
    'seats': 12,
    'ratio': 0.25,
    'old_signal': null,
  });
  print(remoteConfig.customSignals);
}
```

Values are `String`, `int` or finite `double`; `null` removes a key. Numbers are sent as text, the same on the VM
and the web (`1.0` is `"1"`). The limits: at most 100 signals after the merge, a key of 1 to 250 characters, a
string value of at most 500 characters. A violation throws an `ArgumentError` that names the limit and the position
of the entry, never its text, and nothing is stored. The signals are stored and sent with every fetch; a change
makes the next fetch skip the cache.

**Do not put emails, names or account ids in signals.** They are stored unencrypted and sent on every fetch, and
they are never logged.

## Realtime updates

Listen to `onConfigUpdated` and the client opens a stream to the Remote Config realtime service. When you publish a
new template, the service announces it, the client fetches it and the stream emits a `RemoteConfigUpdate` with the
keys that changed. The stream never carries values. The client does **not** activate: you decide when.

```dart
import 'dart:async';

StreamSubscription<RemoteConfigUpdate> watch(FirebaseRemoteConfig remoteConfig) {
  return remoteConfig.onConfigUpdated.listen(
    (RemoteConfigUpdate update) async {
      print('Changed: ${update.updatedKeys}');
      await remoteConfig.activate();
    },
    onError: (Object error) {
      if (error is FirebaseRemoteConfigException) {
        print('Realtime problem: ${error.code}');
      }
    },
  );
}
```

How it behaves:

- **Open and closed.** The stream is open while there is a listener, the instance is not closed, realtime is not
  disabled and the app is in the foreground. The last listener cancelling, the app going to the background, and
  `close()` abort the connection at once. In a browser, a hidden tab counts as the background.
- **Do not use `cancelOnError`.** After 8 consecutive failures the stream emits one `stream-error` and keeps
  reconnecting; a listener that cancels on the first error ends it. A non-retryable answer (a 403 carries the
  server's text) or an Installations `bad-config` emits one `stream-error` and stops until you listen again.
- **Tell the app about the network and the foreground.** `FirebaseApp` has two streams for it,
  `onBackgroundChanged` and `onNetworkConnected`. By default the first never says "background" and the second never
  says "offline", and a desktop program has no operating system that feeds them. Overriding these two getters of
  `PlatformDependencies` is all that is needed; your program feeds the two subjects (when the window is hidden, when
  the network drops). The web needs no override for the foreground: a hidden tab already counts as the background.
  Give the app your own source:

```dart
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_app_dart/platform_dependencies.dart';
import 'package:rxdart/rxdart.dart';

class AppDependencies extends PlatformDependencies {
  final BehaviorSubject<bool> background = BehaviorSubject<bool>.seeded(false);
  final BehaviorSubject<bool> connectivity = BehaviorSubject<bool>.seeded(true);

  @override
  BehaviorSubject<bool> get onBackgroundChanged => background;

  @override
  BehaviorSubject<bool> get onNetworkConnected => connectivity;
}

FirebaseApp appWithLifecycle(AppDependencies dependencies) {
  return FirebaseApp.withOptions(
    const FirebaseOptions(
      apiKey: 'AIzaSyDummyDummyDummyDummyDummyDummyDum', // placeholder: use your own key
      appId: '1:123456789012:web:0123456789abcdef',
      projectId: 'my-project',
    ),
    dependencies: dependencies,
  );
}
```

  Feed `connectivity.add(false)` when the network is lost and `connectivity.add(true)` when it returns: a change
  from `false` to `true` clears the failure backoff and lets the client reconnect at once (after the 1 s floor, and
  after a pause the server asked for with `retryIntervalSeconds`); a repeated `true` does nothing. Without it a lost network is found by failed connections; transport failures
  back off for at most 7.5 minutes, and server throttling answers for longer (below).
- **Reconnects.** A connection that fails to open or ends early waits 1, 2, 4, 8, 16, 32, 60, 120 and then 300
  seconds, each with jitter between 0.5 and 1.5 times; an answer of 408, 429, 502, 503 or 504 uses the longer table of
  the Android SDK (2 minutes, doubling to 256 minutes). A connection that stays open for a minute counts as healthy
  and resets both. A connection that receives no byte for 330 seconds (counted from sending the request) is closed
  and reopened. The server may also send a pause (`retryIntervalSeconds`, at most a day) or turn the feature off:
  `featureDisabled` ends every stream of this instance with `realtime-unavailable`, and later listeners get the
  same at once.
- **The fetch after a message.** The client fetches through the same path as `fetch()`: the shared throttle applies,
  and a fetch that fails or leaves the client stale gives the listeners one `update-not-fetched`. One fetch chain runs at a time. If a chain ends without an up-to-date template (its attempts ran out, or a fetch
  failed or was throttled), the next chain starts 60 seconds later; after an up-to-date chain the next announcement
  starts one at once. A chain is up to date only when the client holds the announced version, so an unchanged
  answer below it counts as stale. An update that changes no key produces no event.
- **The installation changes.** The stream reconnects with the new id.

The package works without a first `fetch`: the first message makes the client fetch the template. (The JS SDK
does not; FlutterFire's web documentation asks for a fetch first.)

## Offline start

A program that starts without a network keeps working:

- Reads return the defaults (then the static values) until a fetch has succeeded once. After one, they return the
  last activated template, also offline.
- `getId()` works offline: it creates the installation id and stores it, and registers it with the server later.
- `fetch()` throws `FirebaseRemoteConfigException`. When the installation is already registered and has a valid
  token, the code is `fetch-client-network`. When there is nothing registered yet, the call cannot get a token, and
  the code is `installations-error` with a `FirebaseInstallationsException('network-error')` as `cause`. Both mean
  "try again when the network is back"; neither stores anything or starts a throttle window.
- `onConfigUpdated` keeps trying to connect with the back-off of the next section; see `onNetworkConnected` above
  to make it reconnect as soon as the network returns.

## Throttling

The service limits how often an installation may fetch. After a 429, 502, 503 or 504 answer the client refuses to
send another request until a time it computes: 2, 4, 8, 16, 32, 64, 128 and then 256 minutes for the 1st to 8th
consecutive failure, each multiplied by a random factor between 0.5 and 1.5. The wait is stored, so a restart does
not forget it, and it applies to realtime fetches too.

- A refused call throws `FirebaseRemoteConfigException('fetch-throttle')` at once, with `throttledUntil`, and sends
  nothing (not even an Installations request). `info.lastFetchStatus` is `throttled`.
- The call that received the 429 throws `fetch-throttle`; one that received another throttling status throws
  `fetch-status` with `httpStatus` and `throttledUntil`.
- A valid answer resets the count. Other errors (a bad body, a transport failure, other statuses) do not throttle.

The client fails fast instead of waiting inside `fetch` as the JS SDK does: a server, or an app that is starting,
cannot tell a long wait from a hang. Show the cached values and try later.

## Errors

Every exception is a `FirebaseException` with a kebab-case `code`. `FirebaseRemoteConfigException` also has
`httpStatus`, `serverStatus`, `serverMessage` (control characters removed, at most 1 KiB), `throttledUntil` and
`cause`; `firebaseRemoteConfigExceptionCodes` lists the codes.

| Code | When |
|---|---|
| `invalid-app-config` | `projectId`, `apiKey` or `appId` is missing |
| `installations-error` | the installation id or token could not be obtained; `cause` is the `FirebaseInstallationsException` |
| `fetch-client-network` | a transport failure, including a refused redirect in a browser |
| `fetch-timeout` | the call's deadline passed |
| `fetch-throttle` | inside a backoff window, or a 429; `throttledUntil` is set |
| `fetch-client-parse` | the body is not JSON, has fields of the wrong type, is over 8 MiB, or nests deeper than 32 levels |
| `fetch-status` | another non-200 answer, including a 3xx on the VM |
| `storage-error` | the store cannot be used, or a write that must persist failed |
| `stream-error` | realtime: 8 consecutive failures, a non-retryable answer, or an Installations `bad-config` |
| `realtime-unavailable` | the server turned realtime off |
| `update-message-invalid` | a realtime message that is not a valid JSON object |
| `update-not-fetched` | the fetch after a realtime message failed or stayed stale |
| `remote-config-closed` | the instance was closed |

Installations has its own: `invalid-app-config`, `bad-config` (400 or 403: look at the key's restrictions and the
enabled APIs), `installation-not-found`, `too-many-requests`, `unavailable`, `network-error`, `invalid-response`,
`storage-error` and `installations-closed`. After a 400 or 403 the client does not send another create or token
request for 24 hours, and rethrows `bad-config` with `retryAfter`; a new instance tries again. A 401 or 404 on a
create request is also `bad-config`, without the 24 hours. A 409 on a create request, a 3xx and other failures start
a shorter backoff (a few seconds, at most 30 minutes); one call recovers from one 409 with a new id and fails with
`invalid-response` on a second, and a call made inside the window of a 409 throws `too-many-requests`. Any other
unexpected 4xx (408, for example) is `invalid-response` with the status kept; it is not `bad-config`.

```dart
Future<void> safeFetch(FirebaseRemoteConfig remoteConfig) async {
  try {
    await remoteConfig.fetchAndActivate();
  } on FirebaseRemoteConfigException catch (error) {
    switch (error.code) {
      case 'fetch-throttle':
        print('Try again after ${error.throttledUntil}.');
      case 'installations-error':
        print('No installation: ${error.cause}');
      default:
        print('${error.code} ${error.httpStatus}');
    }
  }
}
```

## Restricted API keys

An API key can be restricted in the Google Cloud console by application (Android apps, iOS apps, or HTTP referrers)
and by API. The Android and iOS SDKs send the package name and certificate, or the bundle id, so their requests
pass. A desktop or server program has neither. Either use a key without an application restriction, or pass the
headers the restriction expects: `X-Android-Package` and `X-Android-Cert` for an Android key, `X-Ios-Bundle-Identifier`
for an iOS key.

Whatever the application restriction, the key must allow these three APIs, and the APIs must be enabled in the
project:

- Firebase Installations API (registration and tokens);
- Firebase Remote Config API (fetch);
- Firebase Remote Config Realtime API (`onConfigUpdated`; without it the stream ends with a 403 `stream-error`).

Publish a template in the console too: with none, a fetch returns no values.

A key restricted to HTTP referrers works on the web only. A browser sends the `Referer` header; a program on the VM
cannot, and its requests get 403 (`bad-config` from Installations).

```dart
FirebaseInstallations restricted(FirebaseApp app, KeyValueStore store) {
  return FirebaseInstallations(
    app,
    store: store,
    headers: const <String, String>{
      'X-Android-Package': 'com.example.app',
      'X-Android-Cert': 'ABCDEF0123456789ABCDEF0123456789ABCDEF01',
    },
  );
}
```

`headers` accepts exactly `X-Android-Package`, `X-Android-Cert` and `X-Ios-Bundle-Identifier`; any other name throws
an `ArgumentError`. Remote Config reads them from the `FirebaseInstallations` it is given and sends the same ones.

On the web, a page with a Content-Security-Policy needs these three hosts in `connect-src`:
`https://firebaseinstallations.googleapis.com`, `https://firebaseremoteconfig.googleapis.com` and
`https://firebaseremoteconfigrealtime.googleapis.com`.

## Security notes

The two clients follow one set of rules (decision D14 in [remote_config_decisions.md](../remote_config_decisions.md)):

- The refresh token goes only to the Installations server. The client's origins are fixed at construction: `https`,
  or `http` to a loopback host (for a fake server in tests).
- Redirects are refused. Response bodies are capped (Remote Config 8 MiB, Installations 64 KiB, error bodies 16 KiB,
  one realtime message 16 KiB), and deeply nested JSON is rejected before it is decoded.
- Every number from the server or the store is checked against a range, and means the same on the VM and in a
  browser.
- No log line, exception message or `toString` holds a token, the API key, a request body or a signal's text. Pass
  a `logger` to the constructors to see what the clients do; it never receives those.
- Nothing is written outside the store, and on the web tokens never travel in a `BroadcastChannel` message.
- The installation record is not encrypted (see [The store](#the-store)).

## Testing your own code

There is no emulator. For unit tests:

- Pass `MemoryKeyValueStore()` and an `http.Client` (a `MockClient` from `package:http/testing.dart`) to
  `FirebaseInstallations` and `FirebaseRemoteConfig`, and answer the requests yourself: `POST
  /v1/projects/<project>/installations` and `.../authTokens:generate` for Installations, `POST
  /v1/projects/<project>/namespaces/firebase:fetch` for Remote Config.
- Or give your tests a stub of the thin interface you put in front of Remote Config, and keep the package behind it.

`tool/verify_production_remote_config/run.sh` in the repository runs the clients against your real project, and
[`examples/remote_config_web`](../../examples/remote_config_web) is a browser page that fetches, shows the values
and logs realtime updates.

## FlutterFire (`firebase_remote_config_dart_platform`)

A Flutter app written against the official `firebase_remote_config` API can run on this client through
`firebase_remote_config_dart_platform`. On Linux, adding the package is enough. On other platforms, call
`FirebaseRemoteConfigDart.use()` first in `main()`:

```dart flutter
WidgetsFlutterBinding.ensureInitialized();
FirebaseRemoteConfigDart.use();
await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
await FirebaseRemoteConfig.instance.fetchAndActivate();
```

- The default store is one per isolate: on the VM, a `firebase_dart` folder under the application support directory;
  on the web, the IndexedDB database `firebase_dart_kv`. A second process of the same desktop app gets the error code
  `internal` ("in use by another process"); `FirebaseRemoteConfigDart.use(store: ...)` gives each process its own
  directory.
- Values use FlutterFire's conversions: only `true` and `1` are true.
- Error codes on the VM are `network-error`, `throttled`, `forbidden`, `remote-config-server-error`,
  `invalid-argument` and `internal`; on the web they are this client's codes.

See the [package README](../../firebase_remote_config/firebase_remote_config_dart_platform/README.md).

## What differs from FlutterFire and the JS SDK

- Configuration is immutable and given to the constructor: `defaults`, `minimumFetchInterval`, `fetchTimeout`.
  FlutterFire has setters (`setConfigSettings`, `setDefaults`) that must run before the reads that depend on them.
- `fetch()` returns a `FetchResult`.
- A throttled call fails at once with `fetch-throttle`.
- The store is required, and the installation is registered with the server and kept, so the id is stable across
  fetches (the official C++ desktop SDK sends a new random id with every fetch).
- Realtime works on desktop. `onConfigUpdated` needs no first fetch, and the stream is yours to activate.
- The value rules are Android's, not FlutterFire's.
- No emulator support, no Analytics, no A/B testing hand-off, no `getKeysByPrefix`, `reset()` or `asJson()` in 0.1.0.
