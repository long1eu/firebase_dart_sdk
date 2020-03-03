// File created by
// Lung Razvan <long1eu>
// on 20/10/2018

import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage_vm/src/internal/slash_util.dart';
import 'package:firebase_storage_vm/src/network/network_request.dart';

const String _tag = 'StorageUtil';
const int _maximumTokenWaitTimeMs = 30000;
const int kNetworkUnavailable = -2;

int parseDateTime(String dateString) {
  if (dateString == null) {
    return 0;
  }

  try {
    return DateTime.parse(dateString).millisecondsSinceEpoch;
  } on FormatException catch (_) {
    Log.w(_tag, 'unable to parse datetime: $dateString');
  }

  return 0;
}

/// Null-safe equivalent of {@code a.equals(b)}. */
bool equals(Object a, Object b) {
  return a == b || a != null && a == b;
}

String getAuthority() => NetworkRequest.authority;

/// Normalizes a Firebase Storage uri into its 'gs://' format and strips any
/// trailing slash.
Uri normalize(FirebaseApp app, String s) {
  if (s == null || s.isEmpty) {
    return null;
  }

  const String invalidUrlMessage = 'Firebase Storage URLs must point to an '
      'object in your Storage Bucket. Please obtain a URL using the Firebase '
      'Console or getDownloadUrl().';

  final String trimmedInput = s.toLowerCase();
  String bucket;
  String encodedPath;
  if (trimmedInput.startsWith('gs://')) {
    final String fullUri =
        preserveSlashEncode(normalizeSlashes(s.substring(5)));
    return Uri.parse('gs://$fullUri');
  } else {
    final Uri uri = Uri.parse(s);
    final String scheme = uri.scheme;

    if (scheme != null &&
        (equals(scheme.toLowerCase(), 'http') ||
            equals(scheme.toLowerCase(), 'https'))) {
      final String lowerAuthority = uri.authority.toLowerCase();
      int indexOfAuth;
      try {
        indexOfAuth = lowerAuthority.indexOf(getAuthority());
      } catch (e) {
        throw const FormatException('Could not parse Url because the '
            'Storage network layer did not load');
      }
      encodedPath = slashize(uri.path);
      if (indexOfAuth == 0 && encodedPath.startsWith('/')) {
        final int firstBSlash =
            encodedPath.indexOf('/b/', 0); // /v0/b/bucket.storage
        // .firebase.com/o/child/image.png
        final int endBSlash = encodedPath.indexOf('/', firstBSlash + 3);
        final int firstOSlash = encodedPath.indexOf('/o/', 0);
        if (firstBSlash != -1 && endBSlash != -1) {
          bucket = encodedPath.substring(firstBSlash + 3, endBSlash);
          if (firstOSlash != -1) {
            encodedPath = encodedPath.substring(firstOSlash + 3);
          } else {
            encodedPath = '';
          }
        } else {
          Log.w(_tag, invalidUrlMessage);
          throw ArgumentError(invalidUrlMessage);
        }
      } else if (indexOfAuth > 1) {
        bucket = uri.authority.substring(0, indexOfAuth - 1);
      } else {
        Log.w(_tag, invalidUrlMessage);
        throw ArgumentError(invalidUrlMessage);
      }
    } else {
      Log.w(_tag, 'FirebaseStorage is unable to support the scheme: $scheme');
      throw ArgumentError('Uri scheme');
    }
  }

  Preconditions.checkNotEmpty(bucket, 'No bucket specified');

  return Uri.parse('gs://$bucket/$encodedPath');
}

Future<String> getCurrentAuthToken(FirebaseApp app) {
  return app.getAuthProvider
      .getAccessToken(false)
      .timeout(const Duration(milliseconds: _maximumTokenWaitTimeMs))
      .then((GetTokenResult result) {
    if (result.token != null && result.token.isNotEmpty) {
      return result.token;
    } else {
      Log.w(_tag, 'no auth token for request');
      return null;
    }
  }).catchError((dynamic e) => Log.e('StorageUtil', 'error getting token $e'));
}
