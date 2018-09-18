// File created by
// Lung Razvan <long1eu>
// on 18/09/2018

import 'package:firebase_common/firebase_common.dart';

/// Indicates whether metadata-only changes (i.e. only
/// [DocumentSnapshot.getMetadata()] or [Query.getMetadata()] changed) should
/// trigger snapshot events.
@publicApi
enum MetadataChanges { EXCLUDE, INCLUDE }
