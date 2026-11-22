/// Size estimate of a node's JSON. JS: none; Android: `core/utilities/NodeSizeEstimator.java`.
library;

import 'package:firebase_database_dart/src/core/snap/node.dart';

/// The estimated size in bytes of [node] serialised as JSON (decides whether a listen sends a
/// compound hash).
int estimateSerializedNodeSize(Node node) => throw UnimplementedError();

/// The number of leaves of [node].
int nodeCount(Node node) => throw UnimplementedError();
