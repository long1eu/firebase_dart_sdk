// InPageRecaptchaPresenter in a real browser page against a fake `window.grecaptcha`: what it
// renders, where, with which parameters, how a token, an expiry and an error come back, and the
// Enterprise execute. Google's scripts are never loaded (the fake is in place before each test, so
// the presenter does not add a script), and nothing leaves the machine.
//
// dart test -p chrome test/browser/in_page_presenter_test.dart
// dart test -p chrome --compiler dart2wasm test/browser/in_page_presenter_test.dart

@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:secure_flow/secure_flow.dart';
import 'package:secure_flow/src/dom_web.dart' as web;
import 'package:test/test.dart';

const String _siteKey = '6LcTestSiteKey-for_the_in_page_widget_0001';

/// A fake of Google's v2 and Enterprise APIs, installed as `window.grecaptcha`.
class _FakeGrecaptcha {
  _FakeGrecaptcha({this.enterpriseToken, this.autoSolve});

  /// What `grecaptcha.enterprise.execute` resolves with; null rejects. No `enterprise` when
  /// [withEnterprise] is false.
  String? enterpriseToken;

  /// When set, `execute(id)` of the v2 API answers with this token on the next turn.
  final String? autoSolve;

  bool withEnterprise = true;
  final List<web.Element> containers = <web.Element>[];

  /// The parent of each container when it was rendered into.
  final List<web.Element?> parents = <web.Element?>[];
  final List<JSObject> parameters = <JSObject>[];
  final List<int> executed = <int>[];
  final List<int> resets = <int>[];
  final List<String> enterpriseKeys = <String>[];
  final List<String> enterpriseActions = <String>[];
  String response = '';

  JSObject build() {
    final JSObject grecaptcha = JSObject()
      ..['render'] = ((web.Element container, JSObject parameters) {
        containers.add(container);
        parents.add(container.parentElement);
        this.parameters.add(parameters);
        return this.parameters.length.toJS;
      }).toJS
      ..['execute'] = ((JSNumber id) {
        executed.add(id.toDartInt);
        final String? token = autoSolve;
        if (token != null) {
          Timer.run(() => callback(token));
        }
      }).toJS
      ..['getResponse'] = ((JSNumber id) => response.toJS).toJS
      ..['reset'] = ((JSNumber id) {
        resets.add(id.toDartInt);
      }).toJS;
    if (withEnterprise) {
      grecaptcha['enterprise'] = JSObject()
        ..['ready'] = ((JSFunction ready) {
          ready.callAsFunction();
        }).toJS
        ..['execute'] = ((JSString siteKey, JSObject options) {
          enterpriseKeys.add(siteKey.toDart);
          enterpriseActions.add(options['action'].dartify()! as String);
          final String? token = enterpriseToken;
          return (token == null
                  ? Future<JSString>.error(StateError('refused'))
                  : Future<JSString>.value(token.toJS))
              .toJS;
        }).toJS;
    }
    return grecaptcha;
  }

  /// The parameter [name] of the last render.
  Object? parameter(String name) => parameters.last[name].dartify();

  /// Calls the `callback` of the last render with [token], as a solved widget does.
  void callback(String token) =>
      parameters.last.callMethod<JSAny?>('callback'.toJS, token.toJS);

  void expired() => parameters.last.callMethod<JSAny?>('expired-callback'.toJS);

  void error() => parameters.last.callMethod<JSAny?>('error-callback'.toJS);
}

_FakeGrecaptcha _install(_FakeGrecaptcha fake) {
  globalContext['grecaptcha'] = fake.build();
  return fake;
}

Future<void> _pump() => Future<void>.delayed(Duration.zero);

/// The Google script addresses a [_loader] was asked for.
final List<Uri> _loaded = <Uri>[];

/// A script address that calls the onload callback of Google's address at once: a load that works,
/// without contacting Google (the fake `grecaptcha` is in place already).
Uri _loader(Uri google) {
  _loaded.add(google);
  return Uri.dataFromString(
    'window["${google.queryParameters['onload']}"]();',
    mimeType: 'text/javascript',
  );
}

/// The number of elements in `<head>`, where the scripts go.
int _headElements() => web.document.head!.childElementCount;

