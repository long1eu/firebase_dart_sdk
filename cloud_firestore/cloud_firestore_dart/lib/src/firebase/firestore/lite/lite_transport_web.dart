// Only compiles for the web.

import 'package:cloud_firestore_dart/src/firebase/firestore/core/database_info.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/channel_options_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/firestore_transport.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/web/fetch_http_client.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/web/rest_transport.dart';

/// The transport of Firestore Lite on the web: REST over `fetch`, without
/// the WebChannel streams of the main library.
FirestoreTransport createLiteTransport(
  DatabaseInfo databaseInfo,
  ChannelOptionsProvider optionsProvider,
) => RestTransport(FetchHttpClient(), databaseInfo, optionsProvider);
