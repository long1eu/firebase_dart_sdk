# App Check

Firestore sends an App Check token in the `x-firebase-appcheck` metadata header of every RPC when the app has an
App Check source. Without one nothing changes: no header, no extra requests. This package contains only the plumbing;
it does not attest a device. Reference: Android SDK `ff414cb2c` (AppCheck integration), `3e5cd47` (rename only).

## Usage

Implement `InternalAppCheckTokenProvider` (from `firebase_app_dart/lib/src/internal`, re-exported by `firebase_app_dart`):

```dart
class MyAppCheck implements InternalAppCheckTokenProvider {
  @override
  Future<AppCheckTokenResult> getToken({required bool forceRefresh}) async { ... }

  @override
  Stream<AppCheckTokenResult> get onTokenChanged => ...;
}

app.appCheckProvider = MyAppCheck();            // or PlatformDependencies.appCheckProvider
final firestore = Firestore.getInstance(app);
```

Set it before the first `Firestore.getInstance`; Firestore reads it when the instance is created.
`Firestore.newInstance(..., appCheckProvider:)` and `FirestoreMultiDbComponent(..., appCheckProvider:)` accept one
explicitly and take precedence over the app's.

## Behaviour (same as upstream)

* `AppCheckTokenResult` carries a token and an optional error. A result with an error but a non-empty (placeholder)
  token is logged and the token is still sent; the backend rejects it. An empty token sends no header.
* If `getToken` itself throws, the RPC fails with `UNAUTHENTICATED`.
* An app without a provider: App Check is skipped (`FirebaseApiNotAvailableError` is swallowed and logged).
* Auth and App Check tokens are fetched concurrently; an auth error wins.
* When the backend answers `UNAUTHENTICATED`, `ChannelOptionsProvider.invalidateToken()` invalidates both providers:
  the next request calls `getToken(forceRefresh: true)` once.
* `onTokenChanged` is subscribed for the life of the client (cancelled on `shutdown`) and exposed as
  `AppCheckTokenProvider.onChange`. Streams are not restarted on a change: upstream tried that (26d0992) and reverted
  it (62d868a), so a new token is used by the next RPC or stream restart.

## Where it lives

* `firebase_app_dart/lib/src/internal/app_check.dart`: the interface and result.
* `firebase_app_dart`: `FirebaseApp.appCheckProvider`, `PlatformDependencies.appCheckProvider`.
* `auth/app_check_token_provider.dart`: wrapper with `forceRefresh` bookkeeping and the change stream.
* `remote/firestore_call_credentials.dart` sets the header; `remote/datastore/channel_options_provider.dart` passes the
  provider in and forwards `invalidateToken()`; `Datastore`, `core/FirestoreClient`, `Firestore` thread it through.

## Tests

`test/unit/firebase/firestore/auth/app_check_token_provider_test.dart` (fake provider): header present/absent,
empty token, error result, throwing provider, refresh after invalidate, change stream and close. The emulator ignores
the header, so enforcement can only be verified against a real project.
