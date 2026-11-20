# firebase_auth_dart_platform

An unofficial implementation of the platform interface of the official
[`firebase_auth`](https://pub.dev/packages/firebase_auth) Flutter plugin, on top of `FirebaseUserAuth` of
[`firebase_auth_providers_dart`](https://pub.dev/packages/firebase_auth_providers_dart), a pure-Dart client of the
Firebase Auth REST API. Your app keeps the official API (`FirebaseAuth.instance.signInWithEmailAndPassword(...)`,
`authStateChanges()`, `User.updateProfile`, ...), and the Dart client does the work underneath, without the native
Firebase SDKs.

You need it for a Flutter app on Linux desktop, where `firebase_auth` and `firebase_core` have no implementation of
their own: add it to `pubspec.yaml` and it registers itself. On other platforms it is an opt-in. It is not affiliated
with or endorsed by Google or Firebase.

> **Status: 0.1.0, unreleased.** Unit-tested with `flutter test` through the classes of `firebase_auth` 7.1.0
> (`firebase_auth_platform_interface` 9.2.0), against a fake backend. The client underneath is tested against the
> Auth emulator in its own package. This package has not yet run in a Linux desktop build, against the emulator, or
> against a production project.

## How to enable it

```yaml
dependencies:
  firebase_auth: ^7.0.1
  firebase_core: ^5.1.0
  firebase_auth_dart_platform: ^0.1.0
```

**On Linux** nothing else is needed: Flutter calls `FirebaseAuthDart.registerWith()` before `main()`. Pass the
options to `Firebase.initializeApp` (there is no native configuration file to read them from):

```dart
await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: password);
```

**On any other platform**, call `FirebaseAuthDart.use()` at the start of `main()`, before the first use of
`Firebase` or `FirebaseAuth`. There `firebase_core` keeps its native implementation, and the native Auth SDK is still
built into the app, unused.

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FirebaseAuthDart.use();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp());
}
```

### Options of `use`

| Argument | Default | What it does |
| --- | --- | --- |
| `storageFor` | a file per program (see below); memory on Android, iOS and the web | Returns the `AuthStorage` that keeps the session of a FlutterFire app, for example a `FileAuthStorage` at a path of your choice, or one on top of a secure storage plugin. |
| `httpClient` | one per app | The `http.Client` of the requests (tests, proxies). |
| `useDartCore` | Linux only, when `firebase_core` has no other implementation | Installs a small pure-Dart `firebase_core`. Pass `true` to force it (tests), `false` to never do it. |

`use()` throws a `StateError` once the `FirebaseAuth` of an app has been used, because the configuration is read
then.

### `firebase_core` on Linux

`firebase_core` has no Linux implementation either. This package installs a small one (apps in memory,
`initializeApp` needs `options`) only while `firebase_core` still has its default implementation. The Firestore
platform package of this repository (`cloud_firestore_dart_platform`) does the same with its own, so the two can be
in one app: whichever registers first provides `firebase_core`, and the other keeps it.

### The session

The signed-in user survives a restart: the session (its refresh token) is stored, and the restore starts as soon as
the app's `FirebaseAuth` instance is created (`firebase_auth` creates it at the first call on it).
`authStateChanges()` and `idTokenChanges()` emit the restored user (or null) once the restore has finished;
`currentUser` is null until then. Code that needs the restored user at start awaits `authStateChanges().first`:

```dart
final User? user = await FirebaseAuth.instance.authStateChanges().first;
```

By default the sessions are in one file per program, written owner-only (mode 0600) by `FileAuthStorage`:

| Platform | File |
| --- | --- |
| Linux | `$XDG_DATA_HOME/<executable>/firebase_auth_dart_platform/sessions.json` (`~/.local/share/...` when unset) |
| macOS | `~/Library/Application Support/<executable>/firebase_auth_dart_platform/sessions.json` |
| Windows | `%APPDATA%\<executable>\firebase_auth_dart_platform\sessions.json` |

`<executable>` is the file name of the program, which for a Flutter desktop app is the name of the project.
`defaultSessionFile()` returns the path. The file holds a refresh token, which does not expire: anyone who can read
it can act as the user. Pass `storageFor` to keep it in the system keyring instead. Separate processes of the same
program share the file: the last one to write it wins.

If the file cannot be written (a read-only or full disk), the sign-in still succeeds: the session stays in memory until
the program ends, and the failure is printed once.

Under `flutter test`, the registration on Linux uses neither the file nor this package's `firebase_core`, so tests
do not share a file and `setupFirebaseCoreMocks` keeps working; call `use()` to choose otherwise.

`setPersistence(Persistence.NONE)` (or `SESSION`) moves the session to memory, so the user is signed out at the next
start; `Persistence.LOCAL` moves it back.

## Firestore

The Firestore platform package sends requests as the signed-in user through `tokenProviderFor`. Two ways, on any
platform where this package implements `firebase_auth`:

```dart
import 'package:cloud_firestore_dart_flutterfire/cloud_firestore_dart_flutterfire.dart';
import 'package:cloud_firestore_dart_platform/cloud_firestore_dart_platform.dart';
import 'package:firebase_auth/firebase_auth.dart';

// The user of the official API, as on every other platform:
CloudFirestoreDart.use(
  tokenProviderFor: (FirebaseApp app) =>
      FlutterFireAuthTokenProvider(FirebaseAuth.instanceFor(app: app)),
);

