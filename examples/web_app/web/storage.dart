// Files in Cloud Storage for Firebase from a page: a resumable upload with a
// progress bar and pause, resume and cancel buttons, the list of a folder, and
// the images of that folder shown by their download URL.
//
// Address settings: `storageEmulator=<host>:<port>` (default 127.0.0.1:9199;
// `none` uses the production backend of the options below).

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_storage_dart/firebase_storage_dart.dart';
import 'package:web/web.dart' as web;

/// `demo-test` and its bucket are the ones of `tool/start_storage_emulator.sh`
/// (open rules). For a real project, put the options of its web app here and
/// open the page with `?storageEmulator=none`.
const FirebaseOptions _options = FirebaseOptions(
  apiKey: 'demo-key',
  appId: '1:1234567890:web:example',
  projectId: 'demo-test',
  storageBucket: 'demo-test.appspot.com',
);

const String _folder = 'web_app';

Future<void> main() async {
  final String emulator =
      Uri.base.queryParameters['storageEmulator'] ?? '127.0.0.1:9199';
  _text(
    '#backend',
    emulator == 'none'
        ? 'production (${_options.projectId})'
        : 'emulator $emulator',
  );
  final FirebaseStorage storage = FirebaseStorage(
    FirebaseApp.withOptions(_options),
    emulatorHost: emulator == 'none' ? null : emulator,
  );
  final _Page page = _Page(storage.ref(_folder));
  await page.refresh();
}

class _Page {
  _Page(this._folder) {
    _form.onSubmit.listen((web.Event event) {
      event.preventDefault();
      unawaited(_upload());
    });
    _button('#pause').onClick.listen((_) => _task?.pause());
    _button('#resume').onClick.listen((_) => _task?.resume());
    _button('#cancel').onClick.listen((_) => _task?.cancel());
    _button('#refresh').onClick.listen((_) => unawaited(refresh()));
  }

  final Reference _folder;
  UploadTask? _task;

  web.HTMLFormElement get _form =>
      web.document.querySelector('#upload') as web.HTMLFormElement;
  web.HTMLProgressElement get _bar =>
      web.document.querySelector('#progress') as web.HTMLProgressElement;

  Future<void> _upload() async {
    final web.HTMLInputElement input =
        web.document.querySelector('#file') as web.HTMLInputElement;
    final web.File? file = input.files?.item(0);
    if (file == null) {
      _text('#status', 'Pick a file first.');
      return;
    }
    _text('#error', '');
    final Uint8List data = (await file.arrayBuffer().toDart).toDart
        .asUint8List();
    final UploadTask task = _folder
        .child(file.name)
        .startUpload(
          data,
          metadata: SettableMetadata(
            contentType: file.type.isEmpty ? null : file.type,
          ),
        );
    _task = task;
    _bar.hidden = false.toJS;
    _controls(running: true);
    final StreamSubscription<UploadProgress> progress = task.progress.listen((
      UploadProgress event,
    ) {
      _bar.value = event.totalBytes == 0
          ? 100
          : 100 * event.bytesTransferred / event.totalBytes;
      _text(
        '#status',
        '${event.state.name}: ${event.bytesTransferred} of '
            '${event.totalBytes} bytes',
      );
      _controls(
        running: event.state == UploadState.running,
        paused: event.state == UploadState.paused,
      );
    });
    try {
      await task.result;
      _text('#status', 'Uploaded ${file.name}.');
      input.value = '';
    } on FirebaseStorageException catch (error) {
      _text('#status', 'Stopped: ${error.code}');
      if (error.code != 'canceled') {
        _text('#error', '${error.message}');
      }
    } finally {
      await progress.cancel();
      _task = null;
      _controls();
      await refresh();
    }
  }

  void _controls({bool running = false, bool paused = false}) {
    _button('#pause').disabled = !running;
    _button('#resume').disabled = !paused;
    _button('#cancel').disabled = !(running || paused);
  }

  Future<void> refresh() async {
    final web.Element list = web.document.querySelector('#files')!;
    try {
      final ListResult result = await _folder.listAll();
      list.textContent = '';
      for (final Reference item in result.items) {
        list.append(await _entry(item));
      }
      if (result.items.isEmpty) {
        list.textContent = 'No files yet.';
      }
    } on FirebaseStorageException catch (error) {
      _text('#error', 'List failed: ${error.code}: ${error.message}');
    }
  }

  Future<web.Element> _entry(Reference item) async {
    final FullMetadata metadata = await item.metadata();
    final web.Element entry = web.document.createElement('li');
    final web.HTMLAnchorElement link =
        web.document.createElement('a') as web.HTMLAnchorElement;
    final String url = await item.downloadUrl();
    link.href = url;
    link.textContent = item.name;
    entry.append(link);
    entry.append(web.Text(' (${metadata.size} bytes) '));
    final web.HTMLButtonElement remove =
        web.document.createElement('button') as web.HTMLButtonElement;
    remove.textContent = 'Delete';
    remove.onClick.listen((_) async {
      await item.delete();
      await refresh();
    });
    entry.append(remove);
    if (metadata.contentType?.startsWith('image/') ?? false) {
      final web.HTMLImageElement image =
          web.document.createElement('img') as web.HTMLImageElement;
      image.src = url;
      image.alt = item.name;
      image.className = 'thumbnail';
      entry.append(web.document.createElement('br'));
      entry.append(image);
    }
    return entry;
  }
}

web.HTMLButtonElement _button(String selector) =>
    web.document.querySelector(selector) as web.HTMLButtonElement;

void _text(String selector, String text) {
  web.document.querySelector(selector)?.textContent = text;
}
