# firebase_database_dart_platform

> **Work in progress.** This version (0.0.1, not published) is the signature-only skeleton: the classes and their
> signatures are in place, the bodies are not written, and nothing has run yet.

An unofficial implementation of the platform interface of the official
[`firebase_database`](https://pub.dev/packages/firebase_database) Flutter plugin (13.1.0,
`firebase_database_platform_interface` 0.4.3+10), on top of `firebase_database_dart`, a pure-Dart client of the
Firebase Realtime Database. An app keeps the official API (`FirebaseDatabase.instance.ref('notes').onValue`,
`set`, `runTransaction`, ...) and the Dart client does the work underneath, without the native Firebase SDKs.

It is for a Flutter app on Linux desktop, where `firebase_database` and `firebase_core` have no implementation of
their own: adding the dependency registers it. On Windows, an app that lists it as a direct dependency gets it in
place of the native plugin (verified with stand-in plugins; a real Windows build is run before release). On the
other platforms it is an opt-in through `FirebaseDatabaseDart.use()`. Disk persistence is injected by the app
(`firebase_database_dart_sqlite`); without it the client keeps its data in memory.

It is not affiliated with or endorsed by Google or Firebase.
