// File created by
// Lung Razvan <long1eu>
// on 16/09/2018

import 'package:firebase_common/src/annotations.dart';
import 'package:firebase_common/src/firebase_options.dart';
import 'package:firebase_common/src/firebase_app.dart';

/// A observer which gets notified when [FirebaseApp] gets deleted.
// TODO: consider making it public in a future release.
@keepForSdk
abstract class FirebaseAppLifecycleObserver {
  /// Gets called when [FirebaseApp.delete] is called. [FirebaseApp] public
  /// methods start throwing after delete is called, so name and options are
  /// passed in to be able to identify the instance.
  void onDeleted(String firebaseAppName, FirebaseOptions options);
}
