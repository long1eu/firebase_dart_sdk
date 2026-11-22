/// Wire status strings as the connection half reads them (owner K): `rtdb_protocol.md` 9 and 10;
/// threat model T7.
///
/// One error vocabulary for the package: the core's `DatabaseErrorCode` / `DatabaseError`
/// (`rtdb_seam_changes.md` A.9). Statuses cross the seam as strings (and a failed `get` as a
/// `ServerActionsException`); mapping them to codes is the core's `DatabaseError.fromStatus`. This
/// file only holds what the connection half itself needs: the REST status rule, the invalid-token
/// rule and the cleaning of server text. It declares no exception type.
library;

import 'package:firebase_database_dart/src/core/database_error.dart';

/// The listen-response warning key value for a query without an index rule (4.1): `no_index`.
const String noIndexWarning = 'no_index';

/// Prefix of the status a REST listen synthesises for a non-2xx answer other than 401:
/// `rest_error:<code>` (10, ReadonlyRestClient.ts:124).
const String restErrorPrefix = 'rest_error:';

/// The status of a REST listen answered with [httpStatus] (10, ReadonlyRestClient.ts:118-126):
/// `ok` for 2xx and for 404 (404 is null data, not an error), `permission_denied` for 401,
/// `rest_error:<httpStatus>` for every other status.
String restListenStatus(int httpStatus) {
  if (httpStatus >= 200 && httpStatus < 300 || httpStatus == 404) {
    return _ok;
  }
  if (httpStatus == 401) {
    return DatabaseErrorCode.permissionDenied.wireStatus;
  }
  return '$restErrorPrefix$httpStatus';
}

/// Whether [status] counts toward the invalid-token threshold of 8.3: `invalid_token` or
/// `permission_denied` (PersistentConnection.ts:985-1004).
bool countsAsInvalidToken(String status) =>
    status == DatabaseErrorCode.invalidToken.wireStatus ||
    status == DatabaseErrorCode.permissionDenied.wireStatus;

/// [text] from the server made safe for a log line or an error message (threat model T7): cut at
/// 1 KiB with a marker, control characters escaped as `\uXXXX`. For the shutdown reason, `e`
/// control errors, revoke explanations and `sd` messages.
///
/// "1 KiB" counts UTF-8 bytes of the kept text before escaping; the output is the kept text with
/// its escapes, then the marker `...(cut)` when something was cut. C0 and C1 controls, DEL, the
/// line and paragraph separators U+2028/U+2029 and lone surrogates are escaped, so the result is
/// one line of valid UTF-16.
String safeServerText(String text) {
  final StringBuffer out = StringBuffer();
  int bytes = 0;
  int index = 0;
  while (index < text.length) {
    final int unit = text.codeUnitAt(index);
    final bool pair =
        _isLead(unit) &&
        index + 1 < text.length &&
        _isTrail(text.codeUnitAt(index + 1));
    final int width = pair ? 4 : _utf8Width(unit);
    if (bytes + width > _maxBytes) {
      out.write(_cutMarker);
      return out.toString();
    }
    bytes += width;
    if (pair) {
      out.write(text.substring(index, index + 2));
      index += 2;
      continue;
    }
    if (_mustEscape(unit)) {
      out.write('\\u${unit.toRadixString(16).toUpperCase().padLeft(4, '0')}');
    } else {
      out.writeCharCode(unit);
    }
    index++;
  }
  return out.toString();
}

const int _maxBytes = 1024;

const String _ok = 'ok';

const String _cutMarker = '...(cut)';

bool _isLead(int unit) => unit >= 0xD800 && unit <= 0xDBFF;

bool _isTrail(int unit) => unit >= 0xDC00 && unit <= 0xDFFF;

int _utf8Width(int unit) {
  if (unit < 0x80) {
    return 1;
  }
  if (unit < 0x800) {
    return 2;
  }
  return 3;
}

bool _mustEscape(int unit) =>
    unit < 0x20 ||
    (unit >= 0x7F && unit <= 0x9F) ||
    unit == 0x2028 ||
    unit == 0x2029 ||
    (unit >= 0xD800 && unit <= 0xDFFF);
