// File created by
// Lung Razvan <long1eu>
// on 20/10/2018

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_common/firebase_common.dart';
import 'package:firebase_storage_vm/src/firebase_storage.dart';
import 'package:firebase_storage/src/internal/slash_util.dart';
import 'package:firebase_storage/src/internal/version.dart';
import 'package:firebase_storage/src/storage_exception.dart';
import 'package:meta/meta.dart';

/// Encapsulates a single network request and response
abstract class NetworkRequest {
  NetworkRequest(this.gsUri, FirebaseApp app)
      : assert(gsUri != null),
        assert(app != null) {
    setCustomHeader(_xFirebaseGmpid, app.options.applicationId);
  }

  static const String _tag = 'NetworkRequest';

  static const String _xFirebaseGmpid = 'x-firebase-gmpid';

  // Do not change these values without changing corresponding logic on the SDK
  // side
  static const int initializationException = -1;
  static const int networkUnavailable = -2;

  static const String _contentType = 'Content-Type';
  static const String _applicationJson = 'application/json';
  static const String _contentLength = 'Content-Length';
  static const String networkRequestUrl =
      'https://firebasestorage.googleapis.com/v0';
  static const String uploadUrl =
      'https://firebasestorage.googleapis.com/v0/b/';

  @visibleForTesting
  static HttpClientProvider clientProvider = const HttpClientProviderImpl();

  final Uri gsUri;

  /// @return an error representing the reason the REST call failed.
  dynamic error;

  /// The HTTP status code of the REST call.
  int resultCode;
  String rawResponse;
  int resultingContentLength;

  HttpClientRequest _request;
  HttpClientResponse _response;
  final Map<String, String> _requestHeaders = <String, String>{};
  Map<String, List<String>> _resultHeaders;

  static String get authority {
    final Uri uri = Uri.parse(networkRequestUrl);
    return uri.authority;
  }

  /// Returns the target Url to use for this request
  static String getDefaultUrl(Uri gsUri) {
    Preconditions.checkNotNull(gsUri);

    final String pathWithoutBucket = getPathWithoutBucket(gsUri);
    final String path =
        pathWithoutBucket != null ? unSlashize(pathWithoutBucket) : '';
    return '$networkRequestUrl/b/${gsUri.authority}/o/$path';
  }

  /// Returns the path of the object but excludes the bucket name
  ///
  /// [gsUri] is the 'gs://' uri of the blob.
  static String getPathWithoutBucket(Uri gsUri) {
    String path = gsUri.path;
    if (path != null && path.startsWith('/')) {
      // this should always be true.
      path = path.substring(1);
    }
    return path;
  }

  String get action;

  /// Returns the target url to use for this request
  String get url => getDefaultUrl(gsUri);

  /// Returns the path of the object but excludes the bucket name
  String get pathWithoutBucket => getPathWithoutBucket(gsUri);

  /// Can be overridden to return a Map to populate the request body.
  Map<String, dynamic> get outputJson => null;

  /// Can be overridden to return a byte array to populate the request body.
  /*protected*/
  Uint8List get outputRaw => null;

  /// There are cases where a large [Uint8List] is sent for the body, but only a
  /// portion is actually sent to the server.
  ///
  /// Returns the count of bytes to send from [outputRaw].
  int get outputRawSize => 0;

  /// If overridden, returns the query parameters to send on the REST request.
  String get queryParameters => null;

  /// Resets the result of this request
  void reset() {
    error = null;
    resultCode = 0;
  }

  void setCustomHeader(String key, String value) {
    _requestHeaders[key] = value;
  }

  Stream<List<int>> get stream => _response;

  /// Returns the resulting body in Map form, if it could be parsed.
  Map<String, dynamic> get resultBody {
    Map<String, dynamic> resultBody;
    if (rawResponse != null && rawResponse.isNotEmpty) {
      try {
        final Map<String, dynamic> _resultBody =
            jsonDecode(rawResponse).cast<String, dynamic>();
        resultBody = _resultBody;
      } catch (e) {
        Log.e(_tag, 'error parsing result into JSON: $rawResponse');

        resultBody = <String, dynamic>{};
      }
    } else {
      resultBody = <String, dynamic>{};
    }
    return resultBody;
  }

  Future<void> performRequestStart(String token) async {
    if (error != null) {
      resultCode = initializationException;
      return;
    }

    Log.d(_tag, 'sending network request $action $url');

    if (!(await FirebaseStorage.instance.isNetworkConnected())) {
      resultCode = networkUnavailable;
      error = const SocketException('Network subsystem is unavailable');
      return;
    }

    try {
      _request = await _createConnection();

      _addMessage(_request, token);
      final HttpClientResponse response = await _request.close();
      _parseResponse(response);

      Log.d(_tag, 'network request result $resultCode');
    } catch (e) {
      print('#error performRequestStart: $e ${e.stackTrace}');
      Log.w(_tag, 'error sending network request $action $url');

      error = e;
      resultCode = networkUnavailable;
    }
  }

