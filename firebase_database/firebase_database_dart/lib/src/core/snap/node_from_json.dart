/// JSON to node. JS: `core/snap/nodeFromJSON.ts`; Android: `snapshot/NodeUtilities.java`
/// (`NodeFromJSON`).
///
/// Node to JSON is [Node.toJson] (plain value and export form).
library;

import 'package:firebase_database_dart/src/core/snap/node.dart';

/// The node of [json] (export form accepted: `.priority`, `.value`; other keys starting with `.`
/// ignored), with [priority] when given.
Node nodeFromJson(Object? json, [Object? priority]) =>
    throw UnimplementedError();
