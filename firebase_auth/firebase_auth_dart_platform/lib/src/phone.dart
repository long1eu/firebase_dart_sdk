// Phone sign-in on top of the client's verifyPhoneNumber and phone credentials:
// the ConfirmationResult of signInWithPhoneNumber and linkWithPhoneNumber, the
// RecaptchaVerifier that firebase_auth creates for them, and the reCAPTCHA
// Enterprise token source of the web.

import 'package:firebase_auth_dart_platform/src/convert.dart';
import 'package:firebase_auth_dart_platform/src/firebase_auth.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart'
    as dart_auth;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:secure_flow/secure_flow.dart';

/// What a [DartConfirmationResult] does with the credential of its code: sign
/// in, or link it to the user that asked.
typedef PhoneConfirmation =
    Future<dart_auth.UserCredential> Function(
      dart_auth.PhoneAuthCredential credential,
    );

/// Makes the in-page presenter of a `RecaptchaVerifier` on the web: the
/// element [containerId] (null: a new invisible one) and the callbacks of the
/// verifier.
typedef InPagePresenterFactory =
    InPageRecaptchaPresenter Function({
      String? containerId,
      void Function()? onVerified,
      void Function()? onExpired,
      void Function(RecaptchaFailure failure)? onError,
    });

/// The result of `signInWithPhoneNumber` and `User.linkWithPhoneNumber`: the
/// SMS was sent; [confirm] finishes with its code.
class DartConfirmationResult extends ConfirmationResultPlatform {
  DartConfirmationResult(this._auth, super.verificationId, this._confirmation);

  final DartFirebaseAuth _auth;
  final PhoneConfirmation _confirmation;

  /// Signs in (or links) with [verificationCode], the code of the SMS.
  @override
  Future<UserCredentialPlatform> confirm(String verificationCode) => guard(
    _auth,
    () async => _auth.resultOf(
      await _confirmation(
        dart_auth.PhoneAuthProvider.credential(
          verificationId: verificationId,
          verificationCode: verificationCode,
        ),
      ),
    ),
  );
}

/// The `RecaptchaVerifier` that `firebase_auth` creates for
/// `signInWithPhoneNumber` and `linkWithPhoneNumber` (one of its own when the
/// app passes none).
///
/// * On the web ([inPage]) it is a [DartInPageRecaptchaVerifier]: the
///   reCAPTCHA v2 widget rendered into the element `container` of the page
///   (invisible, in a new element, without one) by an
///   [InPageRecaptchaPresenter], with the `size`, `theme` and callbacks of the
///   verifier. The phone members take their reCAPTCHA v2 token from it, unless
///   `FirebaseAuthDart.use` got an `appVerification`.
/// * Elsewhere it renders nothing: the proof of a phone request is the
///   `AppVerification` passed to `FirebaseAuthDart.use` (by default the
///   reCAPTCHA page of the client in the system browser), which the phone
///   members use whatever verifier they get. [verify] throws `unimplemented`.
class DartRecaptchaVerifierFactory extends RecaptchaVerifierFactoryPlatform {
  /// [inPage] (by default on the web) makes in-page verifiers with
  /// [presenterFor] (by default an [InPageRecaptchaPresenter]).
  DartRecaptchaVerifierFactory({
    bool? inPage,
    InPagePresenterFactory? presenterFor,
  }) : inPage = inPage ?? kIsWeb,
       _presenterFor = presenterFor ?? _inPagePresenter;

  /// Whether the verifiers render into the page.
  final bool inPage;

  final InPagePresenterFactory _presenterFor;

  static InPageRecaptchaPresenter _inPagePresenter({
    String? containerId,
    void Function()? onVerified,
    void Function()? onExpired,
    void Function(RecaptchaFailure failure)? onError,
  }) => InPageRecaptchaPresenter(
    containerId: containerId,
    onVerified: onVerified,
    onExpired: onExpired,
    onError: onError,
  );

  @override
  RecaptchaVerifierFactoryPlatform delegateFor({
    required FirebaseAuthPlatform auth,
    String? container,
    RecaptchaVerifierSize size = RecaptchaVerifierSize.normal,
    RecaptchaVerifierTheme theme = RecaptchaVerifierTheme.light,
    RecaptchaVerifierOnSuccess? onSuccess,
    RecaptchaVerifierOnError? onError,
    RecaptchaVerifierOnExpired? onExpired,
  }) {
    if (!inPage) {
      return this;
    }
    final String? containerId = container == null || container.isEmpty
        ? null
        : container;
    return DartInPageRecaptchaVerifier(
      auth,
      _presenterFor(
        containerId: containerId,
        onVerified: onSuccess,
        onExpired: onExpired,
        onError: onError == null
            ? null
            : (RecaptchaFailure failure) =>
                  onError(recaptchaExceptionOf(failure)),
      ),
      size: switch (size) {
        RecaptchaVerifierSize.normal => RecaptchaSize.normal,
        RecaptchaVerifierSize.compact => RecaptchaSize.compact,
      },
      theme: switch (theme) {
        RecaptchaVerifierTheme.light => RecaptchaTheme.light,
        RecaptchaVerifierTheme.dark => RecaptchaTheme.dark,
      },
    );
  }

