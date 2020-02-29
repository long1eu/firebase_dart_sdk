// File created by
// Lung Razvan <long1eu>
// on 24/10/2018

import 'dart:async';

import 'package:firebase_storage/src/storage_task_scheduler.dart';

class MockStorageTaskScheduler implements StorageTaskScheduler {
  factory MockStorageTaskScheduler() => instance;

  MockStorageTaskScheduler._();

  static final MockStorageTaskScheduler instance = MockStorageTaskScheduler._();

  @override
  Future<R> scheduleCallback<R, P>(
      Future<R> Function(P argument) function, P argument) {
    return function(argument);
  }

  @override
  Future<R> scheduleCommand<R, P>(
      Future<R> Function(P argument) function, P argument) {
    return function(argument);
  }

  @override
  Future<R> scheduleDownload<R, P>(
      Future<R> Function(P argument) function, P argument) {
    return function(argument);
  }

  @override
  Future<R> scheduleUpload<R, P>(
      Future<R> Function(P argument) function, P argument) {
    return function(argument);
  }
}
