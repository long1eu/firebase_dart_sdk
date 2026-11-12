// Names used by the Android SDK and the current official Firestore API, kept as
// aliases of the existing classes so both spellings are the same type.

import 'package:cloud_firestore_vm/src/firebase/firestore/firestore.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/firestore_settings.dart';

/// Alias of [Firestore]: the name used by the Android SDK and by the official
/// Flutter plugin. Constructors, static members and subclassing work through
/// the alias because both names denote the same class.
typedef FirebaseFirestore = Firestore;

/// Alias of [FirestoreSettings] (official name: `Settings`).
typedef Settings = FirestoreSettings;
