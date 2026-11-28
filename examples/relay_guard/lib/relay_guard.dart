/// The checks a relay makes before it forwards a request with its own credentials.
///
/// A relay is a small server of yours that receives what an app in users' hands sends (error reports, analytics
/// events) and forwards it to a Google API with a credential the app must not hold. Without checks, anyone could
/// use it to write into your project. [relayGuard] is `package:shelf` middleware that refuses a request unless:
///
/// * it is a `POST` with a JSON body no larger than `maxBodyBytes`;
/// * it carries a valid App Check token (`X-Firebase-AppCheck`), unless `requireAppCheck` is false;
/// * it carries a valid Firebase ID token (`Authorization: Bearer`) when `requireUser` is true, and a token that
///   is present is always checked;
/// * the caller (the user, else the app, else the address of the connection) has not passed `maxPerMinute`.
///
/// The tokens are checked by a [CallerVerifier]: [AdminCallerVerifier] with `firebase_admin_dart`, or your own.
/// The handler behind the middleware reads the caller with [callerOf] and the body with [bodyOf].
library;

export 'src/caller.dart';
export 'src/guard.dart';
