// The reCAPTCHA Enterprise part of the requests of FirebaseUserAuth: the cached configuration of
// the project and its tenants, and when and how a token goes with a request
// (`handleRecaptchaFlow` and `injectRecaptchaFields` of the JS SDK,
// `platform_browser/recaptcha/recaptcha_enterprise_verifier.ts`). Not exported.

import 'package:firebase_app_dart/internal.dart' show Log;

import 'app_verification.dart';
import 'auth_exception.dart';
import 'recaptcha_config.dart';
import 'secure_flow_errors.dart';

/// Reads `v2/recaptchaConfig` for [tenantId] and [clientType] and returns the decoded answer.
typedef RecaptchaConfigFetch =
    Future<Map<String, Object?>> Function(
      String? tenantId,
      RecaptchaClientType clientType,
    );

/// Sends a request with [body] and returns the decoded answer.
typedef RecaptchaSend =
    Future<Map<String, Object?>> Function(Map<String, Object?> body);

/// The `captchaResponse` the JS SDK sends when it has no Enterprise token (`FAKE_TOKEN`): with a
/// reCAPTCHA v2 token next to it, it tells the backend that the v2 token is the proof.
const String noRecaptchaToken = 'NO_RECAPTCHA';

/// The errors after which an SMS request under AUDIT is sent again with the v2 token.
const Set<String> _auditFallbackCodes = <String>{
  'missing-recaptcha-token',
  'invalid-app-credential',
};

/// The reCAPTCHA Enterprise configuration and tokens of one client.
final class RecaptchaEnterprise {
  /// [source] makes the tokens (none: requests go out without one); [fetch] reads the
  /// configuration.
  RecaptchaEnterprise({required this.source, required this.fetch});

  /// The token source of the client, or null.
  final RecaptchaEnterpriseVerification? source;

  /// Reads the configuration.
  final RecaptchaConfigFetch fetch;

  /// The configurations read so far: the project's under null, a tenant's under its id
  /// (`_agentRecaptchaConfig` and `_tenantRecaptchaConfigs`).
  final Map<String?, RecaptchaConfig> _configs = <String?, RecaptchaConfig>{};

  /// The client type of the tokens, which the configuration is read for: that of [source], web
  /// without one (as the JS SDK always asks).
  RecaptchaClientType get clientType =>
      source?.clientType ?? RecaptchaClientType.web;

  /// The configuration read for [tenantId], or null.
  RecaptchaConfig? configOf(String? tenantId) => _configs[tenantId];

  /// Reads the configuration of [tenantId] and keeps it (`_initializeRecaptchaConfig`).
  Future<RecaptchaConfig> initialize(String? tenantId) async {
    final RecaptchaConfig config = RecaptchaConfig.fromResponse(
      await fetch(tenantId, clientType),
    );
    _configs[tenantId] = config;
    return config;
  }

  /// Sends a request that the email and password provider may protect (`handleRecaptchaFlow` with
  /// `EMAIL_PASSWORD_PROVIDER`): with a token when the configuration of [tenantId] read so far
  /// protects the provider and there is a [source]; otherwise without one, and once more with a
  /// token when the backend answers `missing-recaptcha-token` and there is a [source].
  Future<Map<String, Object?>> sendEmailPassword({
    required String? tenantId,
    required RecaptchaAction action,
    required Map<String, Object?> body,
    required RecaptchaSend send,
    String? languageCode,
  }) async {
    final bool protected =
        configOf(
          tenantId,
        )?.isProviderEnabled(RecaptchaProvider.emailPassword) ??
        false;
    if (protected && source != null) {
      return send(await _withToken(tenantId, action, body, languageCode));
    }
    try {
      return await send(body);
    } on FirebaseAuthException catch (e) {
      if (e.code != 'missing-recaptcha-token' || source == null) {
        rethrow;
      }
      Log.i(
        'FirebaseUserAuth',
        '${action.value} is protected by reCAPTCHA Enterprise for this project; '
            'sending it again with a token.',
      );
      return send(await _withToken(tenantId, action, body, languageCode));
    }
  }

