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

import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundle_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundle_element.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundle_metadata.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundle_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundled_document_metadata.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/named_query.dart';
import 'package:firebase_app_dart/internal.dart';

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
    BundleSerializer serializer,
    List<int> bundleData,
  ) {
    return BundleReader(
      serializer,
      Stream<List<int>>.fromIterable(<List<int>>[bundleData]),
    );
  }

  static const String _tag = 'BundleElement';

  /// The character that ends the length prefix (the first character of the JSON string).
  static const int _openBracket = 0x7B; // '{'

  /// The largest element (the JSON of one document, named query or metadata) the reader accepts, in bytes. A
  /// Firestore document is at most 1 MiB; its JSON form is a few times that at worst. A bundle is untrusted input,
  /// so a larger length prefix is rejected instead of buffering whatever the stream delivers.
  static const int maxElementBytes = 64 * 1024 * 1024;

  /// The longest length prefix: the decimal digits of [maxElementBytes], with room to spare.
  static const int _maxLengthPrefixBytes = 10;

  static final RegExp _decimal = RegExp(r'^[0-9]+$');

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
        'Expected first element in bundle to be a metadata object',
      );
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

    final int? jsonStringByteCount = _decimal.hasMatch(lengthPrefix)
        ? int.tryParse(lengthPrefix)
        : null;
    if (jsonStringByteCount == null) {
      throw await _abort('Invalid length prefix: "$lengthPrefix"');
    }
    if (jsonStringByteCount > maxElementBytes) {
      throw await _abort(
        'Element of $jsonStringByteCount bytes is larger than the limit of $maxElementBytes bytes',
      );
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
      if (_remaining > _maxLengthPrefixBytes) {
        // Not a length prefix: stop here rather than buffer the stream looking for a '{'.
        throw await _abort(
          'Expected a length prefix of at most $_maxLengthPrefixBytes digits.',
        );
      }
      if (!await _pullMoreData()) {
        break;
      }
    }
    if (nextOpenBracket > _maxLengthPrefixBytes) {
      throw await _abort(
        'Expected a length prefix of at most $_maxLengthPrefixBytes digits.',
      );
    }

    // We broke out of the loop because the underlying stream is closed, and there happens to be no more data to
    // process.
    if (_remaining == 0) {
      return null;
    }

    // We broke out of the loop because the underlying stream is closed, but still cannot find an open bracket.
    if (nextOpenBracket == -1) {
      throw await _abort(
        'Reached the end of bundle when a length string is expected.',
      );
    }

    final String prefix = utf8.decode(
      Uint8List.sublistView(_buffer, _position, _position + nextOpenBracket),
      allowMalformed: true,
    );
    _position += nextOpenBracket;
    return prefix;
  }

  int get _remaining => _buffer.length - _position;

  /// Returns the offset (from the current position) of the first open bracket, or -1 if none is found. Only looks as
  /// far as a length prefix can be long.
  int _indexOfOpenBracket() {
    final int end = _position + _maxLengthPrefixBytes + 1 < _buffer.length
        ? _position + _maxLengthPrefixBytes + 1
        : _buffer.length;
    for (int i = _position; i < end; i++) {
      if (_buffer[i] == _openBracket) {
        return i - _position;
      }
    }
    return -1;
  }

  /// Reads [bytesToRead] bytes from the internal buffer, pulling more data from the underlying stream if needed, and
  /// decodes them as UTF-8. The count is in bytes (not characters) so that multi-byte characters are handled.
  Future<String> _readJsonString(int bytesToRead) async {
    final Uint8List jsonBytes;
    if (_remaining >= bytesToRead) {
      jsonBytes = Uint8List.sublistView(
        _buffer,
        _position,
        _position + bytesToRead,
      );
      _position += bytesToRead;
    } else {
      // The element continues in later chunks: collect it into one buffer of its final size, so that every byte is
      // copied once however small the chunks are.
      final Uint8List target = Uint8List(bytesToRead);
      int filled = _remaining;
      target.setRange(0, filled, _buffer, _position);
      _buffer = Uint8List(0);
      _position = 0;
      while (filled < bytesToRead) {
        if (_closed || !await _chunks.moveNext()) {
          throw await _abort(
            'Reached the end of bundle when more data was expected.',
          );
        }
        final List<int> chunk = _chunks.current;
        final int take = chunk.length < bytesToRead - filled
            ? chunk.length
            : bytesToRead - filled;
        target.setRange(filled, filled + take, chunk);
        filled += take;
        if (take < chunk.length) {
          // The rest of the chunk belongs to the next element.
          _buffer = Uint8List.fromList(chunk.sublist(take));
        }
      }
      jsonBytes = target;
    }
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
      throw await _abort(
        'Cannot decode unknown Bundle element: ${_excerpt(json)}',
      );
    }

    try {
      if (decoded.containsKey('metadata')) {
        final BundleMetadata metadata = serializer.decodeBundleMetadata(
          _object(decoded, 'metadata'),
        );
        Log.d(_tag, 'BundleMetadata element loaded');
        return metadata;
      } else if (decoded.containsKey('namedQuery')) {
        final NamedQuery namedQuery = serializer.decodeNamedQuery(
          _object(decoded, 'namedQuery'),
        );
        Log.d(_tag, 'Query loaded: ${namedQuery.name}');
        return namedQuery;
      } else if (decoded.containsKey('documentMetadata')) {
        final BundledDocumentMetadata documentMetadata = serializer
            .decodeBundledDocumentMetadata(
              _object(decoded, 'documentMetadata'),
            );
        Log.d(_tag, 'Document metadata loaded: ${documentMetadata.key}');
        return documentMetadata;
      } else if (decoded.containsKey('document')) {
        final BundleDocument document = serializer.decodeDocument(
          _object(decoded, 'document'),
        );
        Log.d(_tag, 'Document loaded: ${document.key}');
        return document;
      }
    } on ArgumentError {
      await close();
      rethrow;
    } on TypeError catch (e) {
      // A field of another JSON type than the bundle format has there.
      throw await _abort('Malformed element: $e');
    }
    throw await _abort(
      'Cannot decode unknown Bundle element: ${_excerpt(json)}',
    );
  }

  static Map<String, dynamic> _object(
    Map<String, dynamic> element,
    String key,
  ) {
    final dynamic value = element[key];
    if (value is! Map<String, dynamic>) {
      throw ArgumentError('Invalid bundle: "$key" must be a JSON object');
    }
    return value;
  }

  /// The start of [json], for error messages: an element can be megabytes long.
  static String _excerpt(String json) => json.length <= 200
      ? json
      : '${json.substring(0, 200)}... (${json.length} characters)';

  /// Closes the underlying stream and returns an [ArgumentError] to be thrown by the caller.
  Future<ArgumentError> _abort(String message) async {
    await close();
    return ArgumentError('Invalid bundle: $message');
  }
}
