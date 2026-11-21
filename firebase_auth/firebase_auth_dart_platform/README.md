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

> **Status: 0.1.1.** Unit-tested with `flutter test` through the classes of `firebase_auth` 7.1.0
> (`firebase_auth_platform_interface` 9.2.0), against a fake backend. The client underneath is tested against the
> Auth emulator in its own package. This package has not yet run in a Linux desktop build, against the emulator, or
> against a production project.

## How to enable it

```yaml
dependencies:
  firebase_auth: ^7.0.1
  firebase_core: ^5.1.0
  firebase_auth_dart_platform: ^0.1.1
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
| `storageFor` | the secure store of the platform, with the session file as fallback (see [The session](#the-session)); on the web `BestWebAuthStorage` (IndexedDB, else `localStorage`, else memory) | Returns the `AuthStorage` that keeps the session of a FlutterFire app, for example a `FileAuthStorage` at a path of your choice. It replaces the default entirely. |
| `httpClient` | one per app | The `http.Client` of the requests (tests, proxies). |
| `useDartCore` | Linux only, when `firebase_core` has no other implementation | Installs a small pure-Dart `firebase_core`. Pass `true` to force it (tests), `false` to never do it. |
| `oauthProviders` | none | The `OAuthLoopbackProvider`s of `signInWithProvider`, `User.linkWithProvider` and `User.reauthenticateWithProvider`, one per Firebase provider id (see [Provider sign-in](#provider-sign-in)). |
| `oauthProvidersFor` | none | The providers of one FlutterFire app, for apps with several Firebase projects that each have their own OAuth client; called once per app. They are added to `oauthProviders`, and one with the same id as a provider of `oauthProviders` replaces it for that app. |
| `presenter` | the presenter the `OAuthFlow` of `secure_flow` ranks best in the environment: the system browser on macOS, Linux and Windows, the URL on stderr over SSH or without a display | A `SecurePresenter` that runs the browser part of a provider sign-in: it shows the authorization URL and takes the redirect on 127.0.0.1. `CallbackPresenter((Uri url) => launchUrl(url))` with `url_launcher`, for example. Needed on Android and iOS: without it the provider calls throw `operation-not-supported-in-this-environment`. |
| `appVerification` | `AppVerification.recaptchaV2Loopback(presenter:)` with the `presenter` above: a reCAPTCHA v2 page on 127.0.0.1, once per phone request (in the system browser on a desktop without a `presenter`); no proof with the Auth emulator | The proof of the phone requests (`verifyPhoneNumber`, `signInWithPhoneNumber`, `User.linkWithPhoneNumber`, the SMS second factor): an `AppVerification` of `firebase_auth_providers_dart`, such as `AppVerification.recaptchaV2((request) => tokenFromYourWebView())` (see [Phone sign-in](#phone-sign-in)). `setSettings(appVerificationDisabledForTesting: true)` sends none. |

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

By default the sessions are in the secure store of the platform, through
[`firebase_auth_secure_storage_flutter`](https://pub.dev/packages/firebase_auth_secure_storage_flutter) (`SecureAuthStorage`, under its
default namespace, which is unique per program):

| Platform | Store | Needed |
| --- | --- | --- |
| Linux | libsecret (GNOME Keyring, KDE Wallet) | `libsecret-1-dev` to build, a running Secret Service to use it |
| macOS | data-protection keychain | the `keychain-access-groups` entitlement in a signed app |
| Windows | one DPAPI-encrypted map in `flutter_secure_storage.dat` in the application support directory | the C++ ATL libraries of Visual Studio Build Tools to build; an interactive logon (not SSH, not a service) to use it |
| Android | AES-GCM values, key wrapped by the Android Keystore | exclude the plugin's preferences from Auto Backup |
| iOS | Keychain, accessible while unlocked | nothing |
| Web | `BestWebAuthStorage` of `firebase_auth_providers_dart`: IndexedDB, else `localStorage`, else memory, chosen once (the secure store is not used; a session kept in `localStorage` under the same key moves to IndexedDB) | nothing |

The README of `firebase_auth_secure_storage_flutter` explains each set-up.

**Moving from the session file.** The session file (below) is where the fallback keeps the sessions, and where
builds of this package from before the secure store was the default kept them. At the first read of an app's
session, a session found in that file and not in the secure store moves there: it is written, read
back and compared, marked (see below), and only then deleted from the file (the file goes with its last session).
When the secure store already has a session for an app that is not marked, it wins, and the file is left alone; the
two are never merged.

**The marker.** `<session file>.secure`, next to the session file, records which apps' sessions live in the secure
store. It is a JSON object from the session key to `secure` or `sign-out`, written atomically and owner-only by
`FileAuthStorage`, and it never holds a token. A session is marked `secure` before it is first written to the store,
and before it is deleted from the file after a move. From then on:

- The session file is never read for that app: a copy left there (a crash between the move and the delete) is
  deleted at the next read, and never restored.
- In a run where the store cannot be used, for any reason, that app's session is kept in memory only: the app starts
  signed out, a new sign-in lasts until the program ends, and nothing is written to the file. A sign-in or sign-out in
  such a run marks the session `sign-out`. So does a write the store refuses later in a run that started with it.
- The first read of the next run that can use the store deletes a session marked `sign-out` from the store before
  anything is read, so the account of an earlier run never comes back after the user signed out or signed in again.

An app with no mark (the store never held its session) keeps the file as the fallback below. Android and iOS have no
session file and so no marker.

**When the secure store is unavailable.** Before the first read or write of the run, a probe decides for the whole
run: it writes an entry (`<namespace>/.probe`), reads it back and deletes it. A read alone cannot tell, because a macOS
build without the keychain entitlement reads a missing key as null and fails only at the first write. Operations that
start while the probe runs wait for it; the probe entry is deleted also when its read-back fails. When a step fails
because the store as a whole cannot be used (`SecureAuthStorageException.isUnavailable`: no plugin, no Secret Service
or D-Bus session bus, a locked keyring, a macOS build without the entitlement, Windows without an interactive logon
such as an SSH session or a service, where DPAPI refuses access; or no services binding yet), the sessions of the
run that are not marked are kept in the session file instead (memory on Android and iOS, which have no file), the
marked ones in memory, and one line per process says each. Nothing is written to the secure store for the rest of the run. Any other failure of the probe is
thrown by the operation that waited for it, and the next operation probes again. Once the probe has succeeded, a later
failure in the same run is not a reason to switch: it is thrown like the errors below. Other errors (a value that
cannot be read or decrypted, an iOS device that is locked for now) are thrown, never answered from the file: the restore
fails, the app starts signed out with the error in `authStateReady()`, and the stored session is not replaced by the
file's. A locked keyring and DPAPI refusing access count as unavailable only for apps without a mark: their session
was never in the store, so the file cannot hide or bring back a session there.

The session file of the fallback:

| Platform | File |
| --- | --- |
| Linux | `$XDG_DATA_HOME/<executable>/firebase_auth_dart_platform/sessions.json` (`~/.local/share/...` when unset) |
| macOS | `~/Library/Application Support/<executable>/firebase_auth_dart_platform/sessions.json` |
| Windows | `%APPDATA%\<executable>\firebase_auth_dart_platform\sessions.json` |

`<executable>` is the file name of the program, which for a Flutter desktop app is the name of the project.
`defaultSessionFile()` returns the path. It is written owner-only (mode 0600) by `FileAuthStorage`. It holds a refresh
token, which does not expire: anyone who can read it can act as the user. Separate processes of the same program share
it: the last one to write it wins.

**Keeping the file instead.** `storageFor` replaces the default, secure store and fallback included:

```dart
// FileAuthStorage and InMemoryAuthStorage come from firebase_auth_providers_dart.
final String? file = defaultSessionFile(); // null on Android and iOS
FirebaseAuthDart.use(
  storageFor: (FirebaseApp app) => file == null ? InMemoryAuthStorage() : FileAuthStorage(file),
);
```

**Failed writes.** Whatever the storage, a write that fails (the secure store refuses it, or the fallback file cannot
be written: a read-only or full disk) does not fail the sign-in: the session of that app stays in memory until the
program ends, and the failure is printed once. So there are three levels: the secure store; the session file, for the
whole run, only when the probe finds the store unavailable and the app has no mark; memory, for one app, after a
failed write to either, or for a marked app when the store cannot be used.
A failed read is never answered from memory or the file.

Under `flutter test`, the registration on Linux uses neither the default storage nor this package's
`firebase_core`, so tests do not share a file, need no secure storage plugin and print nothing, and
`setupFirebaseCoreMocks` keeps working; call `use()` to choose otherwise. A test that uses the default storage
without faking the plugin's channel gets the fallback and its line.

`setPersistence(Persistence.NONE)` (or `SESSION`) moves the session to memory, so the user is signed out at the next
start; `Persistence.LOCAL` moves it back. On the web, `LOCAL` (or `INDEXED_DB`) moves it to the storage of the app
(by default IndexedDB, else `localStorage`, else memory). Without `storageFor`, `SESSION` on the web moves it to the
tab's `sessionStorage`: a reload of the tab restores it from there, and a `setPersistence(SESSION)` at start keeps
it. With `storageFor`, `SESSION` stays memory, so the session is never written outside the storage you chose.
IndexedDB, `localStorage` and `sessionStorage` are readable by every script of the origin. The tabs follow each
other, as with the JS SDK: a sign-out or a sign-in in one tab reaches the others (at once with `localStorage`,
within about a second with IndexedDB), and a tab that has not heard of a sign-out yet does not write the session
back. A storage passed with `storageFor` takes part when it reports changes (`ObservableAuthStorage`, as the web
storages of `firebase_auth_providers_dart` do).

## Provider sign-in

`signInWithProvider`, `User.linkWithProvider` and `User.reauthenticateWithProvider` run the loopback OAuth flow of
`firebase_auth_providers_dart`: the authorization URL opens in the system browser, the provider redirects to a
one-shot server on 127.0.0.1, and the code is exchanged for the provider's tokens (PKCE, RFC 8252). Pass one
`OAuthLoopbackProvider` per provider to `use`; the call picks the one whose `providerId` is the id of the FlutterFire
provider (`google.com` for `GoogleAuthProvider`, `github.com` for `GithubAuthProvider`, `oidc.<name>` for
`OAuthProvider('oidc.<name>')`, ...):

```dart
FirebaseAuthDart.use(
  oauthProviders: <OAuthLoopbackProvider>[
    OAuthLoopbackProvider.google(
      clientId: '<the client id of a "Desktop app" OAuth client>',
      clientSecret: '<its client secret>', // not confidential for a desktop client, says Google
    ),
    OAuthLoopbackProvider.github(clientId: '<OAuth App client id>', clientSecret: '<its secret>'),
  ],
  // Optional on macOS, Linux and Windows (the system browser opens); needed on Android and iOS.
  presenter: CallbackPresenter((Uri url) => launchUrl(url)),
);

