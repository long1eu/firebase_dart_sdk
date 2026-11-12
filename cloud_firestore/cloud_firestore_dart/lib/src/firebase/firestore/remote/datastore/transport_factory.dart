/// Picks the [FirestoreTransport] of the platform, so that the libraries
/// above it never import `dart:io`.
library;

export 'transport_factory_unsupported.dart'
    if (dart.library.io) 'grpc_transport.dart'
    if (dart.library.js_interop) 'web/web_transport_factory.dart'
    show createTransport;
