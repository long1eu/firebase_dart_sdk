import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:secure_flow/src/dom_web.dart' as web;
import 'package:secure_flow/src/errors.dart';
import 'package:secure_flow/src/flows/recaptcha_flow.dart';
import 'package:secure_flow/src/presenter.dart';
import 'package:secure_flow/src/recaptcha_scripts.dart';

/// `window.grecaptcha`, once Google's script (or a page of the app) defined it.
@JS('grecaptcha')
external _Grecaptcha? get _grecaptcha;

/// The parts of `grecaptcha` this presenter calls: the v2 widget API and `enterprise`.
extension type _Grecaptcha._(JSObject _) implements JSObject {
  /// `grecaptcha.render` as a value, to see whether the v2 API is there.
  @JS('render')
  external JSAny? get renderFunction;

  /// Renders a v2 widget into [container]; returns its id.
  @JS('render')
  external JSNumber renderWidget(web.Element container, JSObject parameters);

  /// Starts the invisible widget [id].
  external void execute(JSNumber id);

  /// The token of widget [id], empty when there is none.
  external JSString getResponse(JSNumber id);

  /// Clears widget [id] (its token too).
  external void reset(JSNumber id);

  /// The reCAPTCHA Enterprise API, or null.
  external _Enterprise? get enterprise;
}

/// `grecaptcha.enterprise`.
extension type _Enterprise._(JSObject _) implements JSObject {
  /// Calls [callback] once the API is ready.
  external void ready(JSFunction callback);

  /// A token for [siteKey] and `{action}`.
  @JS('execute')
  external JSPromise<JSString> executeAction(
    JSString siteKey,
    JSObject options,
  );
}

/// The loads of Google's scripts, shared by every presenter of the page (one script of each kind
/// per page, like the JS SDK); reset after a failed load so that the next check tries again.
Future<void>? _v2Load;
Future<void>? _enterpriseLoad;
int _callbacks = 0;

/// Renders a reCAPTCHA into the page the app runs in (a web build of the app) and returns its
/// token, without the loopback server: the presenter of kind [SecurePresenterKind.inPage] that
/// `SecureEnvironment.current()` offers on the web, which `RecaptchaFlow` takes first.
///
/// * reCAPTCHA v2: the widget goes into a new element inside the element whose id is
///   [containerId], in the size and theme of the request (the system's light or dark scheme
///   without a theme). Without a [containerId] the widget is invisible, in a new element at the
///   end of the document (as the `RecaptchaVerifier` of FlutterFire's web plugin does). A visible
///   widget waits for the person to check the box; an invisible one starts at once. The widget is
///   reset after each token, so that the next check needs a new one.
/// * reCAPTCHA Enterprise: `grecaptcha.enterprise.execute(siteKey, {action})`, as the JS SDK's
///   Enterprise verifier does; no widget is rendered (Google shows its badge) and [containerId] is
///   not used.
///
/// Google's script (`api.js` or `enterprise.js`) is loaded once per page, unless the page already
/// has `grecaptcha` with the API the check needs. It must load within [scriptTimeout]
/// ([RecaptchaFailureReason.loadTimeout]); a script that fails to load (a content security policy
/// of the page that does not allow `https://www.google.com/recaptcha/` and
/// `https://www.gstatic.com/recaptcha/`, no network) is [RecaptchaFailureReason.scriptLoad].
class InPageRecaptchaPresenter implements RecaptchaPresenter {
  /// A presenter that renders into the element [containerId] (null: a new invisible one) and
  /// tells [onVerified] when the person passed the check, [onExpired] when a v2 token expired
  /// unused, and [onError] when the widget reports an error (the pending check fails with that
  /// [RecaptchaFailure] too).
  InPageRecaptchaPresenter({
    this.containerId,
    this.onVerified,
    this.onExpired,
    this.onError,
    this.scriptTimeout = const Duration(seconds: 30),
  });

  /// The id of the element the widget goes into, or null for a new invisible one.
  final String? containerId;

  /// Called when the person passed the check.
  final void Function()? onVerified;

  /// Called when a token of the v2 widget expired before it was used.
  final void Function()? onExpired;

  /// Called when the widget reports an error.
  final void Function(RecaptchaFailure failure)? onError;

  /// How long Google's script may take to load.
  final Duration scriptTimeout;

  Future<JSNumber>? _rendering;
  web.Element? _element;
  RecaptchaSize _size = RecaptchaSize.invisible;
  Completer<String>? _pending;

  @override
  SecurePresenterKind get kind => SecurePresenterKind.inPage;

  @override
  Future<String> recaptcha(RecaptchaRequest request) =>
      request.isEnterprise ? _enterpriseToken(request) : _v2Token(request);

  /// Renders the v2 widget of [request] once (later calls return the same widget until [clear])
  /// and returns its id. Throws an [ArgumentError] for an Enterprise request, which has no widget,
  /// and a [StateError] when the page has no element [containerId].
  Future<int> render(RecaptchaRequest request) async {
    if (request.isEnterprise) {
      throw ArgumentError.value(
        request,
        'request',
        'is a reCAPTCHA Enterprise check, which has no widget to render',
      );
    }
    return (await (_rendering ??= _render(request))).toDartInt;
  }

  /// Removes the widget and the element it was rendered into; a check that is still waiting fails
  /// with a [StateError]. The next check renders a new widget.
  void clear() {
    final Completer<String>? pending = _pending;
    _pending = null;
    _rendering = null;
    _element?.remove();
    _element = null;
    pending?.completeError(
      StateError('The reCAPTCHA presenter was cleared before the check ended.'),
    );
  }

