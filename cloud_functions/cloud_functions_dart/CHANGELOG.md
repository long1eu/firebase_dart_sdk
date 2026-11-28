## 0.1.0

- `FirebaseFunctions` for a `FirebaseApp`: `httpsCallable(name)` and `httpsCallableFromUrl(url)`, with a region
  (default `us-central1`), a custom domain, an emulator host (`emulatorHostFromEnvironment` reads
  `FIREBASE_FUNCTIONS_EMULATOR_HOST`), a default timeout of 70 seconds, an injectable HTTP client, a warning
  sink and `close()`. Names, regions, custom domains and URLs are validated; `http` is accepted only for
  loopback hosts and the configured emulator.
- `HttpsCallable.call(data, abortTrigger)` returns an `HttpsCallableResult`. A call has a timeout that covers
  the token fetch and aborts the request, a cancellation future, and optionally a limited-use App Check token
  (`HttpsCallableOptions`).
- Requests carry the ID token of `app.authProvider` as `Authorization: Bearer` and the App Check token of
  `app.appCheckProvider` as `X-Firebase-AppCheck`, only to `https` hosts, the configured emulator and
  loopback. An Auth provider error fails the call; an App Check error never does. Redirects are refused.
- Values: JSON types, with whole doubles written as integers as JavaScript writes them, large integers as
  exact digits on 64-bit platforms, and `Int64Value` and `UInt64Value` wrappers decoded in responses. Non-finite
  numbers, `DateTime`, `BigInt`, non-string map keys and nesting beyond 512 levels are refused with an
  `ArgumentError`.
- Responses: the callable envelope decides the code, the HTTP status table covers answers without one; the
  server's message is sanitized and kept, its details are decoded. Response bodies are capped (32 MiB, errors
  1 MiB).
- `FirebaseFunctionsException` with the 16 codes (`firebaseFunctionsExceptionCodes`), `details`, `httpStatus`;
  a transport failure is `unavailable`, a deadline `deadline-exceeded`, a cancel `cancelled`.
- `HttpsCallable.stream(data, abortTrigger)` for streaming callables (server-sent events): `CallableMessage`
  events and a last `CallableResult`; an idle timeout instead of a total one, a non-2xx or JSON answer handled
  like a unary response, an end without a result reported as `internal`, and `close()` aborting streams too.
- Runs on the Dart VM and the web (dart2js and dart2wasm) with no `dart:io` in the library.
- Examples (`example/`), a Functions emulator fixture (`tool/functions_emulator`) and a production verification
  kit (`tool/verify_production_functions`).
