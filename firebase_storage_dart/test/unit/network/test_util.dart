// File created by
// Lung Razvan <long1eu>
// on 23/10/2018

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage_vm/src/firebase_storage.dart';
import 'package:firebase_storage_vm/src/storage_task_scheduler.dart';
import 'package:rxdart/rxdart.dart';
import 'package:test/test.dart';

import 'mock_storage_task_scheduler.dart';

const String _tag = 'TestUtil';

Future<void> setUp() async {
  StorageTaskScheduler.instance = MockStorageTaskScheduler.instance;

  FirebaseApp.withOptions(
    FirebaseOptions(
        apiKey: 'AIzaSyCkEhVjf3pduRDt6d1yKOMitrUEke8agEM',
        applicationId: 'fooey',
        storageBucket: 'project-5516366556574091405.appspot.com'),
    MockAuthProvider(),
    () async => true,
  );

  //await StorageTaskScheduler.initialize();
}

void tearDown() => FirebaseStorage.clearInstancesForTest();

Future<void> verifyTaskStateChanges(String testName,
    {/*TestDownloadHelper.StreamDownloadResponse*/ dynamic response,
    String contents}) async {
  Log.d(_tag, 'Verifying task file.');
  String filename = 'assets/$testName\_task.txt';
  Stream<List<int>> inputStream =
      File('${Directory.current.path}/test/res/$filename').openRead();

  if (response != null) {
    await _verifyTaskStateChanges(inputStream, response.mainTask.toString());
  } else if (contents != null) {
    await _verifyTaskStateChanges(inputStream, contents);
    return;
  } else {
    throw StateError('At least one of response or contents must be provided.');
  }

  Log.d(_tag, 'Verifying background file.');
  filename = 'assets/$testName\_background.txt';
  inputStream = File('${Directory.current.path}/test/res/$filename').openRead();
  await _verifyTaskStateChanges(
      inputStream, response.backgroundTask.toString());
}

Future<void> _verifyTaskStateChanges(
    Stream<List<int>> inputStream, String contents) async {
  final Completer<void> completer = Completer<void>();
  if (inputStream == null) {
    if (contents.isNotEmpty) {
      Log.e(_tag, 'Original:');
      Log.e(_tag, 'New:');
      Log.e(_tag, contents);
    }
    return;
  }

  final String baselineContents = await inputStream
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .join('\n');

  int line = 1;
  Observable.zip2(
      Observable<String>.just(baselineContents).transform(const LineSplitter()),
      Observable<String>.just(contents).transform(const LineSplitter()),
      (String originalLine, String newLine) {
    if (originalLine.length == newLine.length + 1 &&
        originalLine.codeUnitAt(originalLine.length - 1) == /*' '*/ 0x20) {
      // fix trailing spaces
      originalLine = originalLine.substring(0, originalLine.length - 1);
    }
    if (originalLine.contains('currentState:')) {
      if (originalLine != newLine) {
        Log.d(_tag, 'Warning!!! Line $line is different.');
      }
    } else {
      if (originalLine != newLine) {
        Log.e(_tag, 'Original:');
        Log.e(_tag, baselineContents.toString());
        Log.e(_tag, 'New:');
        Log.e(_tag, contents);
      }
      expect(newLine, originalLine, reason: 'line:$line is different.');
    }
    line++;
  }).listen(null, onDone: completer.complete);

  await completer.future.timeout(const Duration(seconds: 2),
      onTimeout: () => throw 'Last line check at $line');
}

class MockAuthProvider extends InternalTokenProvider {
  @override
  Future<GetTokenResult> getAccessToken(bool forceRefresh) async =>
      const GetTokenResult('token');

  @override
  Stream<InternalTokenResult> get onTokenChanged {
    throw StateError('This method is not implemented for Firebase Strorage.');
  }

  @override
  String get uid {
    throw StateError('This method is not implemented for Firebase Strorage.');
  }
}
