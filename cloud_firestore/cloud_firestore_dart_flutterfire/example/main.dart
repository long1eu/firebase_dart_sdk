// A Flutter app that signs in with the official firebase_auth plugin and
// reads and writes with cloud_firestore_dart, as the same user.
//
// Copy it into the lib/ of a Flutter app that depends on firebase_core,
// firebase_auth, cloud_firestore_dart and cloud_firestore_dart_flutterfire, and
// replace the options with those of your project (or with the
// DefaultFirebaseOptions.currentPlatform that `flutterfire configure` writes).
import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart_flutterfire/cloud_firestore_dart_flutterfire.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: '<the apiKey of your project>',
      appId: '1:1234567890:web:0123456789abcdef',
      messagingSenderId: '1234567890',
      projectId: 'my-project',
    ),
  );

  // The firebase_app_dart app, the token provider and the instance, in one call.
  final Firestore firestore = await FlutterFireBridge.firestore();
  runApp(VisitsApp(firestore: firestore));
}

/// Signs in anonymously with firebase_auth and counts the visits of the user in
/// the document `visits/<uid>`.
class VisitsApp extends StatelessWidget {
  /// Creates the app.
  const VisitsApp({super.key, required this.firestore});

  /// The instance made by [FlutterFireBridge.firestore].
  final Firestore firestore;

  Future<void> _visit() async {
    final FirebaseAuth auth = FirebaseAuth.instance;
    final User user =
        auth.currentUser ?? (await auth.signInAnonymously()).user!;
    // The write must belong to the new user: wait until Firestore follows it.
    await FlutterFireBridge.waitForCurrentUser();
    await firestore.doc('visits/${user.uid}').set(<String, Object?>{
      'count': FieldValue.increment(1),
    }, SetOptions.mergeAllFields);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Visits')),
        body: StreamBuilder<User?>(
          stream: FirebaseAuth.instance.authStateChanges(),
          builder: (BuildContext context, AsyncSnapshot<User?> auth) {
            final User? user = auth.data;
            if (user == null) {
              return const Center(child: Text('Not signed in'));
            }
            return StreamBuilder<DocumentSnapshot<Map<String, Object?>>>(
              stream: firestore.doc('visits/${user.uid}').snapshots,
              builder:
                  (
                    BuildContext context,
                    AsyncSnapshot<DocumentSnapshot<Map<String, Object?>>> doc,
                  ) {
                    final Object? count = doc.data?.get('count');
                    return Center(child: Text('Visits: ${count ?? 0}'));
                  },
            );
          },
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: _visit,
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}
