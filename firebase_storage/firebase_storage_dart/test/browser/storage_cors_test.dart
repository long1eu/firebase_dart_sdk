@TestOn('browser')
@Tags(<String>['browser'])
library;

import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'emulator_port.dart';

/// The resumable protocol only works in a browser when its response headers are readable from
/// JS. The JS SDK reads X-Goog-Upload-URL, X-Goog-Upload-Status and X-Goog-Upload-Size-Received
/// (and sends X-Goog-Upload-Protocol, -Command, -Offset, -Header-Content-Length and
/// -Header-Content-Type), so these have to be in Access-Control-Expose-Headers of the answers.
/// Production's firebasestorage.googleapis.com exposes the same set; this test pins what the
/// emulator does, which is what the other browser tests depend on.
void main() {
  setUpAll(loadEmulatorPort);

  test('the resumable start answer exposes X-Goog-Upload-* to JS', () async {
    final http.Client client = http.Client(); // BrowserClient: fetch
    addTearDown(client.close);
    final Uri start = Uri.parse(
      'http://$emulatorHost/v0/b/demo-test.appspot.com/o'
      '?name=browser-test%2Fcors-${DateTime.now().microsecondsSinceEpoch}.bin',
    );
    final http.Response response = await client.post(
      start,
      headers: <String, String>{
        'X-Goog-Upload-Protocol': 'resumable',
        'X-Goog-Upload-Command': 'start',
        'X-Goog-Upload-Header-Content-Length': '3',
        'X-Goog-Upload-Header-Content-Type': 'application/octet-stream',
        'Content-Type': 'application/json; charset=utf-8',
      },
      body: '{"name":"x"}',
    );
    expect(response.statusCode, 200);
    // fetch hides every header that is not CORS-safelisted or exposed.
    expect(response.headers['x-goog-upload-status'], 'active');
    final String? uploadUrl = response.headers['x-goog-upload-url'];
    expect(uploadUrl, isNotNull);

    final http.Response query = await client.post(
      Uri.parse(uploadUrl!),
      headers: <String, String>{'X-Goog-Upload-Command': 'query'},
    );
    expect(query.statusCode, 200);
    expect(query.headers['x-goog-upload-status'], 'active');
    expect(query.headers['x-goog-upload-size-received'], '0');
  });
}
