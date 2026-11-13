// Needs `dart:io`: only the io side of lite_transport.dart may import this
// file.

import 'package:cloud_firestore_dart/src/firebase/firestore/core/database_info.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/channel_options_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/firestore_transport.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/grpc_transport.dart';

/// The transport of Firestore Lite where there are sockets: gRPC, as the main
/// library.
FirestoreTransport createLiteTransport(
  DatabaseInfo databaseInfo,
  ChannelOptionsProvider optionsProvider,
) => createTransport(databaseInfo, optionsProvider);
