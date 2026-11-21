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
  final String? enterpriseToken;

  /// When set, `execute(id)` of the v2 API answers with this token on the next turn.
  final String? autoSolve;

  bool withEnterprise = true;
  final List<web.Element> containers = <web.Element>[];
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

void main() {
  late web.HTMLDivElement box;

  setUp(() {
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
      final web.Element element = fake.containers.single;
      expect(element.parentElement, web.document.documentElement);
      presenter.clear();
      expect(element.isConnected, isFalse);
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
      InPageRecaptchaPresenter(onError: errors.add).recaptcha(
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
    expect(
      await RecaptchaFlow.enterprise(
        siteKey: _siteKey,
        action: 'sendVerificationCode',
      ).run(),
      'e-token',
    );
    expect(fake.enterpriseActions, <String>['sendVerificationCode']);
  });
}