final UserCredential result = await FirebaseAuth.instance.signInWithProvider(
  GoogleAuthProvider()..addScope('https://www.googleapis.com/auth/drive.file'),
);
```

- The scopes (`addScope`) and custom parameters (`setCustomParameters`) of the FlutterFire provider are added to the
  request of the registered one; a custom parameter of both takes the FlutterFire provider's value.
- A provider id without an `OAuthLoopbackProvider` throws `unimplemented`, with a message that names the id.
- The errors are those of the client's flow: `timeout` (five minutes), `user-cancelled`, `invalid-credential`, ...
  `linkWithProvider` and `reauthenticateWithProvider` throw `no-current-user` before the browser opens when the user
  is no longer signed in.
- `OAuthLoopbackProvider` comes from `firebase_auth_providers_dart` and is exported by this package. Its README
  ("Browser sign-in on desktop and command line") says how to set up the OAuth clients of Google, GitHub and OpenID
  Connect providers.
- On the web the flow does not exist: the calls throw `unimplemented`.

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
| Errors: `FirebaseAuthException` with the client's code (the codes of the JS SDK), `email`, `credential`, `phoneNumber`, `tenantId`; a recoverable credential goes back to `signInWithCredential` unchanged; other errors of the client (`ArgumentError` as `argument-error`, `UnsupportedError` as `unimplemented`, `StateError` and file errors as `internal-error`) are `FirebaseAuthException`s too | implemented, tested |
| `multi-factor-auth-required`: a `FirebaseAuthMultiFactorException` whose `resolver.hints` lists the factors and whose `resolver.resolveSignIn` finishes the sign-in or reauthentication with `TotpMultiFactorGenerator.getAssertionForSignIn` or `PhoneMultiFactorGenerator.getAssertion` | implemented, tested |
| Authenticator app (TOTP) second factors: `User.multiFactor` (`getSession`, `enroll`, `unenroll`, `getEnrolledFactors`), `TotpMultiFactorGenerator` (`generateSecret`, `getAssertionForEnrollment`, `getAssertionForSignIn`), `TotpSecret.generateQrCodeUrl` | implemented, tested |
| Phone: `verifyPhoneNumber`, `signInWithPhoneNumber` and `User.linkWithPhoneNumber` (`ConfirmationResult.confirm`), `User.updatePhoneNumber`, `PhoneAuthProvider.credential` in `signInWithCredential`, `linkWithCredential` and `reauthenticateWithCredential` | implemented, unit-tested; run against a real project with a test phone number and no proof; not with a real SMS or against the emulator |
| SMS second factors: `verifyPhoneNumber` with the session of `getSession()` or of a `MultiFactorResolver`, `PhoneMultiFactorGenerator.getAssertion`, `MultiFactor.enroll` | implemented, unit-tested; run against a real project with a test phone number and no proof; not with a real SMS or against the emulator |
| `signInWithProvider`, `User.linkWithProvider`, `User.reauthenticateWithProvider` through the loopback OAuth flow, with the providers passed to `use` | implemented, tested with a simulated browser |

These throw a `FirebaseAuthException` with the code `unimplemented` and a message that says why:

- **Browser flows**: `signInWithPopup`, `signInWithRedirect`, `getRedirectResult`, `User.linkWithPopup`,
  `User.linkWithRedirect`, `User.reauthenticateWithPopup`, `User.reauthenticateWithRedirect`. Use
  `signInWithProvider` instead ([Provider sign-in](#provider-sign-in)).
- **`initializeRecaptchaConfig`** and **`RecaptchaVerifier.verify`**: the proof of a phone request comes from the
  `appVerification` of `use`; the reCAPTCHA Enterprise configuration of the project is not read.
- **A `PhoneAuthCredential` of `credentialFromToken`** (Android only) is an `argument-error`.
- **`TotpSecret.openInOtpApp`**: opening another app needs a URL launcher. Open the URL of `generateQrCodeUrl`
  with `url_launcher`, or show it as a QR code.
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
- **TOTP enrolment**: `MultiFactor.enroll` needs a `displayName` (`argument-error` without one; the backend
  refuses a TOTP factor without a name). `getSession()` sends nothing: the enrolment starts on the backend with
  `generateSecret`, and the session's `id` is the uid of the user. `generateQrCodeUrl()` defaults the account name
  to the user's email address and the issuer to the name of the Firebase app, as the JS SDK does.
- **`setSettings`**: `appVerificationDisabledForTesting` sends the phone requests without a proof; the other
  settings (Android test numbers and reCAPTCHA flow, the iOS keychain) are ignored.
- **Phone verification** has no instant verification and no automatic reading of the SMS (both are Android
  features): `verifyPhoneNumber` calls `codeSent` with the verification id (and no resend token: call it again to
  resend), `verificationFailed` with every error, `codeAutoRetrievalTimeout` after `timeout`, and never
  `verificationCompleted`. The user types the code in.
- **App Check** tokens are not sent: the client supports them, but this package has no `firebase_app_check`
  implementation to take them from.
- **Error messages** are those of the client (the JS SDK's); the codes are the same as on the web. `no-current-user`
  (an operation of a `User` that is no longer signed in) and `unimplemented` are this package's.

## Phone sign-in

`verifyPhoneNumber` and `signInWithPhoneNumber` work as on the other platforms, minus instant verification and
SMS auto-retrieval. Each request that sends an SMS carries the `appVerification` of `use`: by default the
reCAPTCHA v2 page of the client, shown by the `presenter` of `use` (the system browser on a desktop without one),
nothing with the Auth emulator. On Android or iOS, pass a `presenter` that opens the page (for example
`CallbackPresenter((Uri url) => launchUrl(url))`), or, in an app that renders reCAPTCHA itself, a token source:

```dart
FirebaseAuthDart.use(
  appVerification: AppVerification.recaptchaV2(
    (RecaptchaV2Request request) => tokenFromYourWebView(request.siteKey),
  ),
);

