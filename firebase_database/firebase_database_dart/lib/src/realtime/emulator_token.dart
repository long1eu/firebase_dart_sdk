/// Credentials for the emulator (owner U): the unsigned mock user token and the admin `owner`
/// credential (`rtdb_protocol.md` 2.4; threat model T3).
library;

/// The credential the admin SDKs send to the emulator, as `gauth` with `cred: "owner"` (2.4,
/// AuthTokenProvider.ts:108-111, PersistentConnection.ts:383).
const String ownerToken = 'owner';

/// An unsigned JWT for the emulator built from [claims] for [projectId] (2.4,
/// `util:src/emulator.ts:95-142`).
///
/// Header `{"alg":"none","type":"JWT"}` (`type`, not `typ`); payload `iss`
/// `https://securetoken.google.com/<projectId>`, `aud`, `iat` (default 0), `exp` = `iat` + 3600,
/// `auth_time`, `sub`, `user_id`, `firebase: {sign_in_provider: custom, identities: {}}`, then
/// [claims] on top in that key order; base64url without padding; empty signature. Because `iat` is
/// present the token is sent as `auth` (4.6). Throws [ArgumentError] when [claims] has neither
/// `sub` nor `user_id`, or has `uid`. Use only with an emulator (T3: refused otherwise by the
/// caller).
String createMockUserToken(
  Map<String, Object?> claims, {
  required String projectId,
}) {
  throw UnimplementedError();
}
