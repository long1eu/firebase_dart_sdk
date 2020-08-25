// File created by
// Lung Razvan <long1eu>
// on 18/09/2018

import 'package:cloud_firestore_vm/src/firebase/firestore/document_snapshot.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/query.dart';

/// Indicates whether metadata-only changes (i.e. only [DocumentSnapshot.metadata] or
/// [Query.metadata] changed) should trigger snapshot events.
enum MetadataChanges { exclude, include }
