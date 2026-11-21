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
| `oauthProviders` | none | The `OAuthLoopbackProvider`s of `signInWithProvider`, `User.linkWithProvider` and `User.reauthenticateWithProvider`, one per Firebase provider id (see [Provider sign-in](#provider-sign-in)). |
| `oauthProvidersFor` | none | The providers of one FlutterFire app, for apps with several Firebase projects that each have their own OAuth client; called once per app. They are added to `oauthProviders`, and one with the same id as a provider of `oauthProviders` replaces it for that app. |
| `presentUrl` | the system browser on macOS, Linux and Windows | Opens the authorization URL of a provider sign-in, for example `url_launcher`'s `launchUrl`. Needed on Android and iOS: without it the provider calls throw `unimplemented`. |

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
  presentUrl: (Uri url) => launchUrl(url),
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
| `multi-factor-auth-required`: a `FirebaseAuthMultiFactorException` whose `resolver.hints` lists the factors and whose `resolver.resolveSignIn` finishes the sign-in or reauthentication with `TotpMultiFactorGenerator.getAssertionForSignIn` | implemented, tested |
| Authenticator app (TOTP) second factors: `User.multiFactor` (`getSession`, `enroll`, `unenroll`, `getEnrolledFactors`), `TotpMultiFactorGenerator` (`generateSecret`, `getAssertionForEnrollment`, `getAssertionForSignIn`), `TotpSecret.generateQrCodeUrl`. SMS factors are listed and can be unenrolled | implemented, tested |
| `signInWithProvider`, `User.linkWithProvider`, `User.reauthenticateWithProvider` through the loopback OAuth flow, with the providers passed to `use` | implemented, tested with a simulated browser |

These throw a `FirebaseAuthException` with the code `unimplemented` and a message that says why:

- **Browser flows**: `signInWithPopup`, `signInWithRedirect`, `getRedirectResult`, `User.linkWithPopup`,
  `User.linkWithRedirect`, `User.reauthenticateWithPopup`, `User.reauthenticateWithRedirect`. Use
  `signInWithProvider` instead ([Provider sign-in](#provider-sign-in)).
- **Phone**: `verifyPhoneNumber`, `signInWithPhoneNumber`, `User.linkWithPhoneNumber`, `User.updatePhoneNumber`,
  `initializeRecaptchaConfig`, a `PhoneAuthCredential`, `PhoneMultiFactorGenerator.getAssertion`. Phone sign-in needs
  reCAPTCHA or the app verification of Android and iOS.
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
| `AUTH_HARNESS_STEPS` | always | `all`, or some of `google github reauthenticate totp revoke persistence` (commas or spaces); they always run in that order |
| `FIREBASE_API_KEY`, `FIREBASE_PROJECT_ID`, `FIREBASE_APP_ID` | always | from the project settings; the app id is that of any app of the project (`1:<number>:<platform>:<hash>`) |
| `GOOGLE_DESKTOP_CLIENT_ID`, `GOOGLE_DESKTOP_CLIENT_SECRET` | always: every step signs in with Google first | a "Desktop app" OAuth client |
| `GITHUB_CLIENT_ID`, `GITHUB_CLIENT_SECRET` | `github` | the GitHub OAuth App |
| `AUTH_HARNESS_GITHUB_ACCOUNT_EXISTS` | optional, `github` | `1` to start the GitHub step with the `account-exists-with-different-credential` recovery (below) |
| `AUTH_HARNESS_GOOGLE_LOGIN_HINT` | optional | The Google account's email address, passed as `login_hint` so that Google skips the account chooser on each of the browser trips. Never printed |

**Each step prints one line**, `PASS <step>`, `FAIL <step>: <error code>` or `SKIP <step>: <reason>`:

| Step | What a PASS means |
| --- | --- |
| `google` | `signInWithProvider(GoogleAuthProvider())` signed in to an existing account (the primary account of the run) |
| `github` | `User.linkWithProvider(GithubAuthProvider())` linked GitHub, a `signInWithProvider` with it signed in to the same account, and `User.unlink` removed it. With `AUTH_HARNESS_GITHUB_ACCOUNT_EXISTS=1`, first a GitHub sign-in failed with `account-exists-with-different-credential`, and the credential of the error was linked (`linkWithCredential`) after a Google sign-in, then unlinked. When GitHub is already linked, it is only signed in with, and stays linked |
| `reauthenticate` | `User.reauthenticateWithProvider(GoogleAuthProvider())` returned the same user |
| `totp` | a TOTP factor named `auth-harness` was enrolled, a Google sign-in after a sign-out raised the second-factor challenge, `MultiFactorResolver.resolveSignIn` finished it, and the factor was unenrolled. When the backend asks for a recent sign-in (`requires-recent-login`) at the enrolment or the unenrolment, the harness reauthenticates with Google once and retries; a retried enrolment shows a new secret, so add the new entry to the authenticator app |
| `revoke` | never a PASS: `revokeAccessToken` is for Sign in with Apple access tokens only, and the harness has no Apple sign-in. It calls it with a placeholder token and reports a SKIP that says whether the request reached the backend (and what it answered) |
| `persistence` | the session was in the session file, `setPersistence(Persistence.NONE)` removed it from the file while the user stayed signed in (and a token refresh worked), and `setPersistence(Persistence.LOCAL)` wrote it back |

**Codes for the TOTP step**: `flutter test` does not forward the terminal's input to the test, so the harness asks
for codes on a page served on 127.0.0.1 (at a random path), which it opens in the browser and prints. The first
page shows the `otpauth://` URI of the new factor (also printed in the terminal): add it to an authenticator app
(paste it, or type its `secret` as a setup key), then type the code into the page. The sign-in asks for the next
code: the first one is spent. The URI holds the secret of that factor only, which is unenrolled at the end; its
account name is the masked email address.

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
