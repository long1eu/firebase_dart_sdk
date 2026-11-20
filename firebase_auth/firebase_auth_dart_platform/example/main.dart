// A Flutter app that uses the official firebase_auth API, with
// firebase_auth_providers_dart doing the work underneath.
//
// On Linux the FirebaseAuthDart.use() call is optional: Flutter registers the
// package before main() runs. On the other platforms it replaces the official
// implementation. Run it against an emulator started with
// `firebase emulators:start --only auth` (project demo-test).

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_dart_platform/firebase_auth_dart_platform.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FirebaseAuthDart.use();
  await Firebase.initializeApp(
    // Use your own options (flutterfire configure) for a real project.
    options: const FirebaseOptions(
      apiKey: 'demo-api-key',
      appId: '1:1:web:1',
      messagingSenderId: '1',
      projectId: 'demo-test',
    ),
  );
  await FirebaseAuth.instance.useAuthEmulator('127.0.0.1', 9099);
  runApp(const SignInApp());
}

class SignInApp extends StatelessWidget {
  const SignInApp({super.key});

  @override
  Widget build(BuildContext context) {
    final FirebaseAuth auth = FirebaseAuth.instance;
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Sign-in')),
        body: StreamBuilder<User?>(
          // Starts with the user restored from the previous run, if any.
          stream: auth.authStateChanges(),
          builder: (BuildContext context, AsyncSnapshot<User?> snapshot) {
            final User? user = snapshot.data;
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(user == null ? 'Signed out' : 'Signed in: ${user.uid}'),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () async {
                      try {
                        if (user == null) {
                          await auth.signInAnonymously();
                        } else {
                          await auth.signOut();
                        }
                      } on FirebaseAuthException catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('${e.code}: ${e.message}')),
                          );
                        }
                      }
                    },
                    child: Text(user == null ? 'Sign in' : 'Sign out'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