// Or the Dart client behind it, which switches Firestore to the new user before the sign-in call returns:
CloudFirestoreDart.use(
  tokenProviderFor: (FirebaseApp app) => FirebaseAuthDart.userAuthFor(app),
);
```

`FlutterFireAuthTokenProvider` works with this package as it is (`test/firestore_wiring_test.dart`). It learns about
a new user from `idTokenChanges()`, a moment after `signInWith...()` completes; when the next write must belong to
the new user, `await provider.waitForCurrentUser()` first. `userAuthFor` has no such gap.

## What is implemented

| Area | Status |
| --- | --- |
| `signInAnonymously`, `signInWithEmailAndPassword`, `createUserWithEmailAndPassword`, `signInWithCustomToken`, `signOut` | implemented, tested |
| Email link: `sendSignInLinkToEmail`, `isSignInWithEmailLink`, `signInWithEmailLink` | implemented, tested in part |
| `signInWithCredential` with email, email link, Google, Apple, Facebook, GitHub, Twitter, Microsoft, Yahoo and `OAuthProvider` (OIDC) credentials: the app brings the provider's token | implemented, tested for Google |
| `User`: `linkWithCredential`, `reauthenticateWithCredential`, `unlink`, `reload`, `delete`, `getIdToken`, `getIdTokenResult`, `updateEmail`, `updatePassword`, `updateProfile` / `updateDisplayName` / `updatePhotoURL`, `sendEmailVerification`, `verifyBeforeUpdateEmail`; `providerData`, `metadata`, `tenantId` | implemented; `updateProfile`, `getIdTokenResult`, `reload` tested |
| Action codes: `sendPasswordResetEmail`, `confirmPasswordReset`, `verifyPasswordResetCode`, `checkActionCode`, `applyActionCode`; `fetchSignInMethodsForEmail` | implemented, `checkActionCode` tested |
| `authStateChanges()`, `idTokenChanges()`, `userChanges()` | implemented, tested |
| `tenantId`, `languageCode`, `setLanguageCode`, `useAuthEmulator`, `setPersistence` | implemented, tested |
| Errors: `FirebaseAuthException` with the client's code (the codes of the JS SDK), `email`, `credential`, `phoneNumber`, `tenantId`; a recoverable credential goes back to `signInWithCredential` unchanged; other errors of the client (`ArgumentError` as `argument-error`, `StateError` and file errors as `internal-error`) are `FirebaseAuthException`s too | implemented, tested |
| `multi-factor-auth-required`: a `FirebaseAuthMultiFactorException` whose `resolver.hints` lists the factors | implemented, tested; the resolver cannot finish the sign-in (below) |

These throw a `FirebaseAuthException` with the code `unimplemented` and a message that says why:

- **Provider flows**: `signInWithProvider`, `User.linkWithProvider`, `User.reauthenticateWithProvider`. To sign in
  with a provider today, use `FirebaseAuthDart.userAuthFor(app).signInWithOAuthLoopback` (the system browser and a
  loopback redirect), or get the provider's token yourself and use `signInWithCredential`.
- **Browser flows**: `signInWithPopup`, `signInWithRedirect`, `getRedirectResult`, `User.linkWithPopup`,
  `User.linkWithRedirect`, `User.reauthenticateWithPopup`, `User.reauthenticateWithRedirect`.
- **Phone**: `verifyPhoneNumber`, `signInWithPhoneNumber`, `User.linkWithPhoneNumber`, `User.updatePhoneNumber`,
  `initializeRecaptchaConfig`, a `PhoneAuthCredential`, `PhoneMultiFactorGenerator.getAssertion`. Phone sign-in needs
  reCAPTCHA or the app verification of Android and iOS.
- **Multi-factor**: `User.multiFactor` (`getSession`, `enroll`, `unenroll`, `getEnrolledFactors`),
  `MultiFactorResolver.resolveSignIn`, `TotpMultiFactorGenerator`.
- **Play Games and Game Center credentials**, which need their native SDKs.

## How it differs from the official plugin

- **`validatePassword`**: `firebase_auth` does not ask the platform; it fetches the password policy itself from the
  production endpoint, without the tenant and without the emulator. `FirebaseAuthDart.validatePassword(app, password)`
  returns the same `PasswordValidationStatus` but asks the client, which sends the tenant, follows `useAuthEmulator`
  and caches the policy.
- **Errors keep what the server said**: an error from the backend is a `DartFirebaseAuthException`, a
  `FirebaseAuthException` with `serverCode` (such as `EMAIL_EXISTS`) and `httpStatus` added, for logs. Branch on
  `code` as usual.
- **`useAuthEmulator`**: call it before the first request, as the documentation of `firebase_auth` says. A session
  restored from the real service stays signed in until its first token refresh fails against the emulator.
- **`User.refreshToken`** is null: the client keeps the refresh token to itself.
- **`userChanges()`** emits as on the native platforms: once per sign-in or sign-out, once per token refresh and once
  per change of the user's data.
- **Apple's `appleFullPersonName`** reaches the client, which, like the JS SDK, does not send it to the backend: set
  the name with `updateDisplayName` after the first sign-in.
- **`setSettings`** is accepted and ignored: its settings are for phone sign-in and the iOS keychain.
- **App Check** tokens are not sent: the client supports them, but this package has no `firebase_app_check`
  implementation to take them from.
- **Error messages** are those of the client (the JS SDK's); the codes are the same as on the web. `no-current-user`
  (an operation of a `User` that is no longer signed in) and `unimplemented` are this package's.

## Platforms

| Platform | Selected by | Notes |
| --- | --- | --- |
| Linux | automatic (`dartPluginClass`) | `firebase_core` is installed too, unless another package did it first |
| Windows, macOS | `FirebaseAuthDart.use()` | `firebase_core` stays native; the session file is in the user's application data |
| Android, iOS | `FirebaseAuthDart.use()` | the session is in memory unless you pass `storageFor` |
| Web | not supported | use the official plugin |
