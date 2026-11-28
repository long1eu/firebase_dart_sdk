# firebase_remote_config_dart_platform

An unofficial implementation of the platform interface of the official
[`firebase_remote_config`](https://pub.dev/packages/firebase_remote_config) Flutter plugin, on top of
[`firebase_remote_config_dart`](https://pub.dev/packages/firebase_remote_config_dart) and
[`firebase_installations_dart`](https://pub.dev/packages/firebase_installations_dart), pure-Dart clients of the
Remote Config and Installations REST APIs. Your app keeps the official API (`fetchAndActivate()`, `getString(...)`,
`onConfigUpdated`, ...), and the Dart clients do the work underneath, without the native Firebase SDKs.

You need it for a Flutter app on Linux desktop, where `firebase_remote_config` and `firebase_core` have no
implementation of their own: add it to `pubspec.yaml` and it registers itself. On Windows and macOS it is an opt-in
that gives realtime updates and persistence through the same clients. It is not affiliated with or endorsed by
Google or Firebase.

> **Status: 0.1.0.** Not yet tested in a desktop build or against a production project.

## How to enable it

The adapter needs Dart ^3.12 and Flutter >=3.44. It and the two clients below it are not on pub.dev yet, so
depend on them from this repository (`firebase_app_dart` is hosted):

```yaml
dependencies:
  firebase_core: ^5.1.0
  firebase_remote_config: ^7.1.0
  firebase_remote_config_dart_platform:
    git:
      url: https://github.com/long1eu/firebase_dart_sdk
      ref: main
      path: firebase_remote_config/firebase_remote_config_dart_platform
dependency_overrides:
  firebase_remote_config_dart:
    git:
      url: https://github.com/long1eu/firebase_dart_sdk
      ref: main
      path: firebase_remote_config/firebase_remote_config_dart
  firebase_installations_dart:
    git:
      url: https://github.com/long1eu/firebase_dart_sdk
      ref: main
      path: firebase_installations/firebase_installations_dart
```

The `ref: main` lines assume the packages have landed on `main` with this change (until then, use the branch
that carries them).

The two overrides are needed because the adapter asks pub.dev for `firebase_remote_config_dart ^0.1.0` and
`firebase_installations_dart ^0.1.0`, which do not exist there yet. Once the packages are published, the
three hosted entries (`firebase_remote_config_dart_platform: ^0.1.0` and the two clients) replace this block.

**On Linux** nothing else is needed: Flutter calls `FirebaseRemoteConfigDart.registerWith()` before `main()`. Pass
the options to `Firebase.initializeApp` (there is no native configuration file to read them from):

```dart
await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
final FirebaseRemoteConfig remoteConfig = FirebaseRemoteConfig.instance;
await remoteConfig.fetchAndActivate();
print(remoteConfig.getString('welcome_message'));
```

**On Windows, macOS and the other platforms**, call `FirebaseRemoteConfigDart.use()` at the start of `main()`, before
the first use of `Firebase` or `FirebaseRemoteConfig`. There `firebase_core` keeps its native implementation, and the
native Remote Config SDK is still built into the app, unused.

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FirebaseRemoteConfigDart.use();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp());
}
```

### Options of `use`

| Argument | Default | What it does |
| --- | --- | --- |
| `store` | one store per isolate (below) | Keeps the installation and the Remote Config records of every app. |
| `httpClient` | each client creates its own | The `http.Client` of the requests of both Installations and Remote Config (tests, proxies). |
| `languageCode` | the platform's locale | The language the template's conditions see. |
| `useDartCore` | Linux only, when `firebase_core` has no other implementation | Installs a small pure-Dart `firebase_core`. Pass `true` to force it (tests), `false` to never do it. |

`use()` throws a `StateError` once an instance has created its clients, because the configuration is read then.

### The default store

Without `use(store: ...)`, every app shares one store per isolate; each app's records are kept under a key of its
own. If the lookup of the application support directory fails, the next call tries it again.

- **Linux, Windows, macOS:** a `FileKeyValueStore` in the `firebase_dart` directory under the application support
  directory (`getApplicationSupportDirectory()` of `path_provider`). A store directory belongs to one process. A
  second process of the same desktop app gets the error `internal` with the message "the store directory is in use by
  another process"; to run several processes, give each its own directory:

  ```dart
  FirebaseRemoteConfigDart.use(
    store: FileKeyValueStore('${support.path}/firebase_dart_$processName'),
  );
  ```

  (`FileKeyValueStore` comes from `package:firebase_installations_dart/io.dart`.) On Windows, after a hot restart
  the new isolate can report the same error until the app is fully restarted, because the old isolate still holds
  the lock.

  The default store is one per isolate, not per process. Two isolates or Flutter engines of one process that both
  use it are not kept apart (on POSIX the lock belongs to the process, so neither gets the error) and can, for
  example, each create an installation. Give each of them its own directory with `use(store: ...)`.
- **Web:** the IndexedDB database `firebase_dart_kv`, shared by the tabs of the origin.
- **Tests:** pass `MemoryKeyValueStore()`, which this package re-exports.

### `firebase_core` on Linux

`firebase_core` has no Linux implementation either. This package installs a small one (apps in memory,
`initializeApp` needs `options`) only while `firebase_core` still has its default implementation. The other platform
packages of this repository do the same with their own, so they can be in one app: whichever registers first provides
`firebase_core`, and the others keep it. Under `flutter test`, the registration on Linux leaves `firebase_core` alone,
so that `setupFirebaseCoreMocks` keeps working; call `use()` to choose otherwise.

## What is implemented

| Official API | Underneath | Notes |
| --- | --- | --- |
| `FirebaseRemoteConfig.instanceFor(app:)` | one `FirebaseInstallations` and one `FirebaseRemoteConfig` per app | created on first use |
| `fetch`, `fetchAndActivate` | the client's `fetch` and `fetchAndActivate` | with the timeout and minimum fetch interval of `settings` |
| `activate`, `ensureInitialized` | the client's | |
| `setConfigSettings`, `settings` | kept by this package | 60 s and 12 h before the first call; a negative fetch timeout or interval throws `invalid-argument` (a zero timeout is kept, as the client accepts it); `settings` returns a copy |
| `setDefaults` | kept by this package | values kept as `toString()`, as Android does; a `List<int>` as its bytes decoded as UTF-8; a null value is left out |
| `getValue`, `getString`, `getBool`, `getInt`, `getDouble`, `getAll` | the client's active values, then the defaults | FlutterFire's conversions (below) |
| `lastFetchTime`, `lastFetchStatus` | the client's `info` | the epoch (UTC) before a successful fetch |
| `setCustomSignals` | the client's | a signal over a limit throws `invalid-argument` |
| `onConfigUpdated` | the client's realtime stream | works on every platform, desktop included |

The reads in the `getValue` and `lastFetchTime` rows never throw. While the clients cannot be created (the app's
options lack the project id, API key or app id, for example), they answer from the defaults (else empty static
values), the epoch and `noFetchYet`, and the cause is logged once with `debugPrint`; the other calls throw it.

The clients belong to the FlutterFire app and the options it had when they were created. Deleting the app closes
them, on every platform; trying to delete the default app off the web, which throws, leaves them open. While a
delete runs (or after it failed), no new clients are created: the reads answer from the defaults, and the other calls
throw `internal` (an instance first created during the delete closes the clients it created then at its next use). If an app of the same name is created again with the same options, the next use creates new
clients. With other options, the next use closes the old clients and creates new ones only when no
`firebase_app_dart` app of that name with the old options is left: the Linux core deletes it with the FlutterFire app,
but the native and web cores keep it, and this package does not delete it, because the other platform packages of
this repository (Firestore, Storage, Realtime Database) may share it. There an app re-created under the same name
with other options is a restriction: it is not supported until the app restarts: the reads answer from the defaults, and the other calls
throw `internal` with a message that says so. Use another app name for the new options.

## How it differs from the native plugins

- **Realtime updates work on Linux, Windows and macOS**, through the same stream as on the web.
- **Value conversions** are FlutterFire's: `getBool` is true only for `true` (any case) and `1`; `getInt` and
  `getDouble` give 0 for text that does not parse. The pure-Dart client used directly follows Android's rules
  instead (`yes`, `on`, ... are true).
- **Throttling fails fast**, as on Android: inside a backoff window `fetch` throws `throttled` without sending.
- **The store** is a file store under the application support directory, owned by one process (above).

## Errors

Errors are `FirebaseException`s of `firebase_core` with the plugin `firebase_remote_config`.

On Linux, Windows and macOS the codes are those the platform interface documents:

| Code | When |
| --- | --- |
| `network-error` | the server could not be reached, or the fetch timed out (also while getting the installation) |
| `throttled` | inside a backoff window, after a 429, or after a status that starts one (502, 503, 504) |
| `forbidden` | the server answered 403 (for example, the Remote Config API is disabled for the project) |
| `remote-config-server-error` | the server answered another error status |
| `invalid-argument` | `setCustomSignals` with a signal over a limit; `setConfigSettings` with a negative duration |
| `internal` | anything else: a store failure, an Installations failure, a malformed response, a realtime failure, an app that was deleted or re-created with other options (above). A failure of Installations carries the Installations message (for example the store's); the others carry the client's or this package's |

`onConfigUpdated` reports an error through the stream it returns; it does not throw when it is called.

On the web the client's codes pass through, as the official plugin passes the JS SDK's: `fetch-client-network`,
`fetch-timeout`, `fetch-throttle`, `fetch-client-parse`, `fetch-status`, `stream-error`, `realtime-unavailable`,
`update-message-invalid`, `update-not-fetched` and `invalid-app-config`, plus three of this SDK's own:
`installations-error` (getting the installation id or token failed), `storage-error` (the store failed) and
`remote-config-closed` (the app was deleted). The errors of this package itself (a deleted or re-created app, an
unexpected failure) are `internal` there too.
