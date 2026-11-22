// Helpers shared by the conformance tests (test/conformance). Not a test.
import 'dart:convert';

import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/children_node.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/snap/node_from_json.dart';

/// A path of a path string.
Path p(String path) => Path(path);

/// A child key.
ChildKey ck(String name) => ChildKey(name);

/// The node of [json] with the optional [priority].
Node n(Object? json, [Object? priority]) => nodeFromJson(json, priority);

/// The empty node.
Node get emptyNode => ChildrenNode.empty;

/// Decodes JSON written with single quotes (upstream `fromSingleQuotedString`).
Object? sq(String json) => jsonDecode(json.replaceAll("'", '"'));

/// The node of single-quoted JSON.
Node nq(String json) => n(sq(json));
