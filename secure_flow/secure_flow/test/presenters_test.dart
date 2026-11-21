// The built-in presenters: what each shows and where, without opening a browser.

@TestOn('vm')
library;

import 'dart:async';

import 'package:secure_flow/secure_flow.dart';
import 'package:secure_flow/src/browser_command.dart';
import 'package:test/test.dart';

import 'browser.dart';

const String _siteKey = '6LcTestSiteKey-for_the_loopback_page_0001';

void main() {
  group('ConsolePresenter', () {
    test('writes only the URL, one line, to its sink', () async {
      final StringBuffer sink = StringBuffer();
      final ConsolePresenter presenter = ConsolePresenter(sink: sink);
      final Future<String> result = presenter.run(
        RecaptchaFlow(siteKey: _siteKey),
        timeout: const Duration(seconds: 10),
      );
      // The person opens the printed URL in a browser on this machine.
      while (sink.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      final Uri url = Uri.parse(sink.toString().trim());
      await postForm(url, <String, String>{
        'state': url.queryParameters['state']!,
        'token': 'secret-token',
      });
      expect(await result, 'secret-token');
      expect(sink.toString(), '$url\n');
      expect(sink.toString(), isNot(contains(_siteKey)));
      expect(sink.toString(), isNot(contains('secret-token')));
    });

    test(
      'a timeout names the ssh -L forward of the port, and no secret',
      () async {
        final StringBuffer sink = StringBuffer();
        final Object error = await ConsolePresenter(sink: sink)
            .run(
              OAuthFlow(
                providerId: 'oidc.fake',
                authorizationUrl: (String redirectUri) =>
                    Uri.parse('$redirectUri/?state=secret-state'),
                state: 'secret-state',
              ),
              timeout: const Duration(milliseconds: 200),
            )
            .then<Object>((_) => fail('no timeout'), onError: (Object e) => e);
        final Uri url = Uri.parse(sink.toString().trim());
        expect(
          error,
          isA<SecureFlowTimeout>().having(
            (SecureFlowTimeout e) => e.hint,
            'hint',
            contains('ssh -L ${url.port}:127.0.0.1:${url.port}'),
          ),
        );
        expect(error.toString(), contains('ssh -L'));
        expect(
          error.toString(),
          isNot(contains(url.queryParameters['state']!)),
        );
      },
    );

    test('the hint follows the host of the flow', () async {
      final StringBuffer sink = StringBuffer();
      final Object error = await ConsolePresenter(sink: sink)
          .run(
            RecaptchaFlow(siteKey: _siteKey),
            timeout: const Duration(milliseconds: 100),
          )
          .then<Object>((_) => fail('no timeout'), onError: (Object e) => e);
      final Uri url = Uri.parse(sink.toString().trim());
      expect(
        (error as SecureFlowTimeout).hint,
        contains('ssh -L ${url.port}:localhost:${url.port}'),
      );
    });
  });

  group('SystemBrowserPresenter', () {
    test('opens the URL with its opener and takes the answer', () async {
      final List<Uri> opened = <Uri>[];
      final String code = await SystemBrowserPresenter(
        open: (Uri url) async {
          opened.add(url);
          await postForm(url, <String, String>{
            'state': url.queryParameters['state']!,
            'code': '42',
          });
        },
      ).run(const CodeEntryFlow(prompt: 'code'));
      expect(code, '42');
      expect(opened.single.host, '127.0.0.1');
    });

    test('an opener that fails ends the run with its error', () async {
      await expectLater(
        SystemBrowserPresenter(
          open: (_) => throw StateError('no browser'),
        ).run(const CodeEntryFlow(prompt: 'code')),
        throwsStateError,
      );
    });

    test('runs OAuth (it is not embedded)', () async {
      final OAuthRedirect redirect =
          await SystemBrowserPresenter(
            open: (Uri url) async {
              final Uri redirectUri = Uri.parse(url.queryParameters['to']!);
              await send(
                'GET',
                redirectUri.replace(
                  path: '/',
                  queryParameters: <String, String>{'code': 'c', 'state': 's'},
                ),
              );
            },
          ).run(
            OAuthFlow(
              providerId: 'oidc.fake',
              authorizationUrl: (String redirectUri) => Uri.https(
                'idp.example',
                '/authorize',
                <String, String>{'to': redirectUri},
              ),
              state: 's',
            ).map((OAuthResult r) => r as OAuthRedirect),
          );
      expect(redirect.parameters['code'], 'c');
    });
  });

  group('browserCommand', () {
    final Uri url = Uri.parse('https://idp.example/a?b=c&d=e');

    test('one argument per system, no shell', () {
      expect(browserCommand('macos', url)!.executable, 'open');
      expect(browserCommand('macos', url)!.arguments, <String>['$url']);
      expect(browserCommand('linux', url)!.executable, 'xdg-open');
      expect(browserCommand('linux', url)!.arguments, <String>['$url']);
      expect(browserCommand('windows', url)!.executable, 'rundll32');
      expect(browserCommand('windows', url)!.arguments, <String>[
        'url.dll,FileProtocolHandler',
        '$url',
      ]);
    });

    test('none on systems without a desktop browser command', () {
      for (final String os in <String>['android', 'ios', 'fuchsia', 'web']) {
        expect(browserCommand(os, url), isNull, reason: os);
      }
    });
  });
}
