import 'package:firebase_data_connect_dart/src/transport/rest/rest_transport.dart';
import 'package:firebase_data_connect_dart/src/transport/transport.dart';

/// The transport of [config] on the web: the REST transport.
OperationTransport createTransport(TransportConfig config) =>
    RestTransport(config);
