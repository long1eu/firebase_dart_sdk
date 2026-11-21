/// Helpers of the conformance suite: the tests of this folder port the unit tests of the JS SDK
/// (`packages/storage/test/unit/*.test.ts`) to the public API, and name the JS case they pin.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_storage_dart/src/version.dart';
import 'package:test/test.dart';

import '../fakes.dart';

/// The app id of [newApp], sent as `X-Firebase-GMPID`.
const String appId = '1:123:dart:abc';

/// The production origin of the REST API.
const String prod = 'https://firebasestorage.googleapis.com';

/// The headers of [request] with lower-case names, so that a test can compare the whole set.
Map<String, String> headersOf(Recorded request) => <String, String>{
  for (final MapEntry<String, String> entry in request.headers.entries)
    entry.key.toLowerCase(): entry.value,
};

/// The headers every request carries (the JS SDK adds the same from `makeRequest`, except `X-Firebase-GMPID`,
/// which it never sends), plus [extra] with lower-case names.
Map<String, String> commonHeaders([
  Map<String, String> extra = const <String, String>{},
]) => <String, String>{
  'x-firebase-gmpid': appId,
  'x-firebase-storage-version': 'dart/$packageVersion',
  ...extra,
};

/// Expects [request] to be exactly [method] [url] with exactly [headers] (lower-case names) and [body].
void expectRequest(
  Recorded request, {
  required String method,
  required String url,
  required Map<String, String> headers,
  String body = '',
}) {
  expect(request.method, method, reason: 'method');
  expect(request.url.toString(), url, reason: 'url');
  expect(headersOf(request), headers, reason: 'headers');
  expect(request.body, body, reason: 'body');
}

/// The two parts of a multipart upload body: the boundary, the metadata JSON, the content type of the data
/// part and the data bytes. Fails the test when the body does not have the exact layout of the JS SDK.
({String boundary, String metadata, String contentType, Uint8List data})
multipartParts(Recorded request) {
  final RegExpMatch? header = RegExp(
    r'^multipart/related; boundary=([A-Za-z0-9]+)$',
  ).firstMatch(headersOf(request)['content-type'] ?? '');
  expect(header, isNotNull, reason: 'multipart content type');
  final String boundary = header!.group(1)!;
  final List<int> bytes = request.bodyBytes;
  final String head = latin1.decode(bytes);
  final RegExpMatch? layout = RegExp(
    '^--$boundary\r\n'
    'Content-Type: application/json; charset=utf-8\r\n'
    '\r\n'
    '(.*)\r\n'
    '--$boundary\r\n'
    'Content-Type: ([^\r]*)\r\n'
    '\r\n',
    dotAll: true,
  ).firstMatch(head);
  expect(layout, isNotNull, reason: 'multipart layout: $head');
  final String tail = '\r\n--$boundary--';
  expect(head.endsWith(tail), isTrue, reason: 'multipart closing boundary');
  return (
    boundary: boundary,
    metadata: utf8.decode(latin1.encode(layout!.group(1)!)),
    contentType: layout.group(2)!,
    data: Uint8List.fromList(
      bytes.sublist(layout.end, bytes.length - tail.length),
    ),
  );
}
