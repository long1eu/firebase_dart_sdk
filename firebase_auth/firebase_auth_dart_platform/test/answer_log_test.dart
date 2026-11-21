import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'real_project/answer_log.dart';

void main() {
  test('describeAnswer names the fields and never their values', () {
    final String line = describeAnswer(
      utf8.encode(
        jsonEncode(<String, Object?>{
          'mfaPendingCredential': 'secret-pending',
          'localId': 'secret-uid',
          'mfaInfo': <Object?>[
            <String, Object?>{'phoneInfo': '+1555', 'mfaEnrollmentId': 'id'},
          ],
        }),
      ),
    );
    expect(
      line,
      'localId, mfaInfo[mfaEnrollmentId phoneInfo], mfaPendingCredential',
    );
    expect(
      describeAnswer(utf8.encode('{"error":{"message":"INVALID_CODE"}}')),
      'error(INVALID_CODE)',
    );
    expect(describeAnswer(utf8.encode('<html>')), 'not JSON');
  });

  test('AnswerLoggingClient logs Identity Toolkit answers and passes the '
      'body on', () async {
    final List<String> lines = <String>[];
    final http.Client client = AnswerLoggingClient(
      MockClient(
        (http.Request r) async => http.Response('{"idToken":"t"}', 200),
      ),
      lines.add,
    );
    final http.Response answer = await client.post(
      Uri.parse(
        'https://identitytoolkit.googleapis.com/v1/accounts:signInWithIdp?key=k',
      ),
    );
    expect(answer.body, '{"idToken":"t"}');
    expect(lines, <String>['  [answer] accounts:signInWithIdp 200: idToken']);
    await client.get(Uri.parse('https://securetoken.googleapis.com/v1/token'));
    expect(lines, hasLength(1));
  });
}
