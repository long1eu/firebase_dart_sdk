## 0.1.3

- `FlutterFireLimitedUseAppCheckProvider`: the bridge with `getLimitedUseToken`. It extends
  `FlutterFireAppCheckProvider`, implements `LimitedUseAppCheckTokenProvider` of `firebase_app_dart` and takes
  `FirebaseAppCheck.instance.getLimitedUseToken` as a third argument. A null or empty answer, or a throw, is
  reported with the placeholder token. `FlutterFireAppCheckProvider` itself gives no limited-use token, and
  nothing sends the session token in its place.
- Changed: when the plugin throws or returns no token, `getToken` reports the failure with the placeholder token,
  so the request carries the placeholder in `X-Firebase-AppCheck` where it carried no header before. A backend
  that enforces App Check rejects both; one that does not accepts both.
- Changed: a null (or empty) token on `onTokenChange` is no longer forwarded. The stream carries new tokens only.
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
