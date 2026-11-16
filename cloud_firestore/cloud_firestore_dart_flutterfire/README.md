# cloud_firestore_dart_flutterfire

Unofficial bridge from the FlutterFire plugins to
[`cloud_firestore_dart`](https://pub.dev/packages/cloud_firestore_dart), the pure-Dart Firestore
client. For a Flutter app that initializes Firebase with `firebase_core` and signs its users in
with `firebase_auth`, and wants to use `cloud_firestore_dart` for Firestore: for example to run
the same Dart client and code as its backend, or to keep the native Firestore SDKs out of the
build. (It does not open a new platform: `firebase_auth` and the official `cloud_firestore`
plugin support the same platforms.) The bridge reuses the FlutterFire app options and the signed-in user, so you do not
copy the options by hand and the user does not sign in twice. It is not affiliated with or
supported by Google or Firebase.

> **Status: 0.1.0.** Covered by unit tests with fake plugins only. It has not been run in a
> Flutter app with the real plugins, on any platform, or against a real Firebase project.

## Install

```shell
flutter pub add cloud_firestore_dart cloud_firestore_dart_flutterfire firebase_core firebase_auth
```

Dart 3.8 and Flutter 3.32 or later. Tested with `firebase_core` 3.4 to 5.1 and `firebase_auth`
5.0 to 7.0.

## The common case

```dart
await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
final Firestore firestore = await FlutterFireBridge.firestore();
await FirebaseAuth.instance.signInAnonymously(); // or any sign-in of firebase_auth
```

`FlutterFireBridge.firestore()` creates a `firebase_app_dart` app with the name and the options
of `Firebase.app()`, makes a `FlutterFireAuthTokenProvider` for `FirebaseAuth.instance` its token
provider, and returns `Firestore.instanceFor` that app. Pass `app:`, `auth:`, `database:`,
`settings:`, `openDatabase:` (a SQLite cache, see the Flutter guide) and `appCheckProvider:` for
anything other than the defaults. Later calls return the same instance.

Firestore follows the plugin's user: a sign-in, a sign-out or a switch of users restarts its
streams with the new identity, and the pending writes of each user stay with that user, as with
`FirebaseUserAuth` of `firebase_auth_providers_dart`.

The plugin completes `signInWith...()` a moment before it reports the new user. When the next
write must belong to the new user, wait for the bridge first:

```dart
await FirebaseAuth.instance.signInAnonymously();
await FlutterFireBridge.waitForCurrentUser();
await firestore.doc('users/${FirebaseAuth.instance.currentUser!.uid}').set(data);
```

## Wiring by hand

```dart
import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart_flutterfire/cloud_firestore_dart_flutterfire.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart' as flutterfire;

final flutterfire.FirebaseApp source = flutterfire.Firebase.app();
final FlutterFireAuthTokenProvider auth =
    FlutterFireAuthTokenProvider(FirebaseAuth.instanceFor(app: source));
// The firebase_app_dart app, with the same name and options, and the provider.
final app = dartAppFor(source.name, source.options, authProvider: auth);
final Firestore firestore = Firestore.instanceFor(app: app);
```

- `firebaseOptionsFromFlutterFire(options)` maps the options alone: `apiKey`, `appId` (to
  `applicationId`), `projectId`, `messagingSenderId` (to `gcmSenderId`), `storageBucket`,
  `databaseURL` and `trackingId`. The others have no counterpart.
- `dartAppFor(name, options, ...)` creates the app on the first call and returns it afterwards;
  it throws a `StateError` when an app with that name exists with other options.
- `FlutterFireAuthTokenProvider.fromSource(currentUser: ..., idTokenChanges: ...)` takes any
  user source; the tests drive it with fakes.

`firebase_core` and `firebase_app_dart` both export `FirebaseApp` and `FirebaseOptions`; import
one of them with a prefix, as above.

## App Check

This package does not depend on `firebase_app_check`, so that apps without App Check do not get
the plugin and its native SDKs. If you use it, pass its two members:

```dart
final FirebaseAppCheck appCheck = FirebaseAppCheck.instance;
final Firestore firestore = await FlutterFireBridge.firestore(
  appCheckProvider: FlutterFireAppCheckProvider(
    getToken: appCheck.getToken,
    onTokenChange: appCheck.onTokenChange,
  ),
);
```

A failed App Check request does not fail the Firestore request: it goes out without the header
and a warning is logged, as with the App Check SDKs.

## What is not covered

- Only `firebase_core` and `firebase_auth` (and App Check through callbacks). Storage,
  Functions, Messaging and the other FlutterFire plugins are not bridged.
- The bridge does not sign anybody in: use `firebase_auth` for that.
- It does not follow a FlutterFire app that is deleted; terminate the Firestore instance and
  delete the `firebase_app_dart` app yourself.
- The `onTokenChanged` events of the provider carry a marker instead of the ID token for a
  signed-in user (`firebase_auth` reports the change without the token); call `getAccessToken`
  for the token. Firestore only reads the user id.
- It reads `InternalTokenProvider` and `InternalAppCheckTokenProvider` of `firebase_app_dart`,
  which can change in a minor release of that package; this package pins a compatible range.

## Platforms

The bridge is plain Dart on top of the plugins, so it runs where both `firebase_auth` and
`cloud_firestore_dart` run: Android, iOS, macOS and the web (where `cloud_firestore_dart` is
experimental), and Windows where `firebase_auth` supports it. On Linux there is no
`firebase_auth` plugin. None of these was tried with the bridge; see the
[Flutter guide](https://github.com/long1eu/firebase_dart_sdk/blob/main/docs/guides/flutter.md)
for what was tried with `cloud_firestore_dart` itself, and the
[FlutterFire bridge guide](https://github.com/long1eu/firebase_dart_sdk/blob/main/docs/guides/flutterfire_bridge.md)
for how user changes propagate.

## License

Apache-2.0; see `LICENSE` and `NOTICE`.
