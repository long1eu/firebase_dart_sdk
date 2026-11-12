// Copyright 2021 Google LLC
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

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:_firebase_internal_vm/_firebase_internal_vm.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/bundle/bundle_document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/bundle/bundle_element.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/bundle/bundle_metadata.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/bundle/bundle_serializer.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/bundle/bundled_document_metadata.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/bundle/named_query.dart';

/// Reads the length-prefixed JSON stream for Bundles.
///
/// The class takes a bundle stream and presents abstractions to read bundled elements out of the underlying content.
/// A bundle is a sequence of elements, each encoded as the decimal byte length of its JSON string followed by that JSON
/// string (UTF-8). The first element is always the metadata.
///
/// The stream may deliver the bytes in chunks of any size: a chunk boundary can fall in the middle of a length prefix,
/// of a JSON string, or of a multi-byte UTF-8 character.
class BundleReader {
  BundleReader(this.serializer, Stream<List<int>> bundleStream)
      : _chunks = StreamIterator<List<int>>(bundleStream);

  /// Creates a reader over a bundle that is entirely available in memory.
  factory BundleReader.fromBytes(
      BundleSerializer serializer, List<int> bundleData) {
    return BundleReader(
        serializer, Stream<List<int>>.fromIterable(<List<int>>[bundleData]));
  }

  static const String _tag = 'BundleElement';

  /// The character that ends the length prefix (the first character of the JSON string).
  static const int _openBracket = 0x7B; // '{'

  final BundleSerializer serializer;
  final StreamIterator<List<int>> _chunks;

  BundleMetadata? _metadata;
  Uint8List _buffer = Uint8List(0);
  int _position = 0;
  int _bytesRead = 0;
  bool _closed = false;

  /// Returns the number of bytes processed so far.
  int get bytesRead => _bytesRead;

  /// Returns the metadata element from the bundle.
  Future<BundleMetadata> getBundleMetadata() async {
    final BundleMetadata? cached = _metadata;
    if (cached != null) {
      return cached;
    }
    final BundleElement? element = await _readNextElement();
    if (element is! BundleMetadata) {
      throw await _abort(
          'Expected first element in bundle to be a metadata object');
    }
    _metadata = element;
    // We don't consider the metadata as part of the bundle size, as it is used to encode the size of all remaining
    // elements.
    _bytesRead = 0;
    return element;
  }

  /// Returns the next element from the bundle, or null at the end of the bundle. The metadata element can be accessed
  /// by invoking [getBundleMetadata] and is not returned from this method.
  Future<BundleElement?> getNextElement() async {
    // Makes sure metadata is read before proceeding. The metadata element is the first element in the bundle stream.
    await getBundleMetadata();
    return _readNextElement();
  }

