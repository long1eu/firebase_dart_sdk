// The built-in flows as data and parsers, without a server: their host, accept rule, URL, page
// and parser.

import 'package:secure_flow/secure_flow.dart';
import 'package:secure_flow/src/pages.dart';
import 'package:test/test.dart';

const String _siteKey = '6LcTestSiteKey-for_the_loopback_page_0001';

SecureFlowSession _session(SecureFlowHost host, {String path = '/p4th'}) =>
    SecureFlowSession(host: host, port: 4321, path: path, state: 'st4te');

Matcher _rejected(String text) => throwsA(
  isA<SecureAnswerRejected>().having(
    (SecureAnswerRejected e) => e.page.text,
    'text',
    contains(text),
  ),
);

void main() {
  group('SecureFlowSession', () {
    test('origin, Host header and address follow the host and the path', () {
      final SecureFlowSession ipv4 = _session(SecureFlowHost.loopbackIPv4);
      expect(ipv4.origin, 'http://127.0.0.1:4321');
      expect(ipv4.hostHeader, '127.0.0.1:4321');
      expect(ipv4.address, 'http://127.0.0.1:4321/p4th');
      final SecureFlowSession root = _session(
        SecureFlowHost.localhost,
        path: '/',
      );
      expect(root.origin, 'http://localhost:4321');
      expect(root.address, 'http://localhost:4321');
    });

    test('toString leaves out the path and the state', () {
      final String text = _session(SecureFlowHost.localhost).toString();
      expect(text, allOf(isNot(contains('p4th')), isNot(contains('st4te'))));
    });
  });

  group('OAuthFlow', () {
    OAuthFlow flow({String redirectPath = '/', int port = 0}) => OAuthFlow(
      providerId: 'oidc.fake',
      authorizationUrl: (String redirectUri) => Uri.https(
        'idp.example',
        '/authorize',
        <String, String>{'redirect_uri': redirectUri},
      ),
      state: 'client-state',
      redirectPath: redirectPath,
      port: port,
    );

    test(
      'host 127.0.0.1, a GET with the query on the redirect path, the caller\'s state',
      () {
        final OAuthFlow oauth = flow(redirectPath: '/callback', port: 8080);
        expect(oauth.purpose, SecureFlowPurpose.oauth);
        expect(oauth.host, SecureFlowHost.loopbackIPv4);
        expect(oauth.host.hostName, '127.0.0.1');
        expect(oauth.port, 8080);
        expect(oauth.answer.encoding, SecureAnswerEncoding.query);
        expect(oauth.answer.method, 'GET');
        expect(oauth.answer.path, '/callback');
        expect(oauth.state, 'client-state');
        expect(oauth.presenterKinds, <SecurePresenterKind>[
          SecurePresenterKind.providerApp,
          SecurePresenterKind.systemBrowser,
          SecurePresenterKind.inAppBrowser,
          SecurePresenterKind.console,
        ]);
        expect(oauth.page(_session(SecureFlowHost.loopbackIPv4)), isNull);
      },
    );

    test('the redirect URI has no path for /, and the path otherwise', () {
      final Uri root = flow().start(
        _session(SecureFlowHost.loopbackIPv4, path: '/'),
      );
      expect(root.queryParameters['redirect_uri'], 'http://127.0.0.1:4321');
      final Uri callback = flow(
        redirectPath: '/callback',
      ).start(_session(SecureFlowHost.loopbackIPv4, path: '/callback'));
      expect(
        callback.queryParameters['redirect_uri'],
        'http://127.0.0.1:4321/callback',
      );
    });

    test(
      'the result is the query and the redirect URI; toString hides the values',
      () async {
        final OAuthRedirect redirect = flow().parse(<String, String>{
          'code': 'the-code',
          'scope': 'email',
        }, _session(SecureFlowHost.loopbackIPv4, path: '/'));
        expect(redirect.parameters, <String, String>{
          'code': 'the-code',
          'scope': 'email',
        });
        expect(redirect.redirectUri, 'http://127.0.0.1:4321');
        expect(redirect.toString(), isNot(contains('the-code')));
        expect(flow().toString(), isNot(contains('client-state')));
      },
    );

    test('the sign-in pages', () {
      expect(
        flow().notFoundPage.text,
        'This address only receives the sign-in redirect.',
      );
      expect(
        flow().rejectedPage.text,
        contains('does not belong to the sign-in in progress'),
      );
      final OAuthFlow custom = OAuthFlow(
        providerId: 'oidc.fake',
        authorizationUrl: Uri.parse,
        state: 's',
        donePage: const SecurePage.message(
          title: 'Signed in',
          text: 'You are signed in.',
        ),
      );
      expect(custom.donePage.title, 'Signed in');
    });

    test('an empty state, a relative path or a bad port is refused', () {
      expect(
        () => OAuthFlow(
          providerId: 'oidc.fake',
          authorizationUrl: Uri.parse,
          state: '',
        ),
        throwsArgumentError,
      );
      expect(
        () => OAuthFlow(
          providerId: 'oidc.fake',
          authorizationUrl: Uri.parse,
          state: 's',
          redirectPath: 'cb',
        ),
        throwsArgumentError,
      );
      expect(
        () => OAuthFlow(
          providerId: 'oidc.fake',
          authorizationUrl: Uri.parse,
          state: 's',
          port: 65536,
        ),
        throwsArgumentError,
      );
      expect(
        () => OAuthFlow(
          providerId: 'oidc.fake',
          authorizationUrl: Uri.parse,
          state: 's',
          port: -1,
        ),
        throwsArgumentError,
      );
    });
  });

  group('RecaptchaFlow', () {
    test('host localhost, a form POST on a random path, a random state', () {
      final RecaptchaFlow flow = RecaptchaFlow(siteKey: _siteKey);
      expect(flow.purpose, SecureFlowPurpose.recaptcha);
      expect(flow.host, SecureFlowHost.localhost);
      expect(flow.answer.encoding, SecureAnswerEncoding.form);
      expect(flow.answer.method, 'POST');
      expect(flow.answer.path, isNull);
      expect(flow.state, isNull);
      expect(flow.port, 0);
      expect(flow.presenterKinds.first, SecurePresenterKind.inPage);
      expect(
        flow.start(_session(SecureFlowHost.localhost)).toString(),
        'http://localhost:4321/p4th?state=st4te',
      );
    });

    test('the token is the result; an empty or missing one is rejected', () {
      final RecaptchaFlow flow = RecaptchaFlow(siteKey: _siteKey);
      final SecureFlowSession session = _session(SecureFlowHost.localhost);
      expect(flow.parse(<String, String>{'token': 'tok'}, session), 'tok');
      expect(
        () => flow.parse(<String, String>{'token': ''}, session),
        _rejected('no token'),
      );
      expect(
        () => flow.parse(<String, String>{}, session),
        _rejected('no token'),
      );
    });

    test('the page: site key, its own path, nonce in the CSP, no state', () {
      final SecurePage page = RecaptchaFlow(
        siteKey: _siteKey,
        languageCode: 'ro',
      ).page(_session(SecureFlowHost.localhost));
      final String html = page.html!;
      expect(html, contains('data-sitekey="$_siteKey"'));
      expect(html, contains('action="/p4th"'));
      expect(html, contains('&amp;hl=ro"'));
      expect(html, isNot(contains('st4te')));
      final String nonce = RegExp(
        r"'nonce-([A-Za-z0-9_-]+)'",
      ).firstMatch(page.contentSecurityPolicy!)!.group(1)!;
      expect(RegExp('nonce="$nonce"').allMatches(html), hasLength(2));
      expect(page.contentSecurityPolicy, contains("form-action 'self'"));
      expect(page.referrerPolicy, 'strict-origin');
    });

    test('a language code that is not a plain tag is dropped', () {
      expect(
        RecaptchaFlow(
          siteKey: _siteKey,
          languageCode: 'en"><script>',
        ).languageCode,
        isNull,
      );
      expect(
        RecaptchaFlow(siteKey: _siteKey, languageCode: 'pt-BR').languageCode,
        'pt-BR',
      );
    });

    test('a site key that is not one is refused without repeating it', () {
      expect(
        () => RecaptchaFlow(siteKey: '"><script>'),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => '$e',
            'text',
            isNot(contains('<script>')),
          ),
        ),
      );
      expect(
        RecaptchaFlow(siteKey: _siteKey).toString(),
        isNot(contains(_siteKey)),
      );
    });
  });

  group('CodeEntryFlow', () {
    const CodeEntryFlow flow = CodeEntryFlow(
      prompt: 'The code <from> the email',
    );

    test('host 127.0.0.1, a form POST on a random path', () {
      expect(flow.purpose, SecureFlowPurpose.codeEntry);
      expect(flow.host, SecureFlowHost.loopbackIPv4);
      expect(flow.answer.encoding, SecureAnswerEncoding.form);
      expect(flow.answer.path, isNull);
      expect(flow.state, isNull);
    });

    test('the page escapes the prompt and posts the state to its path', () {
      final SecurePage page = flow.page(_session(SecureFlowHost.loopbackIPv4));
      expect(page.html, contains('The code &lt;from&gt; the email'));
      expect(page.html, contains('action="/p4th"'));
      expect(page.html, contains('name="state" value="st4te"'));
      expect(page.html, isNot(contains('<script')));
      expect(page.contentSecurityPolicy, contains("form-action 'self'"));
      final String nonce = RegExp(
        r"style-src 'nonce-([A-Za-z0-9_-]+)'",
      ).firstMatch(page.contentSecurityPolicy!)!.group(1)!;
      expect(page.html, contains('<style nonce="$nonce">'));
    });

    test('the code is trimmed; empty or too long is rejected', () {
      final SecureFlowSession session = _session(SecureFlowHost.loopbackIPv4);
      expect(
        flow.parse(<String, String>{'code': ' 123 456 '}, session),
        '123 456',
      );
      expect(
        () => flow.parse(<String, String>{'code': '  '}, session),
        _rejected('enter the code'),
      );
      expect(
        () => flow.parse(<String, String>{}, session),
        _rejected('enter the code'),
      );
      expect(
        () => flow.parse(<String, String>{'code': 'x' * 257}, session),
        _rejected('enter the code'),
      );
      expect(
        flow.parse(<String, String>{'code': 'x' * 256}, session),
        hasLength(256),
      );
    });
  });

  group('map', () {
    test('keeps everything of the flow and converts the result', () async {
      final RecaptchaFlow base = RecaptchaFlow(siteKey: _siteKey);
      final SecureFlow<int> mapped = base.map((String token) => token.length);
      final SecureFlowSession session = _session(SecureFlowHost.localhost);
      expect(mapped.purpose, base.purpose);
      expect(mapped.host, base.host);
      expect(mapped.answer.encoding, base.answer.encoding);
      expect(mapped.port, base.port);
      expect(mapped.state, base.state);
      expect(mapped.presenterKinds, base.presenterKinds);
      expect(mapped.start(session), base.start(session));
      expect(mapped.page(session)!.html, contains(_siteKey));
      expect(mapped.notFoundPage.text, base.notFoundPage.text);
      expect(mapped.rejectedPage.text, base.rejectedPage.text);
      expect(mapped.donePage.text, base.donePage.text);
      expect(mapped.failedPage.text, base.failedPage.text);
      expect(await mapped.parse(<String, String>{'token': 'abc'}, session), 3);
      await expectLater(
        mapped.parse(<String, String>{}, session),
        throwsA(isA<SecureAnswerRejected>()),
      );
    });
  });

  group('renderPage', () {
    test('a message page is escaped, dark-mode aware and scriptless', () {
      final ({String html, String contentSecurityPolicy}) page = renderPage(
        const SecurePage.message(title: 'A <b>', text: 'x & "y"'),
      );
      expect(page.html, contains('<h1>A &lt;b&gt;</h1>'));
      expect(page.html, contains('x &amp; &quot;y&quot;'));
      expect(page.html, contains('color-scheme:light dark'));
      expect(
        page.html,
        contains('<meta name="color-scheme" content="light dark">'),
      );
      expect(page.contentSecurityPolicy, startsWith("default-src 'none'"));
    });

    test('a message page gets a new style nonce on every response', () {
      const SecurePage page = SecurePage.message(title: 't', text: 'x');
      final ({String html, String contentSecurityPolicy}) one = renderPage(
        page,
      );
      final ({String html, String contentSecurityPolicy}) two = renderPage(
        page,
      );
      final String nonce = RegExp(
        r"style-src 'nonce-([A-Za-z0-9_-]{22,})'",
      ).firstMatch(one.contentSecurityPolicy)!.group(1)!;
      expect(one.html, contains('<style nonce="$nonce">'));
      expect(one.contentSecurityPolicy, isNot(contains('unsafe-inline')));
      expect(two.contentSecurityPolicy, isNot(contains(nonce)));
    });

    test('an HTML page is sent as it is with its policy', () {
      final ({String html, String contentSecurityPolicy}) page = renderPage(
        const SecurePage.html(
          '<p>x</p>',
          contentSecurityPolicy: "default-src 'self'",
        ),
      );
      expect(page.html, '<p>x</p>');
      expect(page.contentSecurityPolicy, "default-src 'self'");
    });
  });
}
