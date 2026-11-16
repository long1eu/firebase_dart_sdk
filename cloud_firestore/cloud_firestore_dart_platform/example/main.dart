// A Flutter app that uses the official cloud_firestore API, with
// cloud_firestore_dart doing the work underneath.
//
// On Linux the CloudFirestoreDart.use() call is optional: Flutter registers the
// package before main() runs. On the other platforms it replaces the official
// implementation. Run it against an emulator started with
// `firebase emulators:start --only firestore` (project demo-test).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_firestore_dart_platform/cloud_firestore_dart_platform.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  CloudFirestoreDart.use();
  await Firebase.initializeApp(
    // Use your own options (flutterfire configure) for a real project.
    options: const FirebaseOptions(
      apiKey: 'demo-api-key',
      appId: '1:1:web:1',
      messagingSenderId: '1',
      projectId: 'demo-test',
    ),
  );
  FirebaseFirestore.instance.useFirestoreEmulator('127.0.0.1', 8080);
  runApp(const NotesApp());
}

class NotesApp extends StatelessWidget {
  const NotesApp({super.key});

  @override
  Widget build(BuildContext context) {
    final CollectionReference<Map<String, dynamic>> notes = FirebaseFirestore
        .instance
        .collection('notes');
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Notes')),
        floatingActionButton: FloatingActionButton(
          onPressed: () => notes.add(<String, Object?>{
            'text': 'Note ${DateTime.now()}',
            'at': FieldValue.serverTimestamp(),
          }),
          child: const Icon(Icons.add),
        ),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: notes.orderBy('at', descending: true).snapshots(),
          builder:
              (
                BuildContext context,
                AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snapshot,
              ) {
                if (snapshot.hasError) {
                  return Center(child: Text('${snapshot.error}'));
                }
                final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs =
                    snapshot.data?.docs ??
                    <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                return ListView(
                  children: <Widget>[
                    for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
                        in docs)
                      ListTile(
                        title: Text('${doc['text']}'),
                        subtitle: Text(
                          doc.metadata.hasPendingWrites ? 'saving' : 'saved',
                        ),
                      ),
                  ],
                );
              },
        ),
      ),
    );
  }
}