  /// Closes the underlying stream.
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _chunks.cancel();
  }

  /// Reads from the head of the internal buffer. Pulls more data from the underlying stream until a complete element
  /// is found (including the prefixed length and the JSON string).
  ///
  /// Once a complete element is read, it is dropped from the internal buffer.
  ///
  /// Returns either the bundled element, or null if we have reached the end of the stream.
  Future<BundleElement?> _readNextElement() async {
    final String? lengthPrefix = await _readLengthPrefix();
    if (lengthPrefix == null) {
      return null;
    }

    final int? jsonStringByteCount = int.tryParse(lengthPrefix);
    if (jsonStringByteCount == null || jsonStringByteCount < 0) {
      throw await _abort('Invalid length prefix: "$lengthPrefix"');
    }
    final String json = await _readJsonString(jsonStringByteCount);
    _bytesRead += utf8.encode(lengthPrefix).length + jsonStringByteCount;
    return _decodeBundleElement(json);
  }

  /// Reads the length prefix from the beginning of the internal buffer until the first '{'. Returns the length string.
  ///
  /// If it reached the end of the stream, returns null.
  Future<String?> _readLengthPrefix() async {
    int nextOpenBracket;

    while ((nextOpenBracket = _indexOfOpenBracket()) == -1) {
      if (!await _pullMoreData()) {
        break;
      }
    }

    // We broke out of the loop because the underlying stream is closed, and there happens to be no more data to
    // process.
    if (_remaining == 0) {
      return null;
    }

    // We broke out of the loop because the underlying stream is closed, but still cannot find an open bracket.
    if (nextOpenBracket == -1) {
      throw await _abort(
          'Reached the end of bundle when a length string is expected.');
    }

    final String prefix = utf8.decode(
        Uint8List.sublistView(_buffer, _position, _position + nextOpenBracket),
        allowMalformed: true);
    _position += nextOpenBracket;
    return prefix;
  }

  int get _remaining => _buffer.length - _position;

  /// Returns the offset (from the current position) of the first open bracket, or -1 if none is found.
  int _indexOfOpenBracket() {
    for (int i = _position; i < _buffer.length; i++) {
      if (_buffer[i] == _openBracket) {
        return i - _position;
      }
    }
    return -1;
  }

  /// Reads [bytesToRead] bytes from the internal buffer, pulling more data from the underlying stream if needed, and
  /// decodes them as UTF-8. The count is in bytes (not characters) so that multi-byte characters are handled.
  Future<String> _readJsonString(int bytesToRead) async {
    while (_remaining < bytesToRead) {
      if (!await _pullMoreData()) {
        throw await _abort(
            'Reached the end of bundle when more data was expected.');
      }
    }

    final Uint8List jsonBytes =
        Uint8List.sublistView(_buffer, _position, _position + bytesToRead);
    _position += bytesToRead;
    try {
      return utf8.decode(jsonBytes);
    } on FormatException catch (e) {
      throw await _abort('Invalid UTF-8 in element: ${e.message}');
    }
  }

  /// Pulls more data from the underlying stream into the internal buffer, dropping the bytes that were already
  /// consumed.
  ///
  /// Returns whether more data was read.
  Future<bool> _pullMoreData() async {
    if (_closed) {
      return false;
    }
    while (await _chunks.moveNext()) {
      final List<int> chunk = _chunks.current;
      if (chunk.isEmpty) {
        continue;
      }
      final Uint8List merged = Uint8List(_remaining + chunk.length)
        ..setRange(0, _remaining, _buffer, _position)
        ..setRange(_remaining, _remaining + chunk.length, chunk);
      _buffer = merged;
      _position = 0;
      return true;
    }
    return false;
  }

  /// Converts a JSON-encoded bundle element into its model class.
  Future<BundleElement> _decodeBundleElement(String json) async {
    final dynamic decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException catch (e) {
      throw await _abort('Cannot parse element as JSON: ${e.message}');
    }
    if (decoded is! Map<String, dynamic>) {
      throw await _abort('Cannot decode unknown Bundle element: $json');
    }

    if (decoded.containsKey('metadata')) {
      final BundleMetadata metadata = serializer
          .decodeBundleMetadata(decoded['metadata'] as Map<String, dynamic>);
      Log.d(_tag, 'BundleMetadata element loaded');
      return metadata;
    } else if (decoded.containsKey('namedQuery')) {
      final NamedQuery namedQuery = serializer
          .decodeNamedQuery(decoded['namedQuery'] as Map<String, dynamic>);
      Log.d(_tag, 'Query loaded: ${namedQuery.name}');
      return namedQuery;
    } else if (decoded.containsKey('documentMetadata')) {
      final BundledDocumentMetadata documentMetadata =
          serializer.decodeBundledDocumentMetadata(
              decoded['documentMetadata'] as Map<String, dynamic>);
      Log.d(_tag, 'Document metadata loaded: ${documentMetadata.key}');
      return documentMetadata;
    } else if (decoded.containsKey('document')) {
      final BundleDocument document = serializer
          .decodeDocument(decoded['document'] as Map<String, dynamic>);
      Log.d(_tag, 'Document loaded: ${document.key}');
      return document;
    } else {
      throw await _abort('Cannot decode unknown Bundle element: $json');
    }
  }

  /// Closes the underlying stream and returns an [ArgumentError] to be thrown by the caller.
  Future<ArgumentError> _abort(String message) async {
    await close();
    return ArgumentError('Invalid bundle: $message');
  }
}
