// File created by
// Lung Razvan <long1eu>
// on 22/10/2018

import 'package:firebase_common/firebase_common.dart';
import 'package:firebase_storage/src/file_download_task.dart';
import 'package:firebase_storage/src/storage_exception.dart';
import 'package:firebase_storage/src/storage_reference.dart';
import 'package:firebase_storage/src/storage_task.dart';

class TaskEventType {
  final int _i;

  const TaskEventType._(this._i);

  static const TaskEventType progress = TaskEventType._(0);
  static const TaskEventType paused = TaskEventType._(1);
  static const TaskEventType success = TaskEventType._(2);
  static const TaskEventType error = TaskEventType._(3);
  static const TaskEventType complete = TaskEventType._(4);

  static TaskEventType fromValue(int i) {
    switch (i) {
      case 0:
        return TaskEventType.progress;
      case 1:
        return TaskEventType.paused;
      case 2:
        return TaskEventType.success;
      case 3:
        return TaskEventType.error;
      case 4:
        return TaskEventType.complete;
      default:
        throw StateError('$i is not a valid value.');
    }
  }
}

class TaskEvent<TResult extends StorageTaskState> {
  final TaskEventType type;
  final TResult data;

  TaskEvent(this.type, {this.data});

  factory TaskEvent.progressed(TResult progress) =>
      TaskEvent<TResult>(TaskEventType.progress, data: progress);

  factory TaskEvent.paused() => TaskEvent<TResult>(TaskEventType.paused);

  factory TaskEvent.success(TResult result) =>
      TaskEvent<TResult>(TaskEventType.success, data: result);

  factory TaskEvent.complete() => TaskEvent<TResult>(TaskEventType.complete);

  factory TaskEvent.error(TResult data) =>
      TaskEvent<TResult>(TaskEventType.error, data: data);

  factory TaskEvent.deserialized(List<dynamic> values) {
    final int typeValue = values[0];
    final TaskEventType type = TaskEventType.fromValue(typeValue);

    final List<dynamic> dataValues = values[1];

    if (dataValues[1] == null) {
      return TaskEvent<TResult>(type);
    }

    final String constructor = dataValues[0];
    final List<dynamic> args = dataValues[1];

    final TResult object = StorageTaskState.constructors[constructor](args);
    return TaskEvent<TResult>(type, data: object);
  }

  List<dynamic> get serialize => <dynamic>[
        type._i,
        <dynamic>['${data?.runtimeType}', data?.serialized]
      ];
}

abstract class StorageTaskState {
  dynamic get error;

  List<dynamic> get serialized;

  static Map<String, Function> constructors = <String, Function>{
    'SnapshotBase': SnapshotBase.deserialized,
    'DownloadTaskSnapshot': DownloadTaskSnapshot.deserialized,
  };
}

/// Base class for state.
class SnapshotBase<TResult extends StorageTaskState>
    implements StorageTaskState {
  @override
  final dynamic error;
  final String referenceUrl;

  // This should be private
  SnapshotBase(this.error, this.referenceUrl);

  // This is the default constructor
  factory SnapshotBase.base(
      String referenceUrl,
      int currentState,
      // ignore: avoid_positional_boolean_parameters
      bool isCanceled,
      dynamic error) {
    return SnapshotBase<TResult>(
        errorFor(currentState, isCanceled, error), referenceUrl);
  }

  static SnapshotBase<TResult> deserialized<TResult extends StorageTaskState>(
      List<dynamic> values) {
    final dynamic error = values[0];
    final String referenceUrl = values[1];

    return SnapshotBase<TResult>(error, referenceUrl);
  }

  static dynamic errorFor(
      int currentState,
      // ignore: avoid_positional_boolean_parameters
      bool isCanceled,
      dynamic error) {
    if (error == null) {
      if (isCanceled) {
        // give the developer a canceled exception.
        return StorageException.fromErrorStatus(Status.resultCanceled);
      } else if (currentState == StorageTask.kInternalStateFailure) {
        // this is unexpected and a bug.
        return StorageException.fromErrorStatus(Status.resultInternalError);
      } else {
        return null;
      }
    } else {
      return error;
    }
  }

  @override
  List<dynamic> get serialized => <dynamic>[error.toString(), referenceUrl];

  /// Returns the target of the upload.
  @publicApi
  StorageReference get storage {
    // ignore: only_throw_errors
    throw 'If we want to implement this we need to make sure we have the proper'
        ' FirebaseApp and the proper FirebaseStorage instance';
  }
}

/// Encapsulates state about the running [FileDownloadTask]
@publicApi
class DownloadTaskSnapshot extends SnapshotBase<DownloadTaskSnapshot> {
  /// Return the total bytes downloaded so far.
  @publicApi
  final int bytesTransferred;

  /// Returns the total bytes to upload.
  @publicApi
  final int totalByteCount;

  // This should be private
  DownloadTaskSnapshot(dynamic error, String referenceUrl,
      this.bytesTransferred, this.totalByteCount)
      : super(error, referenceUrl);

  // This is the default constructor
  factory DownloadTaskSnapshot.base(
      String referenceUrl,
      int currentState,
      // ignore: avoid_positional_boolean_parameters
      bool isCanceled,
      dynamic error,
      int bytesTransferred,
      int totalByteCount) {
    return DownloadTaskSnapshot(
        SnapshotBase.errorFor(currentState, isCanceled, error),
        referenceUrl,
        bytesTransferred,
        totalByteCount);
  }

  static DownloadTaskSnapshot deserialized(List<dynamic> values) {
    final dynamic error = values[0];
    final String referenceUrl = values[1];
    final int bytesTransferred = values[2];
    final int totalByteCount = values[3];

    return DownloadTaskSnapshot(
        error, referenceUrl, bytesTransferred, totalByteCount);
  }

  @override
  List<dynamic> get serialized =>
      super.serialized..addAll(<dynamic>[bytesTransferred, totalByteCount]);
}
