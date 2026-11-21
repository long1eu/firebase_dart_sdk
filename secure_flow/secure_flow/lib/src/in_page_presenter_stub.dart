import 'package:secure_flow/src/errors.dart';
import 'package:secure_flow/src/flows/recaptcha_flow.dart';
import 'package:secure_flow/src/presenter.dart';

Never _unsupported() => throw UnsupportedError(
  'InPageRecaptchaPresenter renders into a web page: it needs a web build of the app.',
);

/// Renders a reCAPTCHA into the page the app runs in. Needs a web build (`dart:js_interop`); on
/// this platform [recaptcha], [render] and [clear] throw an [UnsupportedError].
class InPageRecaptchaPresenter implements RecaptchaPresenter {
  /// See the web implementation.
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

  @override
  SecurePresenterKind get kind => SecurePresenterKind.inPage;

  @override
  Future<String> recaptcha(RecaptchaRequest request) async => _unsupported();

  /// Renders the v2 widget of [request]. Throws an [UnsupportedError] on this platform.
  Future<int> render(RecaptchaRequest request) async => _unsupported();

  /// Removes the widget. Throws an [UnsupportedError] on this platform.
  void clear() => _unsupported();
}
