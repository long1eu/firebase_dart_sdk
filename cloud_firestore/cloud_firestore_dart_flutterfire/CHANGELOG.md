## 0.1.3

- Behaviour change: when the plugin throws or returns no token, `FlutterFireAppCheckProvider.getToken` returns
  `AppCheckTokenResult.failure(...)`, the placeholder token with the error, where it returned an empty token.
  Firestore and the other clients then send the request with the placeholder in the App Check header, where they
  sent no header. A backend that enforces App Check rejects both; one that does not accepts both.
- Behaviour change: `FlutterFireAppCheckProvider.onTokenChanged` drops an event of the plugin without a token
  (null or empty), where it emitted an empty token. The stream carries new tokens only.
- `FlutterFireAppCheckProvider` takes an optional `getLimitedUseToken` (pass
  `FirebaseAppCheck.instance.getLimitedUseToken`) and overrides `AppCheckTokenProvider.getLimitedUseToken()` with
  it. A null or empty answer, or a throw, is an `AppCheckTokenResult.failure(...)`. Without the
  argument the provider gives no limited-use token (an empty token with an `UnsupportedError`); it never returns
  the session token instead. Firestore does not ask for limited-use tokens; the method is for packages that do.
- Requires `firebase_app_dart` 0.2.3.

## 0.1.2

No code change. A shorter package description (it was 190 characters, which pub.dev scores as too long).

## 0.1.1

No code change. The constraint on `cloud_firestore_dart` is `>=0.2.0 <0.4.0` instead of `^0.2.0`, so that the
package can be used with `cloud_firestore_dart` 0.3.0. It compiles against 0.2.0 and 0.3.0.

## 0.1.0

First version, built against the 0.2 API of `cloud_firestore_dart` and `firebase_app_dart`.

- `FlutterFireBridge.firestore()`: a `cloud_firestore_dart` `FirebaseFirestore` instance for a FlutterFire app
  (default `Firebase.app()`) and the user of its `FirebaseAuth`, in one call.
  `FlutterFireBridge.app()` returns the `firebase_app_dart` app alone, and
  `FlutterFireBridge.waitForCurrentUser()` waits until Firestore follows the plugin's current
  user after a sign-in or a sign-out.
- `firebaseOptionsFromFlutterFire` and `dartAppFor`: the `firebase_app_dart` options (every field
  but `recaptchaSiteKey`) and app for the options and the name of a FlutterFire app.
- `FlutterFireAuthTokenProvider`: an `AuthTokenProvider` of `firebase_app_dart`, backed by
  `firebase_auth`. It follows `idTokenChanges()` (sign-in, sign-out, user switch, token refresh),
  forwards `forceRefresh` to `User.getIdToken`, throws `FirebaseNoSignedInUserException` when
  nobody is signed in, and drops a token fetched for a user that was replaced meanwhile.
- `FlutterFireAppCheckProvider`: an `AppCheckTokenProvider` of `firebase_app_dart`, from the
  `getToken` and `onTokenChange` of `firebase_app_check` (passed in; this package does not
  depend on `firebase_app_check`).
- Requires Dart 3.8 and Flutter 3.32 or later; `firebase_core` 3 to 5 and `firebase_auth` 5 to 7.

Verified with unit tests and fakes of the plugins only. Nothing was run in a Flutter app with
the real plugins or against a real Firebase project.
