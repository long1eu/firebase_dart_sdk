// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of firebase_auth;

const String sdkVersion = '0.0.1';

/// Adds 'key' query parameter when making HTTP requests.
///
/// If 'key' is already present on the URI, it will complete with an exception.
/// This will prevent accidental overrides of a query parameter with the API key.
class ApiKeyClient extends DelegatingClient {
  ApiKeyClient(String apiKey, this._headers, {Client client})
      : _encodedApiKey = Uri.encodeQueryComponent(apiKey),
        super(client ?? Client(), closeUnderlyingClient: true);

  final String _encodedApiKey;
  final HeaderBuilder _headers;

  String locale;

  @override
  Future<StreamedResponse> send(BaseRequest request) async {
    Uri url = request.url;
    if (url.queryParameters.containsKey('key')) {
      return Future<StreamedResponse>.error(Exception(
          'Tried to make a HTTP request which has already a "key" query parameter. Adding the API key would override that existing value.'));
    }

    if (url.queryParameters.isEmpty) {
      url = url.replace(queryParameters: <String, String>{'key': _encodedApiKey});
    } else {
      url = url.replace(queryParameters: <String, String>{...url.queryParameters, 'key': _encodedApiKey});
    }

    final RequestImpl modifiedRequest = RequestImpl(request.method, url, request.finalize());
    final Map<String, String> headers = <String, String>{
      ...request.headers,
      if (_headers != null) ..._headers() ?? <String, String>{},
      if (locale != null) 'X-Firebase-Locale': locale,
      'X-Client-Version': '${Platform.operatingSystem}/FirebaseSDK/$sdkVersion/dart',
    };
    modifiedRequest.headers.addAll(headers);

    final StreamedResponse response = await baseClient.send(modifiedRequest);
    return _validateResponse(response);
  }
}

/// Base class for delegating HTTP clients.
///
/// Depending on [closeUnderlyingClient] it will close the client it is delegating to or not.
abstract class DelegatingClient extends BaseClient {
  DelegatingClient(this.baseClient, {this.closeUnderlyingClient = true});

  final Client baseClient;
  final bool closeUnderlyingClient;
  bool _isClosed = false;

  @override
  void close() {
    if (_isClosed) {
      throw StateError('Cannot close a HTTP client more than once.');
    }
    _isClosed = true;
    super.close();

    if (closeUnderlyingClient) {
      baseClient.close();
    }
  }
}

class RequestImpl extends BaseRequest {
  RequestImpl(String method, Uri url, [Stream<List<int>> stream])
      : _stream = stream ?? Stream<List<int>>.fromIterable(<List<int>>[]),
        super(method, url);

  final Stream<List<int>> _stream;

  @override
  ByteStream finalize() {
    super.finalize();
    if (_stream == null) {
      return null;
    }
    return ByteStream(_stream);
  }
}

Future<StreamedResponse> _validateResponse(StreamedResponse response) async {
  final int statusCode = response.statusCode;

  if (statusCode < 200 || statusCode >= 400) {
    // Some error happened, try to decode the response and fetch the error.
    final Stream<String> stringStream = _decodeStreamAsText(response);
    if (stringStream != null) {
      final dynamic jsonResponse = await stringStream.transform(json.decoder).first;
      if (jsonResponse is Map && jsonResponse['error'] is Map) {
        final Map<dynamic, dynamic> error = jsonResponse['error'];
        final dynamic codeValue = error['code'];
        String message = error['message'];
        message = message.split(' : ')[0];

        throw FirebaseAuthError(message, '');
      }
    }
  }

  return response;
}

Stream<String> _decodeStreamAsText(StreamedResponse response) {
  // TODO(long1eu): Correctly handle the response content-types, using correct decoder.
  // Currently we assume that the api endpoint is responding with json encoded in UTF8.
  final String contentType = response.headers['content-type'];
  if (contentType != null && contentType.toLowerCase().startsWith('application/json')) {
    return response.stream.transform(const Utf8Decoder(allowMalformed: true));
  } else {
    return null;
  }
}
