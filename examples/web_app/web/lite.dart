// The same notes with Firestore Lite: no cache, no listener, every call is one
// request. This file imports `lite.dart` only, so the compiled page contains
// no sync engine, local store, SQLite layer or WebChannel. Compare its size
// with the page of the main library (README.md).
//
// EXPERIMENTAL: the web support and the Lite API of cloud_firestore_dart are
// experimental.

import 'dart:async';

import 'package:cloud_firestore_dart/lite.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:web/web.dart' as web;
import 'package:web_app/app_config.dart';

Future<void> main() async {
  final AppConfig config = AppConfig.fromUri(Uri.base);
  _text('#backend', config.backendLabel);

  final FirebaseApp app = FirebaseApp.withOptions(firebaseOptions);
  Settings settings = Settings();
  if (config.emulatorHost != null) {
    settings = settings.withEmulator(
      config.emulatorHost!,
      config.emulatorPort!,
    );
  }
  final FirebaseFirestore firestore = FirebaseFirestore.instanceFor(
    app: app,
    settings: settings,
  );
  final CollectionReference<Map<String, Object?>> notes = firestore.collection(
    notesCollection,
  );

  final web.HTMLButtonElement refresh =
      web.document.querySelector('#refresh') as web.HTMLButtonElement;
  refresh.onClick.listen((web.Event _) => unawaited(_load(notes)));
  _setUpForm(notes);
  await _load(notes);
}

/// Reads the 50 newest notes from the backend. There is no listener: the list
/// changes only when this runs again.
Future<void> _load(CollectionReference<Map<String, Object?>> notes) async {
  final web.Element list = web.document.querySelector('#notes')!;
  try {
    final QuerySnapshot<Map<String, Object?>> snapshot = await notes
        .orderBy('createdAt', descending: true)
        .limit(50)
        .get();
    list.textContent = '';
    for (final QueryDocumentSnapshot<Map<String, Object?>> doc
        in snapshot.docs) {
      final web.Element item = web.document.createElement('li');
      item.textContent = '${doc.data()['text']}';
      list.append(item);
    }
    if (snapshot.docs.isEmpty) {
      list.textContent = 'No notes yet.';
    }
    _text(
      '#sync',
      'Read ${snapshot.docs.length} notes at ${_time(DateTime.now())}',
    );
  } on FirestoreException catch (e) {
    // Without a connection a read fails (unavailable): there is no cache.
    _text('#sync', 'Read failed: ${e.code}: ${e.message}');
  }
}

/// Adds a note and reads the list again. A Lite write is not queued: it
/// completes when the backend has applied it, or fails.
void _setUpForm(CollectionReference<Map<String, Object?>> notes) {
  final web.HTMLFormElement form =
      web.document.querySelector('#add') as web.HTMLFormElement;
  final web.HTMLInputElement input =
      web.document.querySelector('#text') as web.HTMLInputElement;
  form.onSubmit.listen((web.Event event) async {
    event.preventDefault();
    final String text = input.value.trim();
    if (text.isEmpty) {
      return;
    }
    try {
      await notes.add(<String, Object?>{
        'text': text,
        'createdAt': FieldValue.serverTimestamp(),
      });
      input.value = '';
      _text('#error', '');
      await _load(notes);
    } on FirestoreException catch (e) {
      _text('#error', 'Write failed: ${e.code}: ${e.message}');
    }
  });
}

void _text(String selector, String text) {
  web.document.querySelector(selector)?.textContent = text;
}

String _time(DateTime time) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
}
