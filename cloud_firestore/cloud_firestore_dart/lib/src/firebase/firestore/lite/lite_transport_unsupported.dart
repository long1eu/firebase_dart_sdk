import 'package:cloud_firestore_dart/src/firebase/firestore/core/database_info.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/channel_options_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/firestore_transport.dart';

/// There is no transport for this platform.
FirestoreTransport createLiteTransport(
  DatabaseInfo databaseInfo,
  ChannelOptionsProvider optionsProvider,
) {
  throw UnsupportedError(
    'Cloud Firestore has no network transport for this platform.',
  );
}