  Future<String> _v2Token(RecaptchaRequest request) async {
    final JSNumber id = await (_rendering ??= _render(request));
    final _Grecaptcha grecaptcha = _grecaptcha!;
    final String solved = grecaptcha.getResponse(id).toDart;
    if (solved.isNotEmpty) {
      grecaptcha.reset(id);
      return solved;
    }
    final Completer<String> pending = Completer<String>();
    _pending = pending;
    if (_size == RecaptchaSize.invisible) {
      grecaptcha.execute(id);
    }
    try {
      return await pending.future;
    } finally {
      if (identical(_pending, pending)) {
        _pending = null;
      }
      if (_rendering != null) {
        grecaptcha.reset(id);
      }
    }
  }

  Future<JSNumber> _render(RecaptchaRequest request) async {
    try {
      await _loadV2(request.languageCode);
      final web.Element element = web.HTMLDivElement();
      _container().appendChild(element);
      _element = element;
      _size = containerId == null ? RecaptchaSize.invisible : request.size;
      return _grecaptcha!.renderWidget(element, _parameters(request));
    } on Object {
      _rendering = null;
      rethrow;
    }
  }

  /// The element [containerId], or the document element without one.
  web.Element _container() {
    final String? id = containerId;
    if (id == null) {
      return web.document.documentElement!;
    }
    final web.Element? element = web.document.getElementById(id);
    if (element == null) {
      throw StateError('The page has no element with the id "$id".');
    }
    return element;
  }

  JSObject _parameters(RecaptchaRequest request) {
    final bool dark = web.mediaMatches('(prefers-color-scheme: dark)');
    return JSObject()
      ..['sitekey'] = request.siteKey.toJS
      ..['size'] = _size.value.toJS
      ..['theme'] = (request.theme?.value ?? (dark ? 'dark' : 'light')).toJS
      ..['callback'] = _onToken.toJS
      ..['expired-callback'] = _onExpired.toJS
      ..['error-callback'] = _onError.toJS;
  }

  void _onToken(JSString token) {
    onVerified?.call();
    final Completer<String>? pending = _pending;
    _pending = null;
    pending?.complete(token.toDart);
  }

  void _onExpired() => onExpired?.call();

  void _onError() {
    const RecaptchaFailure failure = RecaptchaFailure(
      RecaptchaFailureReason.widget,
      'The reCAPTCHA widget reported an error (usually the network).',
    );
    onError?.call(failure);
    final Completer<String>? pending = _pending;
    _pending = null;
    pending?.completeError(failure);
  }

  Future<String> _enterpriseToken(RecaptchaRequest request) async {
    await _loadEnterprise(request.siteKey, request.languageCode);
    final _Enterprise enterprise =
        _grecaptcha?.enterprise ??
        (throw const RecaptchaFailure(
          RecaptchaFailureReason.scriptLoad,
          'The reCAPTCHA Enterprise script loaded without grecaptcha.enterprise.',
        ));
    final Completer<void> ready = Completer<void>();
    enterprise.ready((() => ready.complete()).toJS);
    await ready.future;
    final String token;
    try {
      token =
          (await enterprise
                  .executeAction(
                    request.siteKey.toJS,
                    JSObject()..['action'] = request.enterpriseAction!.toJS,
                  )
                  .toDart)
              .toDart;
    } on Object {
      const RecaptchaFailure failure = RecaptchaFailure(
        RecaptchaFailureReason.widget,
        'reCAPTCHA Enterprise could not make a token.',
      );
      onError?.call(failure);
      throw failure;
    }
    onVerified?.call();
    return token;
  }

  Future<void> _loadV2(String? languageCode) {
    if (_grecaptcha?.renderFunction != null) {
      return Future<void>.value();
    }
    return _v2Load ??=
        _load(
          (String onload) =>
              recaptchaV2ScriptUrl(onload: onload, languageCode: languageCode),
        ).catchError((Object error, StackTrace stackTrace) {
          _v2Load = null;
          Error.throwWithStackTrace(error, stackTrace);
        });
  }

  Future<void> _loadEnterprise(String siteKey, String? languageCode) {
    if (_grecaptcha?.enterprise != null) {
      return Future<void>.value();
    }
    return _enterpriseLoad ??=
        _load(
          (String onload) => recaptchaEnterpriseScriptUrl(
            siteKey: siteKey,
            onload: onload,
            languageCode: languageCode,
          ),
        ).catchError((Object error, StackTrace stackTrace) {
          _enterpriseLoad = null;
          Error.throwWithStackTrace(error, stackTrace);
        });
  }

  /// Adds the script at the address [url] makes for a new global onload callback, and completes
  /// when Google's script calls it.
  Future<void> _load(Uri Function(String onload) url) {
    final String callback = '__secureFlowRecaptchaLoaded${_callbacks++}';
    final Completer<void> loaded = Completer<void>();
    late final Timer timer;
    void finish([RecaptchaFailure? failure]) {
      timer.cancel();
      globalContext.delete(callback.toJS);
      if (loaded.isCompleted) {
        return;
      }
      failure == null ? loaded.complete() : loaded.completeError(failure);
    }

    timer = Timer(
      scriptTimeout,
      () => finish(
        RecaptchaFailure(
          RecaptchaFailureReason.loadTimeout,
          'The reCAPTCHA script did not load within ${scriptTimeout.inSeconds} seconds.',
        ),
      ),
    );
    globalContext[callback] = (() => finish()).toJS;
    final web.HTMLScriptElement script = web.HTMLScriptElement()
      ..src = url(callback).toString()
      ..async = true;
    script.onerror = ((web.Event _) => finish(
      const RecaptchaFailure(
        RecaptchaFailureReason.scriptLoad,
        'The reCAPTCHA script could not load (offline, blocked, or refused by the page).',
      ),
    )).toJS;
    (web.document.head ?? web.document.documentElement!).appendChild(script);
    return loaded.future;
  }
}