final ConfirmationResult confirmation = await FirebaseAuth.instance.signInWithPhoneNumber('+15555550100');
await confirmation.confirm(codeFromYourTextField);
```

The SMS second factor goes through `verifyPhoneNumber` with `multiFactorSession` (from
`User.multiFactor.getSession()` to enrol, from `MultiFactorResolver.session` with `multiFactorInfo` to sign in),
then `PhoneMultiFactorGenerator.getAssertion(PhoneAuthProvider.credential(verificationId: ..., smsCode: ...))`.
No error holds the phone number, the verification id, the code or the reCAPTCHA token.

## Platforms

| Platform | Selected by | Notes |
| --- | --- | --- |
| Linux | automatic (`dartPluginClass`) | `firebase_core` is installed too, unless another package did it first; the session is in libsecret (`libsecret-1-dev` to build) |
| Windows, macOS | `FirebaseAuthDart.use()` | `firebase_core` stays native; the session is in DPAPI (Windows) or the keychain (macOS; the session file when the build lacks the keychain entitlement) |
| Android, iOS | `FirebaseAuthDart.use()` | the session is in the Keystore or the Keychain |
| Web | not supported | use the official plugin |

## Real-project harness

`test/real_project/real_project.dart` drives the official `firebase_auth` API on top of this package against a
real Firebase project, with you at the browser. It is for the maintainers; it is skipped unless
`AUTH_HARNESS_STEPS` is set, so a plain `flutter test` does not run it. On macOS (Linux should work too, untested):

```shell
cd firebase_auth/firebase_auth_dart_platform
AUTH_HARNESS_STEPS=all flutter test test/real_project/real_project.dart -r expanded
```

It runs under `flutter test` because `package:flutter`, which `firebase_core` and `firebase_auth` import, needs the
engine (`dart run` cannot load it), and a test needs no app, runner or entitlements. It uses a plain `test()`
without a test binding, so its `HttpClient` is the real one, and `FirebaseAuthDart.use(useDartCore: true)`
provides `firebase_core`. The session is kept by a `FileAuthStorage` in a new temporary directory, deleted at the
end.

**The configuration comes only from the environment** (for example `op run --env-file=... --` in front of the
command):

| Variable | Needed for | What |
| --- | --- | --- |
| `AUTH_HARNESS_STEPS` | always | `all`, or some of `google github reauthenticate totp phone sms revoke persistence` (commas or spaces); they always run in that order |
| `FIREBASE_API_KEY`, `FIREBASE_PROJECT_ID`, `FIREBASE_APP_ID` | always | from the project settings; the app id is that of any app of the project (`1:<number>:<platform>:<hash>`) |
| `GOOGLE_DESKTOP_CLIENT_ID`, `GOOGLE_DESKTOP_CLIENT_SECRET` | always: every step signs in with Google first | a "Desktop app" OAuth client |
| `GITHUB_CLIENT_ID`, `GITHUB_CLIENT_SECRET` | `github` | the GitHub OAuth App |
| `AUTH_HARNESS_GITHUB_ACCOUNT_EXISTS` | optional, `github` | `1` to start the GitHub step with the `account-exists-with-different-credential` recovery (below) |
| `AUTH_HARNESS_GOOGLE_LOGIN_HINT` | optional | The Google account's email address, passed as `login_hint` so that Google skips the account chooser on each of the browser trips. Never printed |
| `AUTH_HARNESS_PHONE_NUMBER`, `AUTH_HARNESS_PHONE_CODE` | `phone`, `sms` (skipped without them) | A test phone number of the project in E.164 form and its code (Authentication, Sign-in method, Phone, "Phone numbers for testing"). No SMS is sent. Never printed in full |
| `AUTH_HARNESS_LOG_ANSWERS` | optional | `1` to print, for every Identity Toolkit call, the method, the HTTP status and the names of the fields of the answer (for example `accounts:signInWithIdp 200: mfaInfo[…], mfaPendingCredential`). Values are never printed, except the backend's error code. For finding out why a step failed. |

**Each step prints one line**, `PASS <step>`, `FAIL <step>: <error code>` or `SKIP <step>: <reason>`:

| Step | What a PASS means |
| --- | --- |
| `google` | `signInWithProvider(GoogleAuthProvider())` signed in to an existing account (the primary account of the run) |
| `github` | `User.linkWithProvider(GithubAuthProvider())` linked GitHub, a `signInWithProvider` with it signed in to the same account, and `User.unlink` removed it. With `AUTH_HARNESS_GITHUB_ACCOUNT_EXISTS=1`, first a GitHub sign-in failed with `account-exists-with-different-credential`, and the credential of the error was linked (`linkWithCredential`) after a Google sign-in, then unlinked. When GitHub is already linked, it is only signed in with, and stays linked |
| `reauthenticate` | `User.reauthenticateWithProvider(GoogleAuthProvider())` returned the same user |
| `totp` | a TOTP factor named `auth-harness` was enrolled, a Google sign-in after a sign-out raised the second-factor challenge, `MultiFactorResolver.resolveSignIn` finished it, and the factor was unenrolled. When the backend asks for a recent sign-in (`requires-recent-login`) at the enrolment or the unenrolment, the harness reauthenticates with Google once and retries; a retried enrolment shows a new secret, so add the new entry to the authenticator app |
| `phone` | `User.linkWithPhoneNumber` linked the test number, `signInWithPhoneNumber` signed in to the same account after a sign-out, `reauthenticateWithCredential` with a credential of `verifyPhoneNumber` returned the same user, and `User.unlink` removed the number. Skipped when the account already has a phone number |
| `sms` | the test number was enrolled as an SMS factor named `auth-harness-sms` (`verifyPhoneNumber` with the session of `getSession()`), a Google sign-in after a sign-out raised the second-factor challenge, `verifyPhoneNumber` with the resolver's session and `resolveSignIn` finished it, and the factor was unenrolled |
| `revoke` | never a PASS: `revokeAccessToken` is for Sign in with Apple access tokens only, and the harness has no Apple sign-in. It calls it with a placeholder token and reports a SKIP that says whether the request reached the backend (and what it answered) |
| `persistence` | the session was in the session file, `setPersistence(Persistence.NONE)` removed it from the file while the user stayed signed in (and a token refresh worked), and `setPersistence(Persistence.LOCAL)` wrote it back |

**Codes for the TOTP step**: `flutter test` does not forward the terminal's input to the test, so the harness asks
for codes on a page served on 127.0.0.1 (at a random path), which it opens in the browser and prints. The first
page shows the `otpauth://` URI of the new factor (also printed in the terminal): add it to an authenticator app
(paste it, or type its `secret` as a setup key), then type the code into the page. The sign-in asks for the next
code: the first one is spent. The URI holds the secret of that factor only, which is unenrolled at the end; its
account name is the masked email address.

