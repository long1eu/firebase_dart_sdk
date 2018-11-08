// File created by
// Lung Razvan <long1eu>
// on 23/10/2018

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_common/firebase_common.dart';
import 'package:firebase_storage/src/network/network_request.dart';
import 'package:meta/meta.dart';
import 'package:mockito/mockito.dart';
import 'package:rxdart/rxdart.dart';
import 'package:test/test.dart';

class TestHttpClientProvider implements HttpClientProviderImpl {
  static const String _tag = 'TestHttpClientProvider';

  final bool _binaryBody;

  Completer<void> completer;
  MockHttpClientRequest requestMock;
  MockHttpClientResponse responseMock;

  List<String> verifications = <String>[];
  int count = 0;

  Stream<List<int>> _file;
  int pauseRecord = 9223372036854775807;
  int _currentRecord = 0;

  TestHttpClientProvider({@required String testName, @required bool isBinary})
      : _binaryBody = isBinary,
        _file = _getResFile('$testName\_network.txt');

  static Stream<List<int>> _getResFile(String fileName) {
    return File('${Directory.current.path}/test/res/assets/$fileName')
        .openRead();
  }

  @override
  Future<HttpClient> client(String method, Uri url) async {
    final Completer<MockHttpClient> fileCompleter = Completer<MockHttpClient>();
    Log.d(
        _tag, 'client called with: method:[$method], url:[$url] $requestMock');
    //verifyOldMock();

    final MockHttpClient mock = MockHttpClient();

    completer = Completer<void>();
    requestMock = MockHttpClientRequest();
    when(requestMock.method).thenReturn(method);
    when(requestMock.headers).thenReturn(MockHeaders(<String, List<String>>{}));

    responseMock = MockHttpClientResponse();

    final Map<String, List<String>> headers = <String, List<String>>{};
    final MockHeaders responseHeaders = MockHeaders(headers);

    _file.transform(utf8.decoder).transform(const LineSplitter()).listen(
        (String line) {
      count++;

      if (line == '<new>') {
        return;
      }

      Log.d(_tag, line.padRight(200).substring(0, 200));

      final int colon = line.indexOf(':');
      if (colon == -1) {
        return;
      }

      String key = line.substring(0, colon);
      String value = line.substring(colon + 1);

      if (key == 'Url') {
        expect(url.toString(), value);
      } else if (key == 'setRequestMethod') {
        expect(method, value);
      } else if (key == 'close') {
        if (value == 'Exception') {
          when(requestMock.close())
              .thenThrow(Exception('Exception thrown by mock'));
        } else {
          when(requestMock.close()).thenAnswer((_) async => responseMock);
        }
        verifications.add(line);
      } else if (key == 'getResponseCode') {
        when(responseMock.statusCode).thenReturn(int.parse(value));
      } else if (key == 'getHeaderFields') {
        when(responseMock.headers).thenReturn(responseHeaders);
      } else if (key == 'getInputStream') {
        List<dynamic> responseData;
        bool injectException = false;

        if (value.endsWith(':Exception')) {
          value = value.substring(0, value.lastIndexOf(':Exception'));
          injectException = true;
        }

        if (_binaryBody) {
          responseData = base64Decode(value);
        } else {
          responseData = utf8.encode(value);
        }

        Log.d(_tag, 'Returning byte count: ${responseData.length}');
        if (injectException) {
          responseData.insert(responseData.length, 'Exception');
        }

        responseMock._controller
          ..add(responseData)
          ..close();
      } else if (key.codeUnitAt(0) == /*' '*/ 0x20) {
        key = key.substring(1);
        value = value.substring(1, value.length - 1);
        if (key == 'Content-Length') {
          final int integerLength = int.parse(value);
          when(responseMock.contentLength).thenReturn(integerLength);
        } else if (key == 'Content-Type') {
          when(responseHeaders.contentType)
              .thenReturn(ContentType.parse(value));
        }
        headers[key] = <String>[value];
      } else {
        verifications.add(line);
      }
    }, onError: (dynamic e) {
      Log.d(_tag, '**** Error at line: $count: ${e.runtimeType}/$e');
      throw e;
    }, onDone: () => fileCompleter.complete(mock));

    when(mock.openUrl(
            argThat(anyOf('GET', 'DELETE', 'POST', 'PATCH', 'PUT')), any))
        .thenAnswer((_) async => requestMock);

    _currentRecord++;

    return fileCompleter.future;
  }

  @override
  Future<void> close() {
    print('close');
    verifyOldMock();
    return _currentRecord == pauseRecord
        ? completer.future
        : Future<void>.value();
  }

  void verifyOldMock() {
    if (requestMock == null || verifications.isEmpty) {
      return;
    }
    Log.d(_tag, 'verifyOldMock running');
    final List<String> requestPropertyKeys = <String>[];
    final List<String> requestPropertyValues = <String>[];

    try {
      final MockHeaders mockHeaders = requestMock.headers;
      for (String line in verifications) {
        final int colon = line.indexOf(':');
        if (colon == -1) {
          break;
        }
        String key = line.substring(0, colon);
        String value = line.substring(colon + 1);

        if (key == 'setRequestProperty') {
          final int comma = value.indexOf(',');
          if (comma != -1) {
            key = value.substring(0, comma);
            value = value.substring(comma + 1);
            requestPropertyKeys.add(key);
            requestPropertyValues.add(value);
          }
        } else if (key == 'close') {
          verify(requestMock.close()).called(1);
        }
      }

      for (int i = 0; i < requestPropertyKeys.length; i++) {
        final bool exists =
            mockHeaders._headers.containsKey(requestPropertyKeys[i]);
        expect(exists, isTrue);

        expect(mockHeaders._headers[requestPropertyKeys[i]].first,
            requestPropertyValues[i],
            reason: 'Request property differs for: ${requestPropertyKeys[i]}');
      }
    } catch (e) {
      Log.d(
          _tag, '**********Error in network Line: $count: ${e.runtimeType}/$e');

      if (e is NoSuchMethodError) {
        print(e.stackTrace);
      }

      rethrow;
    }

    requestMock = null;
    responseMock = null;
    completer = null;
    verifications.clear();
  }
}

class MockHttpClient extends Mock implements HttpClient {}

class MockHttpClientRequest extends Mock implements HttpClientRequest {}

class MockHttpClientResponse extends Mock implements HttpClientResponse {
  final StreamController<List<dynamic>> _controller;

  MockHttpClientResponse() : _controller = StreamController<List<dynamic>>();

  Stream<List<int>> get _builtStream =>
      Observable<List<dynamic>>(_controller.stream) //
          .expand<dynamic>((List<dynamic> data) => data)
          .map<dynamic>((dynamic it) {
            if (it == 'Exception') {
              throw Exception('Exception thrown by mock');
            }

            return it;
          })
          .cast<int>()
          .toList()
          .asStream();

  @override
  Stream<S> expand<S>(Iterable<S> Function(List<int> element) convert) {
    return _builtStream.expand<S>(convert);
  }

  @override
  StreamSubscription<List<int>> listen(void Function(List<int> event) onData,
      {Function onError, void Function() onDone, bool cancelOnError}) {
    return _builtStream.listen(onData,
        onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }
}

class MockHeaders extends Mock implements HttpHeaders {
  final Map<String, List<String>> _headers;

  MockHeaders(this._headers);

  @override
  void forEach(void f(String name, List<String> values)) => _headers.forEach(f);

  @override
  void add(String name, Object value) {
    if (_headers[name] == null) {
      _headers[name] = <String>['$value'];
    } else {
      _headers[name].add('$value');
    }
  }
}
