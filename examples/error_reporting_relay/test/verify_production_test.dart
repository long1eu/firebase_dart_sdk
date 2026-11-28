// The kit against a fake Error Reporting: which outcome each answer gives. No request leaves the process.

import 'dart:convert';

import 'package:error_reporting_relay/verify_production.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

const KitConfig _full = KitConfig(
  projectId: 'demo-test',
  accessToken: 'ya29.kit-token',
  apiKey: 'AIzaKitKey',
  otherApiKey: 'AIzaOtherKey',
  runTag: 'abc234',
);

void main() {
  late List<http.Request> requests;

  /// A fake that accepts the token and the kit key, and refuses the other key with 403.
  http.Client fake({int okStatus = 200}) =>
      MockClient((http.Request request) async {
        requests.add(request);
        if (request.url.queryParameters['key'] == 'AIzaOtherKey') {
          return http.Response(
            '{"error":{"code":403,"message":"API key not valid for this API"}}',
            403,
          );
        }
        return http.Response('{}', okStatus);
      });

  setUp(() => requests = <http.Request>[]);

  test(
    'every check passes against a backend that behaves as documented',
    () async {
      final List<CheckResult> results = await runKit(_full, client: fake());
      expect(
        <String, Outcome>{for (final CheckResult r in results) r.id: r.outcome},
        <String, Outcome>{
          'direct-api-key': Outcome.pass,
          'direct-token-v8': Outcome.pass,
          'direct-token-dart': Outcome.pass,
          'direct-token-fatal': Outcome.pass,
          'relay': Outcome.pass,
          'refused-key': Outcome.pass,
        },
      );
      final List<Map<String, Object?>> bodies = <Map<String, Object?>>[
        for (final http.Request r in requests)
          jsonDecode(r.body) as Map<String, Object?>,
      ];
      for (final Map<String, Object?> body in bodies) {
        expect(body['serviceContext'], <String, Object?>{
          'service': kitService,
          'version': 'abc234',
        });
      }
      // The relay forwarded with the token, to the project's endpoint.
      expect(
        requests.where(
          (http.Request r) =>
              r.headers['authorization'] == 'Bearer ya29.kit-token',
        ),
        hasLength(4),
      );
      expect(
        requests.every(
          (http.Request r) =>
              r.url.path == '/v1beta1/projects/demo-test/events:report',
        ),
        isTrue,
      );
    },
  );

  test('a backend that refuses everything fails the delivery checks', () async {
    final List<CheckResult> results = await runKit(
      _full,
      client: fake(okStatus: 400),
    );
    expect(
      results.firstWhere((CheckResult r) => r.id == 'direct-api-key').outcome,
      Outcome.fail,
    );
    expect(
      results.firstWhere((CheckResult r) => r.id == 'relay').outcome,
      isNot(Outcome.pass),
    );
  });

  test('a backend that takes the other key fails the refusal check', () async {
    final List<CheckResult> results = await runKit(
      _full,
      client: MockClient(
        (http.Request request) async => http.Response('{}', 200),
      ),
    );
    expect(
      results.firstWhere((CheckResult r) => r.id == 'refused-key').outcome,
      Outcome.fail,
    );
  });

  test('checks without their credential are skipped', () async {
    final List<CheckResult> results = await runKit(
      const KitConfig(
        projectId: 'demo-test',
        apiKey: 'AIzaKitKey',
        runTag: 'abc234',
      ),
      client: fake(),
    );
    expect(
      results
          .where((CheckResult r) => r.outcome == Outcome.skipped)
          .map((CheckResult r) => r.id),
      <String>[
        'direct-token-v8',
        'direct-token-dart',
        'direct-token-fatal',
        'relay',
        'refused-key',
      ],
    );
  });

  test('no result or log line holds a credential', () async {
    final List<String> lines = <String>[];
    final List<CheckResult> results = await runKit(
      _full,
      client: fake(okStatus: 400),
      log: lines.add,
    );
    final String all = <String>[
      ...lines,
      ...results.map((CheckResult r) => '$r'),
    ].join('\n');
    for (final String secret in <String>[
      'ya29.kit-token',
      'AIzaKitKey',
      'AIzaOtherKey',
    ]) {
      expect(all, isNot(contains(secret)));
    }
  });
}