**The proof of the phone steps**: the first phone request goes without a proof
(`appVerificationDisabledForTesting`); when the project refuses it (`missing-app-credential`,
`invalid-app-credential`, `captcha-check-failed`), the harness sends a placeholder reCAPTCHA token (what the JS
SDK sends for test numbers), and then the reCAPTCHA page in the browser. The PASS line names the proof the project
took, which answers whether a test number needs one.

**The account is left as it was**: every link and enrolment is undone in the step, or at the end if the step
failed, and the last lines say `CLEANUP OK` or `CLEANUP FAILED` with what to fix by hand. The harness never
deletes an account. A sign-in that created a new account (signing in with a Google account that has none yet, or a
GitHub sign-in with `AUTH_HARNESS_GITHUB_ACCOUNT_EXISTS=1` in a project that allows several accounts per email
address) fails the step and is listed for deletion in the console. The output never has a token or a full email
address in it.

Set up in the consoles first:

- **Google**: a "Desktop app" OAuth client (Google Cloud console, APIs & Services, Credentials), in the project
  of the Firebase project or listed in the Google provider's "Safelist client IDs from external projects"; the
  Google provider enabled in Firebase Authentication; a Google account that already has an account in the project.
- **GitHub**: a GitHub OAuth App whose authorization callback URL is exactly `http://127.0.0.1` (no `/` at the
  end). Its client id and secret must be the ones set for the GitHub provider in Firebase Authentication: Firebase
  checks the GitHub token against that app (`invalid-credential` otherwise). The GitHub account must not be linked
  to another account of the project (`credential-already-in-use`). The `account-exists-with-different-credential`
  part also needs "one account per email address" (the default) and a GitHub account with the email address of the
  Google account.
- **TOTP**: Firebase Authentication with Identity Platform, with TOTP multi-factor authentication enabled (through
  the Admin SDK or the REST API: there is no console switch for it), and an account with a verified email address
  (a Google account has one).
- **Phone and SMS**: the Phone provider enabled, a test phone number with its code, and for `sms` SMS
  multi-factor authentication enabled on Identity Platform. The test number must not belong to another account
  (`credential-already-in-use`).
