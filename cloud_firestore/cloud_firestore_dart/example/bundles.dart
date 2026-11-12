// Data bundles: load documents and named queries that a server prepared into
// the local cache, and read them without a query to the backend.
//
// Bundles are built by a server SDK (for example `firestore.bundle()` in the
// Node.js Admin SDK) and usually served from a CDN. This example builds a
// tiny one by hand so that it is self-contained.
//
//     FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 dart run example/bundles.dart

import 'dart:convert';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';

import 'common.dart';

/// A bundle is a sequence of length-prefixed JSON elements: the metadata,
/// then named queries and documents.
List<int> buildBundle() {
  const String root = 'projects/$projectId/databases/(default)/documents';
  const String readTime = '{"seconds":1000,"nanos":0}';
  final List<String> elements = <String>[
    '{"namedQuery":{"name":"latest-stories","readTime":$readTime,'
        '"bundledQuery":{"parent":"$root","structuredQuery":{'
        '"from":[{"collectionId":"bundled-stories"}],'
        '"orderBy":[{"field":{"fieldPath":"published"},"direction":"DESCENDING"},'
        '{"field":{"fieldPath":"__name__"},"direction":"DESCENDING"}],'
        '"limit":{"value":1}},"limitType":"FIRST"}}}',
    for (final (String id, int published) in <(String, int)>[
      ('first', 1),
      ('second', 2),
    ]) ...<String>[
      '{"documentMetadata":{"name":"$root/bundled-stories/$id",'
          '"readTime":$readTime,"exists":true}}',
      '{"document":{"name":"$root/bundled-stories/$id",'
          '"createTime":{"seconds":1,"nanos":0},'
          '"updateTime":{"seconds":1,"nanos":0},"fields":{'
          '"title":{"stringValue":"Story $id"},'
          '"published":{"integerValue":$published}}}}',
    ],
  ];
  final String body = <String>[
    for (final String element in elements)
      '${utf8.encode(element).length}$element',
  ].join();
  final String metadata =
      '{"metadata":{"id":"example-bundle",'
      '"createTime":{"seconds":1001,"nanos":0},"version":1,'
      '"totalDocuments":2,"totalBytes":${utf8.encode(body).length}}}';
  return utf8.encode('${utf8.encode(metadata).length}$metadata$body');
}

Future<void> main() async {
  final Firestore firestore = await connect();

  // loadBundle takes the bytes; loadBundleStream takes a stream of chunks
  // (for example the body of an HTTP response).
  final LoadBundleTask task = firestore.loadBundle(buildBundle());
  task.stream.listen((LoadBundleTaskProgress progress) {
    print(
      'progress: ${progress.taskState.name} '
      '${progress.documentsLoaded}/${progress.totalDocuments} documents',
    );
  });
  final LoadBundleTaskProgress result = await task.future;
  print(
    'loaded ${result.documentsLoaded} documents, '
    '${result.bytesLoaded} bytes',
  );

  // The documents are now in the cache.
  final QuerySnapshot<Map<String, Object?>> cached = await firestore
      .collection('bundled-stories')
      .get(Source.cache);
  print('cached: ${<Object?>[for (final doc in cached.docs) doc['title']]}');

  // A named query is a query the server stored in the bundle with its result.
  final Query<Map<String, Object?>>? latest = await firestore.getNamedQuery(
    'latest-stories',
  );
  final QuerySnapshot<Map<String, Object?>> latestStories = await latest!.get(
    Source.cache,
  );
  print('latest: ${latestStories.docs.single['title']}');

  await firestore.terminate();
}
