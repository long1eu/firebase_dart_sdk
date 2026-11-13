// Copyright 2025 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

/// JSON serialization of [DocumentSnapshot] and [QuerySnapshot], and listening from a serialized snapshot.
///
/// Port of the JS SDK `DocumentSnapshot.toJSON()`, `QuerySnapshot.toJSON()`, `documentSnapshotFromJSON()`,
/// `querySnapshotFromJSON()` and `onSnapshotResume()`. The JSON object holds the snapshot as a Firestore bundle string
/// (the format of `Firestore.loadBundle`), so it is interchangeable with the one of the JS SDK (Node).
library;

import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundle_builder.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundle_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundle_metadata.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundle_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundled_document_metadata.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/named_query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart'
    as core;
import 'package:cloud_firestore_dart/src/firebase/firestore/core/view_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/document_reference.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/document_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_data_converter.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_error.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_set.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/query_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/snapshot_listen_options.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/util.dart';

const String _documentSource = 'DocumentSnapshot';
const String _querySource = 'QuerySnapshot';

/// The bundle the JS SDK writes in place of the data when it serializes a snapshot outside of Node.
const String _notSupported = 'NOT SUPPORTED';

/// Returns the JSON of the snapshot of the document [key], which is [document] (null when missing).
Map<String, Object?> documentSnapshotToJson(
  Firestore firestore,
  DocumentKey key,
  Document? document,
  bool hasPendingWrites,
) {
  if (hasPendingWrites) {
    throw FirestoreError(
      'DocumentSnapshot.toJson() attempted to serialize a document with pending writes. '
      'Await waitForPendingWrites() before invoking toJson().',
      FirestoreErrorCode.failedPrecondition,
    );
  }
  String bundle = '';
  if (document != null) {
    final BundleBuilder builder = BundleBuilder(
      RemoteSerializer(firestore.modelDatabaseId),
      autoId(),
    )..addDocument(document);
    bundle = builder.build();
  }
  return <String, Object?>{
    'type': DocumentSnapshot.jsonType,
    'bundle': bundle,
    'bundleSource': _documentSource,
    'bundleName': key.path.canonicalString,
  };
}

/// Returns the JSON of the query snapshot [snapshot].
Map<String, Object?> querySnapshotToJson(
  Firestore firestore,
  ViewSnapshot snapshot,
) {
  if (snapshot.hasPendingWrites) {
    throw FirestoreError(
      'QuerySnapshot.toJson() attempted to serialize a document with pending writes. '
      'Await waitForPendingWrites() before invoking toJson().',
      FirestoreErrorCode.failedPrecondition,
    );
  }
  final String bundleName = autoId();
  final BundleBuilder builder =
      BundleBuilder(RemoteSerializer(firestore.modelDatabaseId), bundleName)
        ..addNamedQuery(
          bundleName,
          snapshot.query,
          snapshot.documents,
          snapshot.readTime,
        );
  return <String, Object?>{
    'type': QuerySnapshot.jsonType,
    'bundleSource': _querySource,
    'bundleName': bundleName,
    'bundle': builder.build(),
  };
}

/// Builds the [DocumentSnapshot] serialized in [json] by [DocumentSnapshot.toJson].
DocumentSnapshot<T> documentSnapshotFromJson<T>(
  Firestore firestore,
  Map<String, Object?> json,
  FirestoreDataConverter<T>? converter,
) {
  final _SnapshotJson parsed = _SnapshotJson.validate(
    json,
    DocumentSnapshot.jsonType,
    _documentSource,
  );
  final DocumentKey key = _documentKey(parsed.bundleName);
  if (parsed.bundle.isEmpty) {
    // PORTING NOTE: toJson() of a missing document writes an empty bundle, which the JS SDK fails to parse. The port
    // reads it back as the missing document.
    return DocumentSnapshotInternal.fromNoDocument<T>(
      firestore,
      key,
      isFromCache: false,
      hasPendingWrites: false,
      converter: converter,
    );
  }

  final _ParsedBundle bundle = _ParsedBundle.parse(firestore, parsed.bundle);
  if (bundle.documents.length != 1) {
    throw FirestoreError(
      'Expected bundle data to contain 1 document, but it contains ${bundle.documents.length} documents.',
      FirestoreErrorCode.invalidArgument,
    );
  }
  final Document document = bundle.documents.single;
  if (document.key != key) {
    throw FirestoreError(
      'The bundle holds the document ${document.key.path}, but the snapshot is of ${key.path}.',
      FirestoreErrorCode.invalidArgument,
    );
  }
  return DocumentSnapshotInternal.fromDocument<T>(
    firestore,
    document,
    isFromCache: false,
    hasPendingWrites: false,
    converter: converter,
  );
}

