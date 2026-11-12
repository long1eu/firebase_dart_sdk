// The transport factory for the web. Only compiles for the web.

import 'package:cloud_firestore_dart/src/firebase/firestore/core/database_info.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/channel_options_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/firestore_transport.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/web/fetch_http_client.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/web/web_channel_transport.dart';

/// Creates the transport of this platform: REST and WebChannel over `fetch`.
FirestoreTransport createTransport(
    DatabaseInfo databaseInfo, ChannelOptionsProvider optionsProvider) {
  return WebChannelTransport(FetchHttpClient(), databaseInfo, optionsProvider);
}
