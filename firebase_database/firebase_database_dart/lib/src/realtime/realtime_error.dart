/// Wire status strings as the connection half reads them (owner K): `rtdb_protocol.md` 9 and 10;
/// threat model T7.
///
/// One error vocabulary for the package: the core's `DatabaseErrorCode` / `DatabaseError`
/// (`rtdb_seam_changes.md` A.9). Statuses cross the seam as strings (and a failed `get` as a
/// `ServerActionsException`); mapping them to codes is the core's `DatabaseError.fromStatus`. This
/// file only holds what the connection half itself needs: the REST status rule, the invalid-token
/// rule and the cleaning of server text. It declares no exception type.
library;

/// The listen-response warning key value for a query without an index rule (4.1): `no_index`.
const String noIndexWarning = 'no_index';

/// Prefix of the status a REST listen synthesises for a non-2xx answer other than 401:
/// `rest_error:<code>` (10, ReadonlyRestClient.ts:124).
const String restErrorPrefix = 'rest_error:';

/// The status of a REST listen answered with [httpStatus] (10): `permission_denied` for 401,
/// `rest_error:<httpStatus>` for any other non-2xx except 404 (404 is null data, not an error).
String restListenStatus(int httpStatus) {
  throw UnimplementedError();
}

/// Whether [status] counts toward the invalid-token threshold of 8.3: `invalid_token` or
/// `permission_denied` (PersistentConnection.ts:985-1004).
bool countsAsInvalidToken(String status) {
  throw UnimplementedError();
}

/// [text] from the server made safe for a log line or an error message (threat model T7): cut at
/// 1 KiB with a marker, control characters escaped as `\uXXXX`. For the shutdown reason, `e`
/// control errors, revoke explanations and `sd` messages.
String safeServerText(String text) {
  throw UnimplementedError();
}