/// Builds the [QuerySnapshot] serialized in [json] by [QuerySnapshot.toJson].
QuerySnapshot<T> querySnapshotFromJson<T>(
  Firestore firestore,
  Map<String, Object?> json,
  FirestoreDataConverter<T>? converter,
) {
  final _SnapshotJson parsed = _SnapshotJson.validate(
    json,
    QuerySnapshot.jsonType,
    _querySource,
  );
  final _ParsedBundle bundle = _ParsedBundle.parse(firestore, parsed.bundle);
  if (bundle.queries.length != 1) {
    throw FirestoreError(
      'Snapshot data expected 1 query but found ${bundle.queries.length} queries.',
      FirestoreErrorCode.invalidArgument,
    );
  }
  final NamedQuery namedQuery = bundle.queries.single;
  final core.Query query = namedQuery.bundledQuery.toQuery();

  DocumentSet documents = DocumentSet.emptySet(query.comparator);
  for (final Document document in bundle.documents) {
    documents = documents.add(document);
  }
  final ViewSnapshot snapshot = ViewSnapshot.fromInitialDocuments(
    query,
    documents,
    DocumentKey.emptyKeySet, // No mutated keys: no pending writes.
    isFromCache: false,
    excludesMetadataChanges: false,
    hasCachedResults: false,
    readTime: namedQuery.readTime,
  );
  return QuerySnapshotInternal.create<T>(
    QueryInternal.create<T>(query, firestore, converter),
    snapshot,
    firestore,
  );
}

/// Loads the bundle of a [DocumentSnapshot.toJson] result and listens to the document from there.
Stream<DocumentSnapshot<T>> documentSnapshotsFromJson<T>(
  Firestore firestore,
  Map<String, Object?> json,
  SnapshotListenOptions options,
  FirestoreDataConverter<T>? converter,
) {
  final _SnapshotJson parsed = _SnapshotJson.forResume(json, _documentSource);
  final DocumentKey key = _documentKey(parsed.bundleName);
  final DocumentReference<T> reference = DocumentReferenceInternal.create<T>(
    key,
    firestore,
    converter,
  );
  if (parsed.bundle.isEmpty) {
    // The document was missing: there is nothing to load.
    return reference.getSnapshotsWithOptions(options);
  }
  return _resume<DocumentSnapshot<T>>(firestore, parsed.bundle, () async {
    return reference.getSnapshotsWithOptions(options);
  });
}

/// Loads the bundle of a [QuerySnapshot.toJson] result and listens to its query from there.
Stream<QuerySnapshot<T>> querySnapshotsFromJson<T>(
  Firestore firestore,
  Map<String, Object?> json,
  SnapshotListenOptions options,
  FirestoreDataConverter<T>? converter,
) {
  final _SnapshotJson parsed = _SnapshotJson.forResume(json, _querySource);
  if (parsed.bundle.isEmpty) {
    throw FirestoreError(
      "snapshotJson field 'bundle' cannot be an empty string.",
      FirestoreErrorCode.invalidArgument,
    );
  }
  return _resume<QuerySnapshot<T>>(firestore, parsed.bundle, () async {
    final Query<Map<String, Object?>>? namedQuery = await firestore
        .getNamedQuery(parsed.bundleName);
    if (namedQuery == null) {
      throw FirestoreError(
        'The bundle does not contain the query ${parsed.bundleName}.',
        FirestoreErrorCode.invalidArgument,
      );
    }
    return QueryInternal.create<T>(
      namedQuery.query,
      firestore,
      converter,
    ).getSnapshotsWithOptions(options);
  });
}

