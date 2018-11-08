// File created by
// Lung Razvan <long1eu>
// on 22/10/2018

import 'package:collection/collection.dart';
import 'package:firebase_common/firebase_common.dart';
import 'package:firebase_storage/src/file_download_task.dart';
import 'package:firebase_storage/src/storage_exception.dart';
import 'package:firebase_storage/src/storage_reference.dart';
import 'package:firebase_storage/src/storage_task.dart';
import 'package:meta/meta.dart';

// ignore_for_file: prefer_constructors_over_static_methods

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

  static const List<String> _values = <String>[
    'progress',
    'paused',
    'success',
    'error',
    'complete',
  ];

  @override
  String toString() => _values[_i];
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

  static TaskEvent<TResult> deserialized<TResult extends StorageTaskState>(
      List<dynamic> values) {
    final int typeValue = values[0];
    final TaskEventType type = TaskEventType.fromValue(typeValue);

    if (values[1] == null) {
      return TaskEvent<TResult>(type);
    }

    final String constructor = values[1];
    final List<dynamic> args = values[2];

    final TResult object = StorageTaskState.constructors[constructor](args);
    return TaskEvent<TResult>(type, data: object);
  }

  TaskPayload get serialize {
    return TaskPayload(
      type: type._i,
      eventType: data != null ? '${data.runtimeType}' : null,
      data: data?._serialized,
    );
  }

  @override
  String toString() {
    return (ToStringHelper(runtimeType)..add('type', type)..add('data', data))
        .toString();
  }
}

abstract class StorageTaskState {
  dynamic get error;

  List<dynamic> get _serialized;

  static Map<String, Function> constructors = <String, Function>{
    'SnapshotBase': SnapshotBase.deserialized,
    'DownloadTaskSnapshot': DownloadTaskSnapshot.deserialized,
    'StreamDownloadTaskSnapshot': DownloadStreamTaskSnapshot.deserialized,
  };
}

abstract class StorageStreamedTaskState implements StorageTaskState {
  List<int> get data;
}

/// Base class for state.
class SnapshotBase<TResult extends StorageTaskState>
    implements StorageTaskState {
  @override
  final dynamic error;
  final String referenceUrl;

  factory SnapshotBase(
      String referenceUrl,
      int currentState,
      // ignore: avoid_positional_boolean_parameters
      bool isCanceled,
      dynamic error) {
    return SnapshotBase<TResult>._(
        errorFor(currentState, isCanceled, error), referenceUrl);
  }

  SnapshotBase._(this.error, this.referenceUrl);

  static SnapshotBase<TResult> deserialized<TResult extends StorageTaskState>(
      List<dynamic> values) {
    final dynamic error = values[0];
    final String referenceUrl = values[1];

    return SnapshotBase<TResult>._(error, referenceUrl);
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
  List<dynamic> get _serialized =>
      <dynamic>[error == null ? null : error.toString(), referenceUrl];

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

  factory DownloadTaskSnapshot(
      String referenceUrl,
      int currentState,
      // ignore: avoid_positional_boolean_parameters
      bool isCanceled,
      dynamic error,
      int bytesTransferred,
      int totalByteCount) {
    return DownloadTaskSnapshot._(
        SnapshotBase.errorFor(currentState, isCanceled, error),
        referenceUrl,
        bytesTransferred,
        totalByteCount);
  }

  DownloadTaskSnapshot._(dynamic error, String referenceUrl,
      this.bytesTransferred, this.totalByteCount)
      : super._(error, referenceUrl);

  static DownloadTaskSnapshot deserialized(List<dynamic> values) {
    final dynamic error = values[0];
    final String referenceUrl = values[1];
    final int bytesTransferred = values[2];
    final int totalByteCount = values[3];

    return DownloadTaskSnapshot._(
        error, referenceUrl, bytesTransferred, totalByteCount);
  }

  @override
  List<dynamic> get _serialized =>
      super._serialized..addAll(<dynamic>[bytesTransferred, totalByteCount]);

  @override
  String toString() {
    return (ToStringHelper(runtimeType)
          ..add('error', error)
          ..add('referenceUrl', referenceUrl)
          ..add('totalByteCount', totalByteCount)
          ..add('bytesTransferred', bytesTransferred))
        .toString();
  }
}

class DownloadStreamTaskSnapshot
    extends SnapshotBase<DownloadStreamTaskSnapshot>
    implements StorageStreamedTaskState {
  @publicApi
  final int bytesTransferred;

  /// Returns the total bytes to upload.
  @publicApi
  final int totalByteCount;

  @override
  final List<int> data;

  factory DownloadStreamTaskSnapshot(
      String referenceUrl,
      int currentState,
      // ignore: avoid_positional_boolean_parameters
      bool isCanceled,
      dynamic error,
      int bytesTransferred,
      int totalByteCount,
      List<int> data) {
    return DownloadStreamTaskSnapshot._(
      SnapshotBase.errorFor(currentState, isCanceled, error),
      referenceUrl,
      bytesTransferred,
      totalByteCount,
      data,
    );
  }

  DownloadStreamTaskSnapshot._(dynamic error, String referenceUrl,
      this.bytesTransferred, this.totalByteCount, this.data)
      : super._(error, referenceUrl);

  static DownloadStreamTaskSnapshot deserialized(List<dynamic> values) {
    final dynamic error = values[0];
    final String referenceUrl = values[1];
    final int bytesTransferred = values[2];
    final int totalByteCount = values[3];
    final List<int> data = values[4];

    return DownloadStreamTaskSnapshot._(
        error, referenceUrl, bytesTransferred, totalByteCount, data);
  }

  @override
  List<dynamic> get _serialized => super._serialized
    ..addAll(<dynamic>[bytesTransferred, totalByteCount, data]);
}

class TaskPayload extends DelegatingList<dynamic> {
  final int type;
  final String eventType;
  final List<dynamic> data;

  TaskPayload({
    @required this.type,
    @required this.eventType,
    @required this.data,
  }) : super(<dynamic>[type, eventType, data]);

  @override
  String toString() {
    return (ToStringHelper(runtimeType)
          ..add('type', '$type(${TaskEventType.fromValue(type)})')
          ..add('eventType', eventType)
          ..add('data', data))
        .toString();
  }
}
