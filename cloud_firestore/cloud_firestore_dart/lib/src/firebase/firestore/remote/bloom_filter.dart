// Copyright 2023 Google LLC
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

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

/// Thrown by [BloomFilter.create] if the given arguments are not valid.
class BloomFilterCreateException implements Exception {
  BloomFilterCreateException(this.message);

  final String message;

  @override
  String toString() => 'BloomFilterCreateException: $message';
}

/// A read-only bloom filter that matches the filter the backend sends in the
/// `unchanged_names` field of an existence filter.
///
/// Strings are hashed with MD5 (UTF-8 bytes). The 16 byte digest is read as two
/// little endian unsigned 64 bit integers `h1` and `h2`; the bit that the i-th
/// hash function checks is `(h1 + i * h2) mod bitCount`, with the arithmetic
/// done modulo 2^64 on unsigned values. Bit `n` lives in `bitmap[n ~/ 8]` at
/// position `n % 8` (least significant bit first).
class BloomFilter {
  /// Creates a new [BloomFilter] with the given parameters.
  ///
  /// [padding] is the number of unused bits in the last byte of [bitmap], it
  /// must be between 0 and 7 (inclusive) and 0 if [bitmap] is empty.
  /// [hashCount] must be greater than zero unless [bitmap] is empty, in which
  /// case it may be zero. Throws an [ArgumentError] otherwise.
  BloomFilter(this._bitmap, int padding, this._hashCount)
      : _bitCount = _bitmap.length * 8 - padding {
    final String? error = _validate(_bitmap, padding, _hashCount);
    if (error != null) {
      throw ArgumentError(error);
    }
  }

  /// Creates a [BloomFilter] with the given arguments, throwing a
  /// [BloomFilterCreateException] if they do not satisfy the requirements
  /// documented on the [BloomFilter] constructor.
  factory BloomFilter.create(Uint8List bitmap, int padding, int hashCount) {
    final String? error = _validate(bitmap, padding, hashCount);
    if (error != null) {
      throw BloomFilterCreateException(error);
    }
    return BloomFilter(bitmap, padding, hashCount);
  }

  final Uint8List _bitmap;
  final int _hashCount;
  final int _bitCount;

  /// The number of bits that are in use in the bitmap.
  int get bitCount => _bitCount;

  static String? _validate(Uint8List bitmap, int padding, int hashCount) {
    if (padding < 0 || padding >= 8) {
      return 'Invalid padding: $padding';
    }
    if (hashCount < 0) {
      return 'Invalid hash count: $hashCount';
    }
    if (bitmap.isNotEmpty && hashCount == 0) {
      // Only an empty bloom filter can have a hash count of 0.
      return 'Invalid hash count: $hashCount';
    }
    if (bitmap.isEmpty && padding != 0) {
      // An empty bloom filter must have no padding.
      return 'Expected padding of 0 when bitmap length is 0, but got $padding';
    }
    return null;
  }

  /// Checks whether the given [value] is a possible member of the bloom filter.
  ///
  /// May return a false positive (`true` for a value that was never added), but
  /// never a false negative.
  bool mightContain(String value) {
    // An empty bitmap contains nothing.
    if (_bitCount == 0) {
      return false;
    }

    final List<int> digest = crypto.md5.convert(utf8.encode(value)).bytes;
    if (digest.length != 16) {
      throw StateError(
          'Invalid md5 hash array length: ${digest.length} (expected 16)');
    }

    final int hash1 = _getLongLittleEndian(digest, 0);
    final int hash2 = _getLongLittleEndian(digest, 8);

    for (int i = 0; i < _hashCount; i++) {
      if (!_isBitSet(_getBitIndex(hash1, hash2, i))) {
        return false;
      }
    }
    return true;
  }

  /// Interprets 8 bytes as a little endian 64 bit integer.
  static int _getLongLittleEndian(List<int> bytes, int offset) {
    int result = 0;
    for (int i = 0; i < 8; i++) {
      result |= (bytes[offset + i] & 0xFF) << (i * 8);
    }
    return result;
  }

  /// Returns the index of the bit the [hashIndex]-th hash function checks.
  int _getBitIndex(int hash1, int hash2, int hashIndex) {
    // h(i) = h1 + i * h2. The hashes are unsigned 64 bit values; addition and
    // multiplication wrap around in the same way for signed and unsigned ints.
    final int combinedHash = hash1 + hash2 * hashIndex;
    return _unsignedRemainder(combinedHash, _bitCount);
  }

  /// Computes `dividend mod divisor`, treating both as unsigned 64 bit values.
  /// [divisor] must be positive.
  static int _unsignedRemainder(int dividend, int divisor) {
    final int quotient = ((dividend >>> 1) ~/ divisor) << 1;
    final int remainder = dividend - quotient * divisor;
    return remainder - (remainder >= divisor ? divisor : 0);
  }

  bool _isBitSet(int index) {
    final int byteAtIndex = _bitmap[index ~/ 8];
    return (byteAtIndex & (0x01 << (index % 8))) != 0;
  }

  @override
  String toString() {
    return 'BloomFilter{hashCount=$_hashCount, size=$_bitCount, '
        'bitmap="${base64.encode(_bitmap)}"}';
  }
}