void main() {
  late web.HTMLDivElement box;

  setUp(() {
    _loaded.clear();
    box = web.HTMLDivElement()..id = 'recaptcha-box';
    web.document.body!.appendChild(box);
  });

  tearDown(() {
    box.remove();
    globalContext.delete('grecaptcha'.toJS);
  });

  test('a visible widget in the container waits for the check', () async {
    final _FakeGrecaptcha fake = _install(_FakeGrecaptcha());
    int verified = 0;
    final InPageRecaptchaPresenter presenter = InPageRecaptchaPresenter(
      containerId: 'recaptcha-box',
      onVerified: () => verified++,
    );
    final Future<String> token = presenter.recaptcha(
      const RecaptchaRequest(
        siteKey: _siteKey,
        size: RecaptchaSize.compact,
        theme: RecaptchaTheme.dark,
      ),
    );
    await _pump();
    expect(fake.parameter('sitekey'), _siteKey);
    expect(fake.parameter('size'), 'compact');
    expect(fake.parameter('theme'), 'dark');
    expect(fake.containers.single.parentElement, box);
    expect(fake.executed, isEmpty);
    fake.callback('the-token');
    expect(await token, 'the-token');
    expect(verified, 1);
    expect(fake.resets, <int>[1]);
    presenter.clear();
    expect(box.childElementCount, 0);
  });

  test(
    'without a container: invisible, at the end of the document, started at once',
    () async {
      final _FakeGrecaptcha fake = _install(_FakeGrecaptcha(autoSolve: 'auto'));
      final InPageRecaptchaPresenter presenter = InPageRecaptchaPresenter();
      expect(
        await presenter.recaptcha(const RecaptchaRequest(siteKey: _siteKey)),
        'auto',
      );
      expect(fake.parameter('size'), 'invisible');
      expect(fake.executed, <int>[1]);
      expect(fake.parents.single, web.document.documentElement);
      // The element the presenter made is gone again after the check.
      expect(fake.containers.single.isConnected, isFalse);
    },
  );

  test('no theme follows the light or dark setting of the system', () async {
    final _FakeGrecaptcha fake = _install(_FakeGrecaptcha(autoSolve: 't'));
    await InPageRecaptchaPresenter().recaptcha(
      const RecaptchaRequest(siteKey: _siteKey),
    );
    final bool dark = web.mediaMatches('(prefers-color-scheme: dark)');
    expect(fake.parameter('theme'), dark ? 'dark' : 'light');
  });

  test('a widget already solved answers at once', () async {
    final _FakeGrecaptcha fake = _install(_FakeGrecaptcha())..response = 'done';
    final InPageRecaptchaPresenter presenter = InPageRecaptchaPresenter(
      containerId: 'recaptcha-box',
    );
    expect(
      await presenter.recaptcha(const RecaptchaRequest(siteKey: _siteKey)),
      'done',
    );
    expect(fake.resets, <int>[1]);
  });

  test('render renders once and returns the widget id', () async {
    final _FakeGrecaptcha fake = _install(_FakeGrecaptcha());
    final InPageRecaptchaPresenter presenter = InPageRecaptchaPresenter(
      containerId: 'recaptcha-box',
    );
    const RecaptchaRequest request = RecaptchaRequest(siteKey: _siteKey);
    expect(await presenter.render(request), 1);
    expect(await presenter.render(request), 1);
    expect(fake.containers, hasLength(1));
    await expectLater(
      presenter.render(
        const RecaptchaRequest(siteKey: _siteKey, enterpriseAction: 'verify'),
      ),
      throwsArgumentError,
    );
    presenter.clear();
    expect(await presenter.render(request), 2);
  });

  test('an expired token tells onExpired and the check goes on', () async {
    final _FakeGrecaptcha fake = _install(_FakeGrecaptcha());
    int expired = 0;
    final InPageRecaptchaPresenter presenter = InPageRecaptchaPresenter(
      containerId: 'recaptcha-box',
      onExpired: () => expired++,
    );
    final Future<String> token = presenter.recaptcha(
      const RecaptchaRequest(siteKey: _siteKey),
    );
    await _pump();
    fake.expired();
    expect(expired, 1);
    fake.callback('second');
    expect(await token, 'second');
  });

  test('an error of the widget fails the check and tells onError', () async {
    final _FakeGrecaptcha fake = _install(_FakeGrecaptcha());
    final List<RecaptchaFailure> errors = <RecaptchaFailure>[];
    final InPageRecaptchaPresenter presenter = InPageRecaptchaPresenter(
      containerId: 'recaptcha-box',
      onError: errors.add,
    );
    final Future<String> token = presenter.recaptcha(
      const RecaptchaRequest(siteKey: _siteKey),
    );
    await _pump();
    fake.error();
    await expectLater(
      token,
      throwsA(
        isA<RecaptchaFailure>().having(
          (RecaptchaFailure e) => e.reason,
          'reason',
          RecaptchaFailureReason.widget,
        ),
      ),
    );
    expect(errors.single.reason, RecaptchaFailureReason.widget);
  });

  test('a container id that is not in the page is a StateError', () async {
    _install(_FakeGrecaptcha());
    await expectLater(
      InPageRecaptchaPresenter(
        containerId: 'not-there',
      ).recaptcha(const RecaptchaRequest(siteKey: _siteKey)),
      throwsStateError,
    );
  });

  test('clear fails a check that is still waiting', () async {
    _install(_FakeGrecaptcha());
    final InPageRecaptchaPresenter presenter = InPageRecaptchaPresenter(
      containerId: 'recaptcha-box',
    );
    final Future<String> token = presenter.recaptcha(
      const RecaptchaRequest(siteKey: _siteKey),
    );
    await _pump();
    presenter.clear();
    await expectLater(token, throwsStateError);
  });

  test('Enterprise executes the action with the site key; no widget', () async {
    final _FakeGrecaptcha fake = _install(
      _FakeGrecaptcha(enterpriseToken: 'enterprise-token'),
    );
    int verified = 0;
    final InPageRecaptchaPresenter presenter = InPageRecaptchaPresenter(
      containerId: 'recaptcha-box',
      onVerified: () => verified++,
      scriptAddress: _loader,
    );
    expect(
      await presenter.recaptcha(
        const RecaptchaRequest(
          siteKey: _siteKey,
          enterpriseAction: 'signInWithPassword',
        ),
      ),
      'enterprise-token',
    );
    expect(fake.enterpriseKeys, <String>[_siteKey]);
    expect(fake.enterpriseActions, <String>['signInWithPassword']);
    expect(fake.containers, isEmpty);
    expect(verified, 1);
  });

  test('Enterprise refusing to make a token is a RecaptchaFailure', () async {
    _install(_FakeGrecaptcha());
    final List<RecaptchaFailure> errors = <RecaptchaFailure>[];
    await expectLater(
      InPageRecaptchaPresenter(
        onError: errors.add,
        scriptAddress: _loader,
      ).recaptcha(
        const RecaptchaRequest(siteKey: _siteKey, enterpriseAction: 'verify'),
      ),
      throwsA(isA<RecaptchaFailure>()),
    );
    expect(errors.single.reason, RecaptchaFailureReason.widget);
  });

  test('RecaptchaFlow picks the in-page presenter on the web', () async {
    _install(_FakeGrecaptcha(autoSolve: 'from-the-page'));
    expect(SecureEnvironment.current().operatingSystem, 'web');
    expect(await RecaptchaFlow(siteKey: _siteKey).run(), 'from-the-page');
  });

  test('RecaptchaFlow.enterprise runs in the page too', () async {
    final _FakeGrecaptcha fake = _install(
      _FakeGrecaptcha(enterpriseToken: 'e-token'),
    );
    // The key's script is loaded once, through a presenter that does not reach Google; the
    // presenter of the environment finds it loaded.
    await InPageRecaptchaPresenter(scriptAddress: _loader).recaptcha(
      const RecaptchaRequest(siteKey: _siteKey, enterpriseAction: 'verify'),
    );
    expect(
      await RecaptchaFlow.enterprise(
        siteKey: _siteKey,
        action: 'sendVerificationCode',
      ).run(),
      'e-token',
    );
    expect(fake.enterpriseActions, <String>['verify', 'sendVerificationCode']);
  });

  test(
    'a page with grecaptcha.enterprise for another key loads the script of this key',
    () async {
      // App Check's provider loaded enterprise.js for its own key: grecaptcha.enterprise exists.
      final _FakeGrecaptcha fake = _install(
        _FakeGrecaptcha(enterpriseToken: 'auth-token'),
      );
      final InPageRecaptchaPresenter presenter = InPageRecaptchaPresenter(
        scriptAddress: _loader,
      );
      const RecaptchaRequest first = RecaptchaRequest(
        siteKey: 'auth-key-1',
        enterpriseAction: 'signInWithPassword',
      );
      expect(await presenter.recaptcha(first), 'auth-token');
      expect(_loaded, hasLength(1));
      expect(_loaded.single.path, '/recaptcha/enterprise.js');
      expect(_loaded.single.queryParameters['render'], 'auth-key-1');
      // Loaded once per key.
      expect(await presenter.recaptcha(first), 'auth-token');
      expect(_loaded, hasLength(1));
      await presenter.recaptcha(
        const RecaptchaRequest(
          siteKey: 'auth-key-2',
          enterpriseAction: 'verify',
        ),
      );
      expect(_loaded.last.queryParameters['render'], 'auth-key-2');
      // A failed execute: the next check loads the key's script again (forceRefresh).
      fake.enterpriseToken = null;
      await expectLater(
        presenter.recaptcha(first),
        throwsA(isA<RecaptchaFailure>()),
      );
      fake.enterpriseToken = 'again';
      expect(await presenter.recaptcha(first), 'again');
      expect(_loaded.map((Uri u) => u.queryParameters['render']), <String>[
        'auth-key-1',
        'auth-key-2',
        'auth-key-1',
      ]);
      expect(fake.enterpriseKeys.last, 'auth-key-1');
    },
  );

  test('repeated checks without a container leave no element behind', () async {
    _install(_FakeGrecaptcha(autoSolve: 'tok'));
    final int before = web.document.documentElement!.childElementCount;
    final InPageRecaptchaPresenter presenter = InPageRecaptchaPresenter();
    for (int i = 0; i < 3; i++) {
      expect(
        await presenter.recaptcha(const RecaptchaRequest(siteKey: _siteKey)),
        'tok',
      );
      // The environment makes a new presenter for every run.
      expect(await RecaptchaFlow(siteKey: _siteKey).run(), 'tok');
    }
    expect(web.document.documentElement!.childElementCount, before);
  });

  test('a second check replaces the first, which fails at once', () async {
    final _FakeGrecaptcha fake = _install(_FakeGrecaptcha());
    final InPageRecaptchaPresenter presenter = InPageRecaptchaPresenter(
      containerId: 'recaptcha-box',
    );
    const RecaptchaRequest request = RecaptchaRequest(siteKey: _siteKey);
    final Future<String> first = presenter.recaptcha(request);
    await _pump();
    final Future<String> second = presenter.recaptcha(request);
    await expectLater(
      first,
      throwsA(
        isA<RecaptchaFailure>().having(
          (RecaptchaFailure e) => e.reason,
          'reason',
          RecaptchaFailureReason.superseded,
        ),
      ),
    );
    await _pump();
    fake.callback('for-the-second');
    expect(await second, 'for-the-second');
    expect(fake.containers, hasLength(1), reason: 'one widget for both');
  });

  test(
    'a script that cannot load: scriptLoad, its tag removed, a retry loads again',
    () async {
      _install(_FakeGrecaptcha(enterpriseToken: 'after-retry'));
      final int before = _headElements();
      const RecaptchaRequest request = RecaptchaRequest(
        siteKey: 'unreachable-key',
        enterpriseAction: 'verify',
      );
      await expectLater(
        InPageRecaptchaPresenter(
          // Refused locally (a closed port that Chrome also treats as unsafe): no network.
          scriptAddress: (Uri google) =>
              Uri.parse('http://127.0.0.1:9/never.js'),
        ).recaptcha(request),
        throwsA(
          isA<RecaptchaFailure>().having(
            (RecaptchaFailure e) => e.reason,
            'reason',
            RecaptchaFailureReason.scriptLoad,
          ),
        ),
      );
      expect(_headElements(), before);
      expect(
        await InPageRecaptchaPresenter(
          scriptAddress: _loader,
        ).recaptcha(request),
        'after-retry',
      );
      expect(_loaded.single.queryParameters['render'], 'unreachable-key');
    },
  );

  test(
    'a script that never calls back: loadTimeout, tag and callback removed',
    () async {
      _install(_FakeGrecaptcha(enterpriseToken: 'unused'));
      final int before = _headElements();
      Uri? google;
      await expectLater(
        InPageRecaptchaPresenter(
          scriptTimeout: const Duration(milliseconds: 200),
          scriptAddress: (Uri address) {
            google = address;
            return Uri.dataFromString('void 0;', mimeType: 'text/javascript');
          },
        ).recaptcha(
          const RecaptchaRequest(
            siteKey: 'silent-key',
            enterpriseAction: 'verify',
          ),
        ),
        throwsA(
          isA<RecaptchaFailure>().having(
            (RecaptchaFailure e) => e.reason,
            'reason',
            RecaptchaFailureReason.loadTimeout,
          ),
        ),
      );
      expect(_headElements(), before);
      expect(globalContext.has(google!.queryParameters['onload']!), isFalse);
    },
  );

  test('without grecaptcha the v2 script is loaded first', () async {
    late _FakeGrecaptcha fake;
    final InPageRecaptchaPresenter presenter = InPageRecaptchaPresenter(
      scriptAddress: (Uri google) {
        // The "script" defines grecaptcha, as api.js does.
        fake = _install(_FakeGrecaptcha(autoSolve: 'loaded'));
        return _loader(google);
      },
    );
    expect(
      await presenter.recaptcha(
        const RecaptchaRequest(siteKey: _siteKey, languageCode: 'ro'),
      ),
      'loaded',
    );
    expect(_loaded.single.path, '/recaptcha/api.js');
    expect(_loaded.single.queryParameters['render'], 'explicit');
    expect(_loaded.single.queryParameters['hl'], 'ro');
    expect(fake.executed, <int>[1]);
  });
}
