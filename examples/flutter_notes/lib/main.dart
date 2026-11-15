// A notes app on cloud_firestore_dart. See README.md.

import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:flutter/material.dart';

import 'firestore_setup.dart';
import 'notes_page.dart';

Future<void> main() async {
  // path_provider and connectivity_plus talk to the platform: the binding
  // must exist before the app and the instance are created.
  WidgetsFlutterBinding.ensureInitialized();
  final AppDependencies dependencies = AppDependencies();
  final Firestore firestore = await createFirestore(dependencies);
  runApp(NotesApp(firestore: firestore, dependencies: dependencies));
}

class NotesApp extends StatefulWidget {
  const NotesApp({
    super.key,
    required this.firestore,
    required this.dependencies,
  });

  final Firestore firestore;
  final AppDependencies dependencies;

  @override
  State<NotesApp> createState() => _NotesAppState();
}

class _NotesAppState extends State<NotesApp> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      // Android and iOS: no network while the app is in the background. The
      // listeners keep serving the cache, and writes wait in it. On resume
      // the client connects at once instead of finding a dead connection
      // and backing off.
      onPause: () => unawaited(widget.firestore.disableNetwork()),
      onResume: () => unawaited(widget.firestore.enableNetwork()),
      // Desktop: the user quits the app or closes its last window.
      onExitRequested: _shutdown,
    );
  }

  Future<AppExitResponse> _shutdown() async {
    // Closes the streams and the SQLite file. Writes that the server has not
    // acknowledged stay in the cache and are sent on the next start.
    await widget.firestore.terminate();
    await widget.dependencies.dispose();
    return AppExitResponse.exit;
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Notes',
      theme: ThemeData(colorSchemeSeed: Colors.indigo),
      home: NotesPage(firestore: widget.firestore),
    );
  }
}
