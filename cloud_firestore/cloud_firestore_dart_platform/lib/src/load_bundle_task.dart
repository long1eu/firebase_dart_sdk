import 'dart:async';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart' as fs;
import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';

import 'errors.dart';

/// A [LoadBundleTaskPlatform] for a `cloud_firestore_dart` [fs.LoadBundleTask].
///
/// The task starts loading at once. Each listener of [stream] first gets the
/// progress events reported so far, then the later ones; the stream ends after
/// a `success` event, or with a [FirebaseException] error when the bundle
/// could not be loaded (as the method channel implementation does).
class DartLoadBundleTask
    extends LoadBundleTaskPlatform<LoadBundleTaskSnapshotPlatform> {
  /// The platform view of [task].
  DartLoadBundleTask(fs.LoadBundleTask task) {
    task.stream.listen(_onProgress, onError: _onError, onDone: _onDone);
  }

  final List<_Event> _events = <_Event>[];
  final Set<MultiStreamController<LoadBundleTaskSnapshotPlatform>> _listeners =
      <MultiStreamController<LoadBundleTaskSnapshotPlatform>>{};
  bool _done = false;

  @override
  late final Stream<LoadBundleTaskSnapshotPlatform> stream =
      Stream<LoadBundleTaskSnapshotPlatform>.multi((
        MultiStreamController<LoadBundleTaskSnapshotPlatform> controller,
      ) {
        for (final _Event event in _events) {
          event.deliver(controller);
        }
        if (_done) {
          controller.close();
          return;
        }
        _listeners.add(controller);
        controller.onCancel = () => _listeners.remove(controller);
      }, isBroadcast: true);

  void _add(_Event event) {
    if (_done) {
      return;
    }
    _events.add(event);
    for (final MultiStreamController<LoadBundleTaskSnapshotPlatform> listener
        in _listeners.toList()) {
      event.deliver(listener);
    }
  }

  void _onProgress(fs.LoadBundleTaskSnapshot progress) {
    if (progress.taskState == fs.LoadBundleTaskState.error) {
      _onError(progress.exception ?? StateError('The bundle failed to load.'));
      return;
    }
    _add(
      _Event.data(
        LoadBundleTaskSnapshotPlatform(
          progress.taskState == fs.LoadBundleTaskState.success
              ? LoadBundleTaskState.success
              : LoadBundleTaskState.running,
          <String, dynamic>{
            'bytesLoaded': progress.bytesLoaded,
            'documentsLoaded': progress.documentsLoaded,
            'totalBytes': progress.totalBytes,
            'totalDocuments': progress.totalDocuments,
          },
        ),
      ),
    );
  }

  void _onError(Object error, [StackTrace? stackTrace]) {
    final Object converted = convertError(error, stackTrace);
    _add(
      _Event.error(
        converted is FirebaseException
            ? converted
            : FirebaseException(
                plugin: firestorePlugin,
                code: 'load-bundle-error',
                message: '$error',
              ),
        stackTrace ?? StackTrace.current,
      ),
    );
    _onDone();
  }

  void _onDone() {
    if (_done) {
      return;
    }
    _done = true;
    for (final MultiStreamController<LoadBundleTaskSnapshotPlatform> listener
        in _listeners.toList()) {
      listener.close();
    }
    _listeners.clear();
  }
}

class _Event {
  _Event.data(this.data) : error = null, stackTrace = null;

  _Event.error(Object this.error, StackTrace this.stackTrace) : data = null;

  final LoadBundleTaskSnapshotPlatform? data;
  final Object? error;
  final StackTrace? stackTrace;

  void deliver(MultiStreamController<LoadBundleTaskSnapshotPlatform> sink) {
    final Object? error = this.error;
    if (error != null) {
      sink.addError(error, stackTrace);
    } else {
      sink.add(data!);
    }
  }
}
