// DatabaseError.fromStatus and DatabaseErrorCode.fromWireStatus: the status table of contract C19
// and the seam's local statuses.
import 'package:firebase_database_dart/src/core/connection/server_actions.dart';
import 'package:firebase_database_dart/src/core/database_error.dart';
import 'package:test/test.dart';

void main() {
  const Map<String, DatabaseErrorCode> table = <String, DatabaseErrorCode>{
    'datastale': DatabaseErrorCode.dataStale,
    'failure': DatabaseErrorCode.operationFailed,
    'permission_denied': DatabaseErrorCode.permissionDenied,
    'disconnected': DatabaseErrorCode.disconnected,
    'maxretries': DatabaseErrorCode.maxRetries,
    'overriddenbyset': DatabaseErrorCode.overriddenBySet,
    'unavailable': DatabaseErrorCode.unavailable,
    'too_big': DatabaseErrorCode.tooBig,
    'user_code_exception': DatabaseErrorCode.userCodeException,
    statusNetworkError: DatabaseErrorCode.networkError,
    'write_canceled': DatabaseErrorCode.writeCanceled,
    'no_index': DatabaseErrorCode.indexNotDefined,
    'database_closed': DatabaseErrorCode.databaseClosed,
    'unknown': DatabaseErrorCode.unknown,
    // Local statuses of JS and Android.
    statusDisconnect: DatabaseErrorCode.disconnected,
    'maxretry': DatabaseErrorCode.maxRetries,
    'set': DatabaseErrorCode.overriddenBySet,
    'overriddenBySet': DatabaseErrorCode.overriddenBySet,
  };

  for (final MapEntry<String, DatabaseErrorCode> entry in table.entries) {
    test('${entry.key} maps to ${entry.value.code}', () {
      expect(DatabaseErrorCode.fromWireStatus(entry.key), entry.value);
      final DatabaseError error = DatabaseError.fromStatus(entry.key, 'why');
      expect(error.code, entry.value);
      expect(error.details, 'why');
      expect(error.message, isNotEmpty);
    });
  }

  test('every code maps back from its own wire status', () {
    for (final DatabaseErrorCode code in DatabaseErrorCode.values) {
      expect(DatabaseErrorCode.fromWireStatus(code.wireStatus), code);
    }
  });

  test('an unknown status is unknown and keeps the raw status', () {
    final DatabaseError withReason = DatabaseError.fromStatus(
      'invalid_parameters',
      'bad query',
    );
    expect(withReason.code, DatabaseErrorCode.unknown);
    expect(withReason.details, 'invalid_parameters: bad query');
    final DatabaseError bare = DatabaseError.fromStatus('internal_error');
    expect(bare.code, DatabaseErrorCode.unknown);
    expect(bare.details, 'internal_error');
  });

  test('toString shows code, message and details', () {
    expect(
      DatabaseError.fromStatus('permission_denied', 'rules').toString(),
      'DatabaseError(permission-denied): This client does not have permission to '
      'perform this operation. (rules)',
    );
  });
}
