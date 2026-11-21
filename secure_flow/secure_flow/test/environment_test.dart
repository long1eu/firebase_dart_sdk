// The choice of a presenter: what an injected environment offers, how each flow ranks it, and
// an explicit presenter accepted or refused. No real environment is read and nothing is shown.

import 'dart:async';

import 'package:secure_flow/secure_flow.dart';
import 'package:test/test.dart';

const String _siteKey = '6LcTestSiteKey-for_the_loopback_page_0001';

/// A provider app that signs in to the providers in [providers] and returns [result].
final class _FakeProviderApp implements ProviderAppPresenter {
  _FakeProviderApp(this.providers, this.result);

  final Set<String> providers;
  final OAuthResult Function(OAuthAppRequest request) result;
  final List<OAuthAppRequest> requests = <OAuthAppRequest>[];

  @override
  SecurePresenterKind get kind => SecurePresenterKind.providerApp;

  @override
  bool canSignIn(String providerId) => providers.contains(providerId);

  @override
  Future<OAuthResult> signIn(OAuthAppRequest request) async {
    requests.add(request);
    return result(request);
  }
}

OAuthFlow _oauth({String providerId = 'facebook.com'}) => OAuthFlow(
  providerId: providerId,
  authorizationUrl: Uri.parse,
  state: 'the-state',
  scopes: const <String>['email'],
  rawNonce: 'raw-nonce',
  hashedNonce: 'hashed-nonce',
);

final RecaptchaFlow _recaptcha = RecaptchaFlow(siteKey: _siteKey);
const CodeEntryFlow _code = CodeEntryFlow(prompt: 'The code');

SecureEnvironment _env(
  String os, {
  Map<String, String> variables = const <String, String>{},
  bool terminal = false,
  List<SecurePresenter> registered = const <SecurePresenter>[],
}) => SecureEnvironment(
  operatingSystem: os,
  variables: variables,
  hasTerminal: terminal,
  registered: registered,
);

final Matcher _noPresenter = throwsA(isA<SecureFlowNoPresenter>());
final Matcher _refused = throwsA(isA<SecureFlowRefused>());

