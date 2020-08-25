// File created by
// Lung Razvan <long1eu>
// on 20/10/2018

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage_vm/src/cancel_exception.dart';

import 'storage_reference.dart';
import 'storage_task.dart';

/// Represents an Exception resulting from an operation on a [StorageReference].
class StorageException extends FirebaseError {
  StorageException(
      /*@ErrorCode*/ this.errorCode, this._cause, this.httpResultCode)
      : super(getErrorMessageForCode(errorCode)) {
    Log.e(
        _tag,
        'StorageException has occurred.\n$message\n '
        'Code: $errorCode HttpResult: $httpResultCode');
    if (_cause != null) {
      Log.e(_tag, _cause.message);
    }
  }

  factory StorageException.fromErrorStatus(Status status) {
    Preconditions.checkNotNull(status);
    Preconditions.checkArgument(
        !status.isSuccess, 'This should not be succcesful');
    return StorageException(_calculateErrorCode(status), null, 0);
  }

  factory StorageException.fromExceptionAndHttpCode(
      dynamic exception, int httpResultCode) {
    if (exception is StorageException) {
      return exception;
    }
    if (_isResultSuccess(httpResultCode) && exception == null) {
      return null;
    }
    return StorageException(_calculateHttpErrorCode(exception, httpResultCode),
        exception, httpResultCode);
  }

  factory StorageException.fromException(dynamic exception) {
    final StorageException se =
        StorageException.fromExceptionAndHttpCode(exception, 0);
    assert(se != null);
    return se;
  }

  static const String _tag = 'StorageException';

  static const int _networkUnavailable = -2;

  final ErrorCode errorCode;

  /// The Http result code (if one exists) from a network operation.
  final int httpResultCode;

  dynamic _cause;

  static ErrorCode _calculateErrorCode(Status status) {
    if (status.isCanceled) {
      return ErrorCode.errorCanceled;
    }
    if (status == Status.resultTimeout) {
      return ErrorCode.errorRetryLimitExceeded;
    }
    return ErrorCode.errorUnknown;
  }

  static ErrorCode _calculateHttpErrorCode(dynamic inner, int httpResultCode) {
    if (inner is CancelException) {
      return ErrorCode.errorCanceled;
    }
    switch (httpResultCode) {
      case _networkUnavailable:
        return ErrorCode.errorRetryLimitExceeded;
      case 401:
        return ErrorCode.errorNotAuthenticated;
      case 403:
        return ErrorCode.errorNotAuthorized;
      case 404:
        return ErrorCode.errorObjectNotFound;
      case 409:
        return ErrorCode.errorInvalidChecksum;
      default:
        return ErrorCode.errorUnknown;
    }
  }

  static bool _isResultSuccess(int resultCode) {
    return resultCode == 0 || (resultCode >= 200 && resultCode < 300);
  }

  static String getErrorMessageForCode(ErrorCode errorCode) {
    switch (errorCode) {
      case ErrorCode.errorUnknown:
        return 'An unknown error occurred, please check the HTTP result code '
            'and inner exception for server response.';
      case ErrorCode.errorObjectNotFound:
        return 'Object does not exist at location.';
      case ErrorCode.errorBucketNotFound:
        return 'Bucket does not exist.';
      case ErrorCode.errorProjectNotFound:
        return 'Project does not exist.';
      case ErrorCode.errorQuotaExceeded:
        return 'Quota for bucket exceeded, please view quota on '
            'www.firebase.google.com/storage.';
      case ErrorCode.errorNotAuthenticated:
        return 'User is not authenticated, please authenticate using Firebase '
            'Authentication and try again.';
      case ErrorCode.errorNotAuthorized:
        return 'User does not have permission to access this object.';
      case ErrorCode.errorRetryLimitExceeded:
        return 'The operation retry limit has been exceeded.';
      case ErrorCode.errorInvalidChecksum:
        return 'Object has a checksum which does not match. Please retry the '
            'operation.';
      case ErrorCode.errorCanceled:
        return 'The operation was cancelled.';
      default:
        return 'An unknown error occurred, please check the HTTP result code '
            'and inner exception for server response.';
    }
  }

  /// Returns the cause of this error, or null if there is no cause.
  dynamic get cause => _cause == this ? null : _cause;

  /// Returns true if this request failed due to a network condition that may be
  /// resolved in a future attempt.
  bool get isRecoverableException =>
      errorCode == ErrorCode.errorRetryLimitExceeded;
}

/// An [ErrorCode] indicates the source of a failed [StorageTask] or operation.
class ErrorCode {
  const ErrorCode(this._i);

  final int _i;

  static const ErrorCode errorUnknown = ErrorCode(-13000);
  static const ErrorCode errorObjectNotFound = ErrorCode(-13010);
  static const ErrorCode errorBucketNotFound = ErrorCode(-13011);
  static const ErrorCode errorProjectNotFound = ErrorCode(-13012);
  static const ErrorCode errorQuotaExceeded = ErrorCode(-13013);
  static const ErrorCode errorNotAuthenticated = ErrorCode(-13020);
  static const ErrorCode errorNotAuthorized = ErrorCode(-13021);
  static const ErrorCode errorRetryLimitExceeded = ErrorCode(-13030);
  static const ErrorCode errorInvalidChecksum = ErrorCode(-13031);
  static const ErrorCode errorCanceled = ErrorCode(-13040);

  static const Map<int, String> _values = <int, String>{
    -13000: 'errorUnknown',
    -13010: 'errorObjectNotFound',
    -13011: 'errorBucketNotFound',
    -13012: 'errorProjectNotFound',
    -13013: 'errorQuotaExceeded',
    -13020: 'errorNotAuthenticated',
    -13021: 'errorNotAuthorized',
    -13030: 'errorRetryLimitExceeded',
    -13031: 'errorInvalidChecksum',
    -13040: 'errorCanceled',
  };

  @override
  String toString() => _values[_i];
}

class Status {
  const Status._(this.statusCode);

  final int statusCode;

  static const Status resultSuccess = Status._(0);

  static const Status resultInterrupted = Status._(14);

  static const Status resultInternalError = Status._(8);

  static const Status resultTimeout = Status._(15);

  static const Status resultCanceled = Status._(16);

  static const Status resultDeadClient = Status._(18);

  bool get isSuccess => statusCode <= 0;

  bool get isCanceled => statusCode == 16;
}
