import 'dart:convert';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

int _appCount = 0;

/// A new app with a unique name.
FirebaseApp newApp({String? projectId = 'demo-test'}) {
  return FirebaseApp.withOptions(
    FirebaseOptions(
      apiKey: 'app-key',
      appId: '1:123:dart:abc',
      projectId: projectId,
    ),
    name: 'error-reporting-test-${_appCount++}',
  );
}

/// An auth provider that hands out [tokens] in turn (the last one repeats) and records the `forceRefresh` of
/// each call. A null token means nobody is signed in.
class FakeAuth extends AuthTokenProvider {
  FakeAuth(this.tokens, {this.error});

  final List<String?> tokens;
  final Object? error;
  final List<bool> calls = <bool>[];

  @override
  Future<GetTokenResult> getAccessToken({required bool forceRefresh}) async {
    calls.add(forceRefresh);
    final Object? failure = error;
    if (failure != null) {
      return Future<Never>.error(failure);
    }
    final String? token =
        tokens[(calls.length - 1).clamp(0, tokens.length - 1)];
    if (token == null) {
      throw const FirebaseNoSignedInUserException('No user.');
    }
    return GetTokenResult(token);
  }

  @override
  String? get uid => null;

  @override
  Stream<AuthTokenChange> get onTokenChanged =>
      const Stream<AuthTokenChange>.empty();
}

/// An App Check provider with a fixed result, or one that throws [error].
class FakeAppCheck extends AppCheckTokenProvider {
  FakeAppCheck(this.result, {this.error});

  final AppCheckTokenResult result;
  final Object? error;

  @override
  Future<AppCheckTokenResult> getToken({required bool forceRefresh}) async {
    final Object? failure = error;
    if (failure != null) {
      return Future<Never>.error(failure);
    }
    return result;
  }

  @override
  Stream<AppCheckTokenResult> get onTokenChanged =>
      const Stream<AppCheckTokenResult>.empty();
}

/// A request a [Server] received.
final class Received {
  Received(this.url, this.headers, this.body);

  final Uri url;
  final Map<String, String> headers;
  final Map<String, Object?> body;

  String get message => body['message']! as String;
}

/// A `MockClient` that answers with `statuses` in turn (the last one repeats) and records the requests.
class Server {
  Server([List<int> statuses = const <int>[200]]) : _statuses = statuses;

  final List<int> _statuses;
  final List<Received> requests = <Received>[];
  Map<String, String> responseHeaders = const <String, String>{};
  String responseBody = '{}';

  late final http.Client client = MockClient((http.Request request) async {
    requests.add(
      Received(
        request.url,
        request.headers,
        jsonDecode(request.body) as Map<String, Object?>,
      ),
    );
    final int status =
        _statuses[(requests.length - 1).clamp(0, _statuses.length - 1)];
    return http.Response(responseBody, status, headers: responseHeaders);
  });
}

/// A VM stack trace of an invented app, as Dart prints it.
final StackTrace appStack = StackTrace.fromString('''
#0      ListBase.first (dart:collection/list.dart:79:5)
#1      NoteRepository.load (package:notes/src/repository.dart:42:7)
<asynchronous suspension>
#2      NoteListModel.refresh (package:notes/src/model.dart:88:12)
#3      main (package:notes/main.dart:12:3)
''');
