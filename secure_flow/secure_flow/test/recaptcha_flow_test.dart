// RecaptchaFlow beyond the v2 checkbox, without a server or a browser: the Enterprise mode and its
// page, the size and theme of the v2 widget, the script addresses, and a RecaptchaPresenter that
// returns the token itself.

import 'package:secure_flow/secure_flow.dart';
import 'package:secure_flow/src/recaptcha_scripts.dart';
import 'package:test/test.dart';

const String _siteKey = '6LcTestSiteKey-for_the_loopback_page_0001';

SecureFlowSession _session() => const SecureFlowSession(
  host: SecureFlowHost.localhost,
  port: 4321,
  path: '/p4th',
  state: 'st4te',
);

/// A RecaptchaPresenter that records its requests and answers with [token].
final class _FakeRecaptchaPresenter implements RecaptchaPresenter {
  _FakeRecaptchaPresenter(this.token, {this.kind = SecurePresenterKind.inPage});

  final String token;
  final List<RecaptchaRequest> requests = <RecaptchaRequest>[];

  @override
  final SecurePresenterKind kind;

  @override
  Future<String> recaptcha(RecaptchaRequest request) async {
    requests.add(request);
    return token;
  }
}

void main() {
  group('RecaptchaFlow.enterprise', () {
    test('a site key and an action; the request says Enterprise', () {
      final RecaptchaFlow flow = RecaptchaFlow.enterprise(
        siteKey: _siteKey,
        action: 'signInWithPassword',
        languageCode: 'ro',
      );
      expect(flow.action, 'signInWithPassword');
      expect(flow.size, RecaptchaSize.invisible);
      expect(flow.request.isEnterprise, isTrue);
      expect(flow.request.enterpriseAction, 'signInWithPassword');
      expect(flow.request.siteKey, _siteKey);
      expect(flow.request.languageCode, 'ro');
      expect(flow.purpose, SecureFlowPurpose.recaptcha);
      expect(flow.host, SecureFlowHost.localhost);
    });

    test('an action Google does not accept is refused; a bad key too', () {
      expect(
        () => RecaptchaFlow.enterprise(siteKey: _siteKey, action: 'a b'),
        throwsArgumentError,
      );
      expect(
        () => RecaptchaFlow.enterprise(siteKey: _siteKey, action: ''),
        throwsArgumentError,
      );
      expect(
        () => RecaptchaFlow.enterprise(siteKey: '"><x', action: 'verify'),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => '$e',
            'text',
            isNot(contains('"><x')),
          ),
        ),
      );
      expect(
        RecaptchaFlow.enterprise(siteKey: _siteKey, action: 'mfa/sms_1'),
        isA<RecaptchaFlow>(),
      );
    });

    test(
      'the page loads enterprise.js for the key and executes the action',
      () {
        final SecurePage page = RecaptchaFlow.enterprise(
          siteKey: _siteKey,
          action: 'getOobCode',
        ).page(_session());
        final String html = page.html!;
        expect(
          html,
          contains(
            'src="https://www.google.com/recaptcha/enterprise.js?'
            'render=$_siteKey&amp;onload=onRecaptchaLoad"',
          ),
        );
        expect(html, contains('data-action="getOobCode"'));
        expect(
          html,
          contains(
            'grecaptcha.enterprise.execute(box.dataset.sitekey, '
            '{ action: box.dataset.action })',
          ),
        );
        expect(html, isNot(contains('grecaptcha.render(')));
        expect(html, isNot(contains('st4te')));
        expect(html, contains('action="/p4th"'));
        final String nonce = RegExp(
          r"'nonce-([A-Za-z0-9_-]+)'",
        ).firstMatch(page.contentSecurityPolicy!)!.group(1)!;
        expect(RegExp('nonce="$nonce"').allMatches(html), hasLength(2));
        expect(page.referrerPolicy, 'strict-origin');
      },
    );

    test('toString names the action, not the key', () {
      final String text = RecaptchaFlow.enterprise(
        siteKey: _siteKey,
        action: 'verify',
      ).toString();
      expect(text, contains('verify'));
      expect(text, isNot(contains(_siteKey)));
      expect(
        RecaptchaFlow.enterprise(
          siteKey: _siteKey,
          action: 'verify',
        ).request.toString(),
        isNot(contains(_siteKey)),
      );
    });
  });

  group('the v2 widget', () {
    test('size and theme reach the page; no theme follows the system', () {
      final String styled = RecaptchaFlow(
        siteKey: _siteKey,
        size: RecaptchaSize.invisible,
        theme: RecaptchaTheme.dark,
      ).page(_session()).html!;
      expect(styled, contains('data-size="invisible"'));
      expect(styled, contains('data-theme="dark"'));
      expect(
        styled,
        contains("if (size === 'invisible') { grecaptcha.execute(id); }"),
      );
      final String plain = RecaptchaFlow(
        siteKey: _siteKey,
      ).page(_session()).html!;
      expect(plain, contains('data-size="normal"'));
      expect(plain, contains('data-theme=""'));
      expect(plain, contains('prefers-color-scheme: dark'));
    });

    test('the page script keeps its names out of the global scope', () {
      final String html = RecaptchaFlow(
        siteKey: _siteKey,
      ).page(_session()).html!;
      // `status` at the top level would be window.status, a string.
      expect(html, contains('(function () {var state'));
      expect(html, contains('})();</script>'));
    });

    test('the request carries the size, the theme and the language', () {
      final RecaptchaRequest request = RecaptchaFlow(
        siteKey: _siteKey,
        languageCode: 'pt-BR',
        size: RecaptchaSize.compact,
        theme: RecaptchaTheme.light,
      ).request;
      expect(request.isEnterprise, isFalse);
      expect(request.size, RecaptchaSize.compact);
      expect(request.theme, RecaptchaTheme.light);
      expect(request.languageCode, 'pt-BR');
    });
  });

  group('a RecaptchaPresenter', () {
    test('ranks first and returns the token without a server', () async {
      final _FakeRecaptchaPresenter presenter = _FakeRecaptchaPresenter('tok');
      final RecaptchaFlow flow = RecaptchaFlow.enterprise(
        siteKey: _siteKey,
        action: 'verify',
      );
      expect(flow.presenterKinds, <SecurePresenterKind>[
        SecurePresenterKind.inPage,
        SecurePresenterKind.embeddedWebView,
        SecurePresenterKind.systemBrowser,
        SecurePresenterKind.console,
      ]);
      expect(flow.canDrive(presenter), isTrue);
      expect(await flow.run(presenter: presenter), 'tok');
      expect(presenter.requests.single.enterpriseAction, 'verify');
      expect(presenter.requests.single.siteKey, _siteKey);
    });

    test('is chosen from the environment before a browser', () {
      final _FakeRecaptchaPresenter presenter = _FakeRecaptchaPresenter('tok');
      final SecureEnvironment environment = SecureEnvironment(
        operatingSystem: 'macos',
        registered: <SecurePresenter>[presenter],
      );
      expect(
        RecaptchaFlow(siteKey: _siteKey).choosePresenter(environment),
        same(presenter),
      );
    });

    test('of another kind it ranks, it still runs directly', () async {
      final _FakeRecaptchaPresenter webView = _FakeRecaptchaPresenter(
        'tok',
        kind: SecurePresenterKind.embeddedWebView,
      );
      expect(
        await RecaptchaFlow(siteKey: _siteKey).run(presenter: webView),
        'tok',
      );
    });

    test('an empty token is a RecaptchaFailure (noToken)', () async {
      await expectLater(
        RecaptchaFlow(
          siteKey: _siteKey,
        ).run(presenter: _FakeRecaptchaPresenter('')),
        throwsA(
          isA<RecaptchaFailure>().having(
            (RecaptchaFailure e) => e.reason,
            'reason',
            RecaptchaFailureReason.noToken,
          ),
        ),
      );
    });

    test('map converts its token too', () async {
      final int length = await RecaptchaFlow(siteKey: _siteKey)
          .map((String token) => token.length)
          .run(presenter: _FakeRecaptchaPresenter('four'));
      expect(length, 4);
    });

    test('OAuth and code entry refuse it', () async {
      final _FakeRecaptchaPresenter presenter = _FakeRecaptchaPresenter('tok');
      await expectLater(
        const CodeEntryFlow(prompt: 'code').run(presenter: presenter),
        throwsA(isA<SecureFlowRefused>()),
      );
      await expectLater(
        OAuthFlow(
          providerId: 'google.com',
          authorizationUrl: Uri.parse,
          state: 's',
        ).run(presenter: presenter),
        throwsA(isA<SecureFlowRefused>()),
      );
    });
  });

  group('script addresses', () {
    test('v2: explicit render, the onload callback, a plain hl only', () {
      expect(
        recaptchaV2ScriptUrl(onload: 'cb', languageCode: 'ro').toString(),
        'https://www.google.com/recaptcha/api.js?onload=cb&render=explicit&hl=ro',
      );
      expect(
        recaptchaV2ScriptUrl(onload: 'cb', languageCode: 'x"y').toString(),
        'https://www.google.com/recaptcha/api.js?onload=cb&render=explicit',
      );
    });

    test('Enterprise: render is the site key', () {
      expect(
        recaptchaEnterpriseScriptUrl(
          siteKey: _siteKey,
          onload: 'cb',
        ).toString(),
        'https://www.google.com/recaptcha/enterprise.js?render=$_siteKey&onload=cb',
      );
    });
  });

  group('RecaptchaFailure', () {
    test('names its reason', () {
      expect(
        const RecaptchaFailure(
          RecaptchaFailureReason.scriptLoad,
          'x',
        ).toString(),
        'RecaptchaFailure(scriptLoad): x',
      );
    });
  });
}