  /// Sends the REST network request.
  Future<void> _performRequest(String token) async {
    await performRequestStart(token);
    try {
      await _parseResponseStream();
    } catch (e) {
      print('#error _performRequest: $e ${e.stackTrace}');
      Log.w(_tag, 'error sending network request $action $url');

      error = e;
      resultCode = networkUnavailable;
      rethrow;
    }

    await clientProvider.close();
  }

  Future<void> performRequest(String authToken) async {
    if (!(await _ensureNetworkAvailable())) {
      return;
    }
    await _performRequest(authToken);
  }

  Future<bool> _ensureNetworkAvailable() async {
    if (!(await FirebaseStorage.instance.isNetworkConnected())) {
      error = const SocketException('Network subsystem is unavailable');
      resultCode = networkUnavailable;
      return false;
    }
    return true;
  }

  Future<HttpClientRequest> _createConnection() async {
    String urlString;
    final String queryParams = queryParameters;
    if (queryParams == null || queryParams.isEmpty) {
      urlString = url;
    } else {
      urlString = '$url?$queryParams';
    }

    final Uri uri = Uri.parse(urlString);
    return (await clientProvider.client(action, uri)).openUrl(action, uri);
  }

  void _addMessage(HttpClientRequest request, String token) {
    Preconditions.checkNotNull(request);

    if (token != null && token.isNotEmpty) {
      request.headers.add('Authorization', 'Firebase $token');
    } else {
      Log.w(_tag, 'no auth token for request');
    }

    final StringBuffer userAgent = StringBuffer('dart/${Version.sdkVersion}');
    request.headers.add('X-Firebase-Storage-Version', userAgent.toString());

    final Map<String, String> requestProperties = _requestHeaders;
    for (MapEntry<String, String> entry in requestProperties.entries) {
      request.headers.add(entry.key, entry.value);
    }

    final Map<String, dynamic> jsonObject = outputJson;
    List<int> rawOutput;
    int rawSize;

    if (jsonObject != null) {
      rawOutput = utf8.encode(jsonObject.toString());
      rawSize = rawOutput.length;
    } else {
      rawOutput = outputRaw;
      rawSize = outputRawSize;
      if (rawSize == 0 && rawOutput != null) {
        rawSize = rawOutput.length;
      }
    }

    if (rawOutput != null && rawOutput.isNotEmpty) {
      if (jsonObject != null) {
        request.headers.add(_contentType, _applicationJson);
      }
      request.headers.add(_contentLength, rawSize);
    } else {
      request.headers.add(_contentLength, '0');
    }

    if (rawOutput != null && rawOutput.isNotEmpty) {
      request.add(rawOutput);
    }
  }

  void _parseResponse(HttpClientResponse response) {
    Preconditions.checkNotNull(response);
    final Map<String, List<String>> headers = <String, List<String>>{};
    response.headers
        .forEach((String key, List<String> value) => headers[key] = value);

    resultCode = response.statusCode;
    _resultHeaders = headers;
    resultingContentLength = response.contentLength;
    _response = response;
  }

  Future<void> _parseResponseStream() async {
    final Stream<String> stream = _response.transform(utf8.decoder);
    rawResponse = stream != null ? await stream.first : null;
    //print('#rawResponse: $rawResponse');

    if (!isResultSuccess) {
      error = Exception(rawResponse);
    }
  }

  /// Returns true if successful, false if an exception was thrown or the server
  /// returns a result code indicating an error.
  bool get isResultSuccess => resultCode >= 200 && resultCode < 300;

  String getPostDataString(
      {@required List<String> keys,
      @required List<String> values,
      @required bool encode}) {
    if (keys == null || keys.isEmpty) {
      return null;
    }

    if (values == null || values.length != keys.length) {
      throw StateError('invalid key/value pairing');
    }

    final StringBuffer result = StringBuffer();
    bool first = true;
    for (int i = 0; i < keys.length; i++) {
      if (first) {
        first = false;
      } else {
        result.write('&');
      }

      result
        ..write(encode ? Uri.encodeComponent(keys[i]) : keys[i])
        ..write('=')
        ..write(encode ? Uri.encodeComponent(values[i]) : values[i]);
    }

    return result.toString();
  }

  String getResultString(String key) {
    if (_resultHeaders != null) {
      final List<String> urlList = _resultHeaders[key];
      if (urlList != null && urlList.isNotEmpty) {
        return urlList.first;
      }
    }
    return null;
  }

  void completeTask<TResult>(Completer<TResult> source, TResult result) {
    if (isResultSuccess && error == null) {
      source.complete(result);
    } else {
      final StorageException se =
          StorageException.fromExceptionAndHttpCode(error, resultCode);
      assert(se != null);
      source.completeError(se);
    }
  }
}

abstract class HttpClientProvider {
  Future<HttpClient> client(String method, Uri uri);

  Future<void> close();
}

class HttpClientProviderImpl implements HttpClientProvider {
  const HttpClientProviderImpl();

  @override
  Future<HttpClient> client(String method, Uri uri) =>
      Future<HttpClient>.value(HttpClient());

  @override
  Future<void> close() => Future<void>.value();
}