  @override
  String get type => 'recaptcha';

  @override
  void clear() {}

  @override
  Future<int> render() async => 0;

  @override
  Future<String> verify() async => throw unimplemented(
    'RecaptchaVerifier.verify',
    'the reCAPTCHA token of a phone request comes from the AppVerification '
        'passed to FirebaseAuthDart.use.',
  );
}

/// A `RecaptchaVerifier` on the web: a reCAPTCHA v2 widget in the page,
/// rendered by [presenter] with the site key of the project
/// (`getRecaptchaSiteKey` of the app's client) and the language of the client.
class DartInPageRecaptchaVerifier extends RecaptchaVerifierFactoryPlatform {
  /// A verifier of [auth] (the instance of an app) that renders with
  /// [presenter] in [size] and [theme].
  DartInPageRecaptchaVerifier(
    this._auth,
    this.presenter, {
    required this.size,
    required this.theme,
  });

  final FirebaseAuthPlatform _auth;

  /// Renders the widget and returns its tokens.
  final InPageRecaptchaPresenter presenter;

  /// The size of the widget (invisible without a container).
  final RecaptchaSize size;

  /// The theme of the widget.
  final RecaptchaTheme theme;

  DartFirebaseAuth get _app => _auth as DartFirebaseAuth;

  @override
  String get type => 'recaptcha';

  /// Renders the widget (once) and returns its id.
  @override
  Future<int> render() => _guard(() async {
    final dart_auth.FirebaseUserAuth client = _app.client;
    return presenter.render(
      RecaptchaRequest(
        siteKey: await client.getRecaptchaSiteKey(),
        languageCode: client.languageCode,
        size: size,
        theme: theme,
      ),
    );
  });

  /// A token of the widget for the site key of the project.
  @override
  Future<String> verify() => _guard(() async {
    final dart_auth.FirebaseUserAuth client = _app.client;
    return tokenFor(
      dart_auth.RecaptchaV2Request(
        siteKey: await client.getRecaptchaSiteKey(),
        action: dart_auth.RecaptchaAction.sendVerificationCode,
        languageCode: client.languageCode,
      ),
    );
  });

  /// Removes the widget.
  @override
  void clear() => presenter.clear();

  /// The proof of a phone request: a token of this widget for each request.
  dart_auth.AppVerification get appVerification =>
      dart_auth.AppVerification.recaptchaV2(tokenFor);

  /// A token of this widget for [request] (a `RecaptchaFlow` run with
  /// [presenter]); the client turns its errors into `FirebaseAuthException`s.
  Future<String> tokenFor(dart_auth.RecaptchaV2Request request) =>
      RecaptchaFlow(
        siteKey: request.siteKey,
        languageCode: request.languageCode,
        size: size,
        theme: theme,
      ).run(presenter: presenter);

  Future<T> _guard<T>(Future<T> Function() body) => guard(_app, () async {
    try {
      return await body();
    } on RecaptchaFailure catch (e, stackTrace) {
      Error.throwWithStackTrace(recaptchaExceptionOf(e), stackTrace);
    } on SecureFlowTimeout catch (e, stackTrace) {
      Error.throwWithStackTrace(
        FirebaseAuthException(code: 'timeout', message: e.message),
        stackTrace,
      );
    }
  });
}

/// [failure] as the exception of the platform interface, with the codes of
/// the JS SDK's reCAPTCHA loader (those of the client).
FirebaseAuthException recaptchaExceptionOf(RecaptchaFailure failure) =>
    FirebaseAuthException(
      code: switch (failure.reason) {
        RecaptchaFailureReason.scriptLoad => 'internal-error',
        RecaptchaFailureReason.loadTimeout ||
        RecaptchaFailureReason.widget => 'network-request-failed',
        RecaptchaFailureReason.noToken => 'missing-app-credential',
      },
      message: failure.message,
    );

/// The reCAPTCHA Enterprise token source of the web: `RecaptchaFlow.enterprise`
/// in the app's page ([InPageRecaptchaPresenter], no widget), for the site key
/// and action the client asks for.
dart_auth.RecaptchaEnterpriseVerification inPageRecaptchaEnterprise() =>
    dart_auth.RecaptchaEnterpriseVerification(
      (dart_auth.RecaptchaEnterpriseRequest request) =>
          RecaptchaFlow.enterprise(
            siteKey:
                request.siteKey ??
                (throw StateError(
                  'The reCAPTCHA Enterprise configuration has no site key.',
                )),
            action: request.action.value,
            languageCode: request.languageCode,
          ).run(presenter: InPageRecaptchaPresenter()),
    );