  /// Sends an SMS request that the phone provider may protect (`handleRecaptchaFlow` with
  /// `PHONE_PROVIDER`), whose proof would otherwise be the v2 token of [v2Fields]; [secrets]
  /// receives every token.
  ///
  /// The configuration of [tenantId] is read first when it has not been (a failure counts as "not
  /// protected", as in the JS SDK). Protected: the Enterprise token goes with the request; under
  /// AUDIT, `missing-recaptcha-token` and `invalid-app-credential` send it again with the v2 token.
  /// Not protected: the v2 token, with `captchaResponse: NO_RECAPTCHA` and the client type and
  /// version, as the JS SDK sends it.
  Future<T> sendPhone<T>({
    required String? tenantId,
    required RecaptchaAction action,
    required Future<Map<String, Object?>> Function() v2Fields,
    required Future<T> Function(Map<String, Object?> proof) send,
    required List<String?> secrets,
    String? languageCode,
  }) async {
    RecaptchaConfig? config = configOf(tenantId);
    if (config == null) {
      try {
        config = await initialize(tenantId);
      } on Object catch (e) {
        Log.i(
          'FirebaseUserAuth',
          'The reCAPTCHA Enterprise configuration could not be read '
              '(${e.runtimeType}); the request carries the reCAPTCHA v2 token.',
        );
      }
    }
    Future<Map<String, Object?>> withV2() async => <String, Object?>{
      ...await v2Fields(),
      ..._markers(noRecaptchaToken),
    };
    if (config == null || !config.isProviderEnabled(RecaptchaProvider.phone)) {
      return send(await withV2());
    }
    final String token = await _token(tenantId, action, languageCode);
    secrets.add(token);
    try {
      return await send(_markers(token));
    } on FirebaseAuthException catch (e) {
      final bool audit =
          config.enforcementState(RecaptchaProvider.phone) ==
          RecaptchaEnforcementState.audit;
      if (!audit || !_auditFallbackCodes.contains(e.code)) {
        rethrow;
      }
      Log.i(
        'FirebaseUserAuth',
        'reCAPTCHA Enterprise did not verify ${action.value}; sending it again with the '
            'reCAPTCHA v2 token.',
      );
      return send(await withV2());
    }
  }

  /// `captchaResponse`, `clientType` and `recaptchaVersion` with [captchaResponse].
  Map<String, Object?> _markers(String captchaResponse) => <String, Object?>{
    'captchaResponse': captchaResponse,
    'clientType': clientType.value,
    'recaptchaVersion': 'RECAPTCHA_ENTERPRISE',
  };

  /// [body] with a token for [action] (`injectRecaptchaFields`); `getOobCode` takes it as
  /// `captchaResp`, the others as `captchaResponse`.
  Future<Map<String, Object?>> _withToken(
    String? tenantId,
    RecaptchaAction action,
    Map<String, Object?> body,
    String? languageCode,
  ) async {
    final String token = await _token(tenantId, action, languageCode);
    return <String, Object?>{
      ...body,
      action == RecaptchaAction.getOobCode ? 'captchaResp' : 'captchaResponse':
          token,
      'clientType': clientType.value,
      'recaptchaVersion': 'RECAPTCHA_ENTERPRISE',
    };
  }

  /// A token for [action] from [source], with the site key of the configuration of [tenantId]
  /// (read when it has not been). When that fails, the configuration is read again and the source
  /// asked once more (`verify(action, forceRefresh: true)` of the JS SDK), except after a timeout
  /// or a cancel of the person.
  Future<String> _token(
    String? tenantId,
    RecaptchaAction action,
    String? languageCode,
  ) async {
    try {
      return await _tokenOnce(tenantId, action, languageCode, refresh: false);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'timeout' || e.code == 'user-cancelled') {
        rethrow;
      }
    } on Object {
      // Any other failure: a stale site key, a script that did not load. Try once more.
    }
    return _tokenOnce(tenantId, action, languageCode, refresh: true);
  }

  Future<String> _tokenOnce(
    String? tenantId,
    RecaptchaAction action,
    String? languageCode, {
    required bool refresh,
  }) async {
    final RecaptchaConfig config =
        (refresh ? null : configOf(tenantId)) ?? await initialize(tenantId);
    final String? siteKey = config.siteKey;
    if (siteKey == null) {
      throw const FirebaseAuthException(
        code: 'recaptcha-not-enabled',
        message:
            'The reCAPTCHA Enterprise configuration of the project has no site key.',
      );
    }
    final RecaptchaEnterpriseRequest request = RecaptchaEnterpriseRequest(
      action: action,
      siteKey: siteKey,
      languageCode: languageCode,
    );
    final String token = await secureFlowErrorsToAuth(
      () async => source!.token(request),
    );
    if (token.isEmpty) {
      throw const FirebaseAuthException(
        code: 'missing-recaptcha-token',
        message:
            'The reCAPTCHA Enterprise token source returned an empty token.',
      );
    }
    return token;
  }
}