void main() {
  group('what the environment offers', () {
    test('a display gives the system browser, a terminal the console', () {
      expect(_env('macos').presenters.single, isA<SystemBrowserPresenter>());
      expect(_env('windows').presenters.single, isA<SystemBrowserPresenter>());
      expect(
        _env(
          'linux',
          variables: <String, String>{'DISPLAY': ':0'},
        ).presenters.single,
        isA<SystemBrowserPresenter>(),
      );
      expect(
        _env(
          'linux',
          variables: <String, String>{'WAYLAND_DISPLAY': 'wayland-0'},
        ).presenters.single,
        isA<SystemBrowserPresenter>(),
      );
      expect(_env('linux').presenters, isEmpty);
      expect(
        _env('linux', variables: <String, String>{'DISPLAY': ''}).presenters,
        isEmpty,
      );
      expect(
        _env('linux', terminal: true).presenters.single,
        isA<ConsolePresenter>(),
      );
      final List<SecurePresenter> both = _env(
        'macos',
        terminal: true,
      ).presenters;
      expect(both[0], isA<SystemBrowserPresenter>());
      expect(both[1], isA<ConsolePresenter>());
    });

    test('SSH takes the display away on every desktop system', () {
      for (final String os in <String>['macos', 'windows', 'linux']) {
        for (final String variable in <String>['SSH_CONNECTION', 'SSH_TTY']) {
          final SecureEnvironment env = _env(
            os,
            variables: <String, String>{
              variable: 'x',
              'DISPLAY': 'localhost:10.0',
            },
            terminal: true,
          );
          expect(env.isSsh, isTrue, reason: '$os $variable');
          expect(
            env.presenters.single,
            isA<ConsolePresenter>(),
            reason: '$os $variable',
          );
        }
      }
    });

    test(
      'mobile, the web and unknown systems offer only what the app registers',
      () {
        final _FakeProviderApp app = _FakeProviderApp(
          <String>{},
          (_) => throw StateError('x'),
        );
        for (final String os in <String>[
          'android',
          'ios',
          'fuchsia',
          'web',
          'plan9',
        ]) {
          expect(_env(os).presenters, isEmpty, reason: os);
          expect(
            _env(os, registered: <SecurePresenter>[app]).presenters,
            <SecurePresenter>[app],
          );
        }
      },
    );

    test('registered presenters come first; toString hides the variables', () {
      final CallbackPresenter mine = CallbackPresenter((_) {});
      final List<SecurePresenter> offered = _env(
        'macos',
        registered: <SecurePresenter>[mine],
      ).presenters;
      expect(offered.first, same(mine));
      const SecureEnvironment env = SecureEnvironment(
        operatingSystem: 'linux',
        variables: <String, String>{'SSH_CONNECTION': '1 2 3 4'},
      );
      expect(env.toString(), isNot(contains('1 2 3 4')));
    });

    test('current() reads this program', () {
      expect(SecureEnvironment.current().operatingSystem, isNotEmpty);
    }, testOn: 'vm');
  });

  group(
    'OAuthFlow ranking: provider app, system browser, in-app browser, console',
    () {
      final _FakeProviderApp facebook = _FakeProviderApp(<String>{
        'facebook.com',
      }, (_) => OAuthTokens(idToken: 'jwt'));

      test('the provider app wins when it can sign in to this provider', () {
        final SecureEnvironment env = _env(
          'macos',
          terminal: true,
          registered: <SecurePresenter>[facebook],
        );
        expect(_oauth().choosePresenter(env), same(facebook));
        // Not for another provider: the system browser then.
        expect(
          _oauth(providerId: 'google.com').choosePresenter(env),
          isA<SystemBrowserPresenter>(),
        );
      });

      test(
        'in-app browser before the console; never a web view or another kind',
        () {
          final CallbackPresenter tab = CallbackPresenter(
            (_) {},
            kind: SecurePresenterKind.inAppBrowser,
          );
          final CallbackPresenter webView = CallbackPresenter(
            (_) {},
            kind: SecurePresenterKind.embeddedWebView,
          );
          final CallbackPresenter other = CallbackPresenter(
            (_) {},
            kind: SecurePresenterKind.other,
          );
          expect(
            _oauth().choosePresenter(
              _env(
                'linux',
                terminal: true,
                registered: <SecurePresenter>[webView, tab],
              ),
            ),
            same(tab),
          );
          expect(
            _oauth().choosePresenter(_env('linux', terminal: true)),
            isA<ConsolePresenter>(),
          );
          expect(
            () => _oauth().choosePresenter(
              _env('android', registered: <SecurePresenter>[webView, other]),
            ),
            _noPresenter,
          );
          expect(() => _oauth().choosePresenter(_env('linux')), _noPresenter);
        },
      );
    },
  );

  group(
    'RecaptchaFlow ranking: embedded web view, system browser, console',
    () {
      test('each in turn; an in-app browser or another kind is not taken', () {
        final CallbackPresenter webView = CallbackPresenter(
          (_) {},
          kind: SecurePresenterKind.embeddedWebView,
        );
        final CallbackPresenter tab = CallbackPresenter(
          (_) {},
          kind: SecurePresenterKind.inAppBrowser,
        );
        final CallbackPresenter other = CallbackPresenter(
          (_) {},
          kind: SecurePresenterKind.other,
        );
        expect(
          _recaptcha.choosePresenter(
            _env(
              'macos',
              terminal: true,
              registered: <SecurePresenter>[other, tab, webView],
            ),
          ),
          same(webView),
        );
        expect(
          _recaptcha.choosePresenter(
            _env(
              'macos',
              terminal: true,
              registered: <SecurePresenter>[other, tab],
            ),
          ),
          isA<SystemBrowserPresenter>(),
        );
        expect(
          _recaptcha.choosePresenter(
            _env(
              'linux',
              terminal: true,
              registered: <SecurePresenter>[other, tab],
            ),
          ),
          isA<ConsolePresenter>(),
        );
        expect(
          () => _recaptcha.choosePresenter(
            _env('ios', registered: <SecurePresenter>[other, tab]),
          ),
          _noPresenter,
        );
      });
      test('a provider app is not for it', () {
        final _FakeProviderApp app = _FakeProviderApp(<String>{
          'facebook.com',
        }, (_) => OAuthTokens(idToken: 'x'));
        expect(
          () => _recaptcha.choosePresenter(
            _env('ios', registered: <SecurePresenter>[app]),
          ),
          _noPresenter,
        );
      });
    },
  );

  group('CodeEntryFlow ranking: console prompt, then the page', () {
    test('the terminal first, the system browser without one', () {
      expect(
        _code.choosePresenter(_env('macos', terminal: true)),
        isA<ConsolePresenter>(),
      );
      expect(
        _code.choosePresenter(_env('macos')),
        isA<SystemBrowserPresenter>(),
      );
      expect(() => _code.choosePresenter(_env('linux')), _noPresenter);
    });

    test('nothing but the terminal and the system browser', () async {
      final CallbackPresenter tab = CallbackPresenter(
        (_) {},
        kind: SecurePresenterKind.inAppBrowser,
      );
      expect(
        () => _code.choosePresenter(
          _env('ios', registered: <SecurePresenter>[tab]),
        ),
        _noPresenter,
      );
      await expectLater(_code.run(presenter: tab), _refused);
    });

    test(
      'on a terminal it reads the injected input; no browser, no server',
      () async {
        final StringBuffer sink = StringBuffer();
        final StreamController<String> input =
            StreamController<String>.broadcast();
        final SecureEnvironment env = _env(
          'macos',
          terminal: true,
          registered: <SecurePresenter>[
            ConsolePresenter(sink: sink, input: input.stream),
          ],
        );
        final Future<String> code = _code.run(environment: env);
        await pumpEventQueue();
        input.add('   ');
        await pumpEventQueue();
        input.add(' 123456 ');
        expect(await code, '123456');
        expect(sink.toString(), 'The code: The code: ');
        await input.close();
      },
    );

    test(
      'an input that ends is an error, and a silent one times out',
      () async {
        await expectLater(
          _code.run(
            presenter: ConsolePresenter(
              sink: StringBuffer(),
              input: const Stream.empty(),
            ),
          ),
          throwsStateError,
        );
        final StreamController<String> silent = StreamController<String>();
        await expectLater(
          _code.run(
            presenter: ConsolePresenter(
              sink: StringBuffer(),
              input: silent.stream,
            ),
            timeout: const Duration(milliseconds: 100),
          ),
          throwsA(isA<SecureFlowTimeout>()),
        );
        await silent.close();
      },
    );
  });

  group('an explicit presenter', () {
    test(
      'is used when the flow accepts it, whatever the environment offers',
      () async {
        final _FakeProviderApp app = _FakeProviderApp(<String>{
          'facebook.com',
        }, (_) => OAuthTokens(accessToken: 'at'));
        final OAuthResult result = await _oauth().run(
          presenter: app,
          environment: _env('macos'),
        );
        expect((result as OAuthTokens).accessToken, 'at');
      },
    );

    test('is refused when its kind is not ranked, never replaced', () async {
      bool shown = false;
      final CallbackPresenter webView = CallbackPresenter(
        (_) => shown = true,
        kind: SecurePresenterKind.embeddedWebView,
      );
      await expectLater(
        _oauth().run(presenter: webView, environment: _env('macos')),
        _refused,
      );
      final _FakeProviderApp app = _FakeProviderApp(<String>{
        'facebook.com',
      }, (_) => OAuthTokens(idToken: 'x'));
      await expectLater(_recaptcha.run(presenter: app), _refused);
      await expectLater(_code.run(presenter: app), _refused);
      expect(shown, isFalse);
    });

    test('a provider app for another provider is refused', () async {
      final _FakeProviderApp google = _FakeProviderApp(<String>{
        'google.com',
      }, (_) => OAuthTokens(idToken: 'x'));
      await expectLater(_oauth().run(presenter: google), _refused);
      expect(google.requests, isEmpty);
    });
  });

  group('a provider app completes the flow without the server', () {
    test(
      'it gets the provider, the scopes, the state and both nonces; tokens come back',
      () async {
        final _FakeProviderApp app = _FakeProviderApp(<String>{
          'facebook.com',
        }, (_) => OAuthTokens(idToken: 'limited-login-jwt'));
        final OAuthResult result = await _oauth().run(
          environment: _env('android', registered: <SecurePresenter>[app]),
        );
        expect(
          result,
          isA<OAuthTokens>().having(
            (OAuthTokens t) => t.idToken,
            'id',
            'limited-login-jwt',
          ),
        );
        final OAuthAppRequest request = app.requests.single;
        expect(request.providerId, 'facebook.com');
        expect(request.scopes, <String>['email']);
        expect(request.state, 'the-state');
        expect(request.rawNonce, 'raw-nonce');
        expect(request.hashedNonce, 'hashed-nonce');
        expect(
          request.toString(),
          allOf(isNot(contains('nonce-')), isNot(contains('the-state'))),
        );
      },
    );

    test(
      'an app redirect must carry the state; it is removed from the result',
      () async {
        final OAuthResult good = await _oauth().run(
          presenter: _FakeProviderApp(
            <String>{'facebook.com'},
            (OAuthAppRequest r) => OAuthRedirect(
              parameters: <String, String>{'code': 'c', 'state': r.state},
              redirectUri: 'fb123://authorize',
            ),
          ),
        );
        expect((good as OAuthRedirect).parameters, <String, String>{
          'code': 'c',
        });
        await expectLater(
          _oauth().run(
            presenter: _FakeProviderApp(
              <String>{'facebook.com'},
              (_) => const OAuthRedirect(
                parameters: <String, String>{'code': 'c', 'state': 'forged'},
                redirectUri: 'fb123://authorize',
              ),
            ),
          ),
          throwsStateError,
        );
      },
    );

    test('a slow app times out, and map applies to its result', () async {
      final Completer<OAuthResult> never = Completer<OAuthResult>();
      final _SlowApp slow = _SlowApp(never.future);
      await expectLater(
        _oauth().run(
          presenter: slow,
          timeout: const Duration(milliseconds: 100),
        ),
        throwsA(isA<SecureFlowTimeout>()),
      );
      final String kind = await _oauth()
          .map((OAuthResult r) => r.runtimeType.toString())
          .run(
            presenter: _FakeProviderApp(<String>{
              'facebook.com',
            }, (_) => OAuthTokens(idToken: 'x')),
          );
      expect(kind, 'OAuthTokens');
    });

    test('tokens need an ID token or an access token', () {
      expect(() => OAuthTokens(), throwsArgumentError);
      expect(
        () => OAuthTokens(idToken: '', accessToken: ''),
        throwsArgumentError,
      );
      expect(
        OAuthTokens(idToken: 'secret').toString(),
        isNot(contains('secret')),
      );
    });
  });

  test('a CallbackPresenter cannot claim to be a provider app', () {
    expect(
      () => CallbackPresenter((_) {}, kind: SecurePresenterKind.providerApp),
      throwsArgumentError,
    );
  });
}

final class _SlowApp implements ProviderAppPresenter {
  _SlowApp(this._result);

  final Future<OAuthResult> _result;

  @override
  SecurePresenterKind get kind => SecurePresenterKind.providerApp;

  @override
  bool canSignIn(String providerId) => true;

  @override
  Future<OAuthResult> signIn(OAuthAppRequest request) => _result;
}