/// Returns a stream that loads [bundle] into the cache when listened to, and then forwards the events of the stream
/// returned by [listen].
Stream<S> _resume<S>(
  Firestore firestore,
  String bundle,
  Future<Stream<S>> Function() listen,
) {
  late StreamController<S> controller;
  StreamSubscription<S>? subscription;
  bool cancelled = false;

  Future<void> start() async {
    try {
      await firestore.loadBundle(utf8.encode(bundle)).future;
      if (cancelled) {
        return;
      }
      final Stream<S> stream = await listen();
      if (cancelled) {
        return;
      }
      subscription = stream.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
      if (controller.isPaused) {
        subscription!.pause();
      }
    } catch (error, stackTrace) {
      if (!cancelled) {
        controller.addError(error, stackTrace);
        unawaited(controller.close());
      }
    }
  }

  controller = StreamController<S>(
    onListen: start,
    onPause: () => subscription?.pause(),
    onResume: () => subscription?.resume(),
    onCancel: () {
      cancelled = true;
      return subscription?.cancel();
    },
  );
  return controller.stream;
}

DocumentKey _documentKey(String path) {
  final ResourcePath resourcePath = ResourcePath.fromString(path);
  if (resourcePath.length == 0 || !DocumentKey.isDocumentKey(resourcePath)) {
    throw FirestoreError(
      "The JSON field 'bundleName' must be a document path, but was '$path'.",
      FirestoreErrorCode.invalidArgument,
    );
  }
  return DocumentKey.fromPath(resourcePath);
}

/// The validated fields of a snapshot JSON object.
class _SnapshotJson {
  _SnapshotJson(this.bundleName, this.bundle);

  /// Validates [json] like the JS `validateJSON()` with the snapshot schema.
  factory _SnapshotJson.validate(
    Map<String, Object?> json,
    String type,
    String source,
  ) {
    final Map<String, String?> schema = <String, String?>{
      'type': type,
      'bundleSource': source,
      'bundleName': null,
      'bundle': null,
    };
    for (final MapEntry<String, String?> field in schema.entries) {
      if (!json.containsKey(field.key)) {
        throw FirestoreError(
          "JSON missing required field: '${field.key}'",
          FirestoreErrorCode.invalidArgument,
        );
      }
      final Object? value = json[field.key];
      if (value is! String) {
        throw FirestoreError(
          "JSON field '${field.key}' must be a string.",
          FirestoreErrorCode.invalidArgument,
        );
      }
      if (field.value != null && value != field.value) {
        throw FirestoreError(
          "Expected '${field.key}' field to equal '${field.value}'",
          FirestoreErrorCode.invalidArgument,
        );
      }
    }
    final String bundle = json['bundle']! as String;
    if (bundle == _notSupported) {
      throw FirestoreError(
        'The provided JSON object was created in a client environment, which is not supported.',
        FirestoreErrorCode.invalidArgument,
      );
    }
    return _SnapshotJson(json['bundleName']! as String, bundle);
  }

  /// Validates [json] like the JS `onSnapshotResume()` (which does not check the `type`).
  factory _SnapshotJson.forResume(Map<String, Object?> json, String source) {
    for (final String key in <String>['bundle', 'bundleName', 'bundleSource']) {
      if (!json.containsKey(key)) {
        throw FirestoreError(
          'snapshotJson missing required field: $key',
          FirestoreErrorCode.invalidArgument,
        );
      }
      final Object? value = json[key];
      if (value is! String) {
        throw FirestoreError(
          "snapshotJson field '$key' must be a string.",
          FirestoreErrorCode.invalidArgument,
        );
      }
      // PORTING NOTE: the JS SDK also rejects an empty 'bundle', which toJSON() writes for a missing document. The
      // port listens to that document directly instead; a query snapshot always has a bundle.
      if (value.isEmpty && key != 'bundle') {
        throw FirestoreError(
          "snapshotJson field '$key' cannot be an empty string.",
          FirestoreErrorCode.invalidArgument,
        );
      }
    }
    if (json['bundleSource'] != source) {
      throw FirestoreError(
        "Expected 'bundleSource' field to equal '$source', but was '${json['bundleSource']}'.",
        FirestoreErrorCode.invalidArgument,
      );
    }
    final String bundle = json['bundle']! as String;
    if (bundle == _notSupported) {
      throw FirestoreError(
        'The provided JSON object was created in a client environment, which is not supported.',
        FirestoreErrorCode.invalidArgument,
      );
    }
    return _SnapshotJson(json['bundleName']! as String, bundle);
  }

  final String bundleName;
  final String bundle;
}

/// The elements of a bundle held in memory, read synchronously (the JS `BundleReaderSync`).
class _ParsedBundle {
  _ParsedBundle(this.queries, this.documents);

  factory _ParsedBundle.parse(Firestore firestore, String bundle) {
    final BundleSerializer serializer = BundleSerializer(
      RemoteSerializer(firestore.modelDatabaseId),
    );
    final List<NamedQuery> queries = <NamedQuery>[];
    final List<Document> documents = <Document>[];
    try {
      final List<int> bytes = utf8.encode(bundle);
      int position = 0;
      bool first = true;
      while (position < bytes.length) {
        final int openBracket = bytes.indexOf(0x7B /* { */, position);
        if (openBracket == -1) {
          throw const FormatException(
            'Reached the end of bundle when a length string is expected.',
          );
        }
        final String prefix = utf8.decode(
          bytes.sublist(position, openBracket),
          allowMalformed: true,
        );
        // Plain decimal digits, as BundleReader requires: int.tryParse also
        // takes signs, white space and hexadecimal.
        final int? length = _lengthPrefix.hasMatch(prefix)
            ? int.tryParse(prefix)
            : null;
        if (length == null) {
          throw FormatException('Invalid length prefix: "${_excerpt(prefix)}"');
        }
        final int end = openBracket + length;
        if (end > bytes.length) {
          throw const FormatException(
            'Reached the end of bundle when more data was expected.',
          );
        }
        final Object? element = jsonDecode(
          utf8.decode(bytes.sublist(openBracket, end)),
        );
        position = end;
        if (element is! Map<String, dynamic>) {
          throw FormatException(
            'Cannot decode unknown Bundle element: ${_excerpt('$element')}',
          );
        }

        if (first) {
          if (!element.containsKey('metadata')) {
            throw const FormatException(
              'Expected first element in bundle to be a metadata object',
            );
          }
          final BundleMetadata _ = serializer.decodeBundleMetadata(
            element['metadata'] as Map<String, dynamic>,
          );
          first = false;
        } else if (element.containsKey('namedQuery')) {
          queries.add(
            serializer.decodeNamedQuery(
              element['namedQuery'] as Map<String, dynamic>,
            ),
          );
        } else if (element.containsKey('documentMetadata')) {
          final BundledDocumentMetadata _ = serializer
              .decodeBundledDocumentMetadata(
                element['documentMetadata'] as Map<String, dynamic>,
              );
        } else if (element.containsKey('document')) {
          final BundleDocument document = serializer.decodeDocument(
            element['document'] as Map<String, dynamic>,
          );
          documents.add(document.document);
        } else {
          throw FormatException(
            'Cannot decode unknown Bundle element: ${_excerpt('$element')}',
          );
        }
      }
      if (first) {
        throw const FormatException(
          'Expected first element in bundle to be a metadata object',
        );
      }
    } on FirestoreError {
      rethrow;
    } on Object catch (e) {
      // The error may repeat the input, which can be megabytes long.
      throw FirestoreError(
        'Invalid snapshot bundle: ${_excerpt('$e')}',
        FirestoreErrorCode.invalidArgument,
        e,
      );
    }
    return _ParsedBundle(queries, documents);
  }

  static final RegExp _lengthPrefix = RegExp(r'^[0-9]{1,10}$');

  /// The start of [text], for error messages.
  static String _excerpt(String text) => text.length <= 200
      ? text
      : '${text.substring(0, 200)}... (${text.length} characters)';

  final List<NamedQuery> queries;
  final List<Document> documents;
}
