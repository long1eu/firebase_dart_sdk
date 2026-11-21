// The constants of ProviderId, SignInMethod, FactorId and AuthErrorCode agree with the classes that use them.

import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';
import 'package:test/test.dart';

void main() {
  test('ProviderId and SignInMethod match the provider classes', () {
    expect(
      <String>[
        ProviderId.password,
        ProviderId.google,
        ProviderId.apple,
        ProviderId.facebook,
        ProviderId.github,
        ProviderId.twitter,
        ProviderId.microsoft,
        ProviderId.yahoo,
      ],
      <String>[
        EmailAuthProvider.PROVIDER_ID,
        GoogleAuthProvider.PROVIDER_ID,
        AppleAuthProvider.PROVIDER_ID,
        FacebookAuthProvider.PROVIDER_ID,
        GithubAuthProvider.PROVIDER_ID,
        TwitterAuthProvider.PROVIDER_ID,
        MicrosoftAuthProvider.PROVIDER_ID,
        YahooAuthProvider.PROVIDER_ID,
      ],
    );
    expect(
      <String>[
        SignInMethod.emailPassword,
        SignInMethod.emailLink,
        SignInMethod.google,
        SignInMethod.apple,
        SignInMethod.facebook,
        SignInMethod.github,
        SignInMethod.twitter,
        SignInMethod.microsoft,
        SignInMethod.yahoo,
      ],
      <String>[
        EmailAuthProvider.EMAIL_PASSWORD_SIGN_IN_METHOD,
        EmailAuthProvider.EMAIL_LINK_SIGN_IN_METHOD,
        GoogleAuthProvider.GOOGLE_SIGN_IN_METHOD,
        AppleAuthProvider.APPLE_SIGN_IN_METHOD,
        FacebookAuthProvider.FACEBOOK_SIGN_IN_METHOD,
        GithubAuthProvider.GITHUB_SIGN_IN_METHOD,
        TwitterAuthProvider.TWITTER_SIGN_IN_METHOD,
        MicrosoftAuthProvider.MICROSOFT_SIGN_IN_METHOD,
        YahooAuthProvider.YAHOO_SIGN_IN_METHOD,
      ],
    );
    expect(
      EmailAuthProvider.credential(
        email: 'a@example.com',
        password: 'p',
      ).signInMethod,
      SignInMethod.emailPassword,
    );
  });

  test('FactorId matches MultiFactorInfo', () {
    expect(FactorId.phone, MultiFactorInfo.phoneFactorId);
    expect(FactorId.totp, MultiFactorInfo.totpFactorId);
  });

  test('AuthErrorCode holds the codes the server errors map to', () {
    for (final (String server, String code) in <(String, String)>[
      ('EMAIL_EXISTS', AuthErrorCode.emailAlreadyInUse),
      ('INVALID_LOGIN_CREDENTIALS', AuthErrorCode.invalidCredential),
      ('TOKEN_EXPIRED', AuthErrorCode.userTokenExpired),
      ('USER_DISABLED', AuthErrorCode.userDisabled),
      ('TOO_MANY_ATTEMPTS_TRY_LATER', AuthErrorCode.tooManyRequests),
      ('SECOND_FACTOR_EXISTS', AuthErrorCode.secondFactorAlreadyInUse),
      ('MISSING_CONTINUE_URI', AuthErrorCode.internalError),
    ]) {
      expect(
        FirebaseAuthException.fromServer(server, httpStatus: 400).code,
        code,
        reason: server,
      );
    }
    expect(
      AuthErrorCode.passwordDoesNotMeetRequirements,
      'password-does-not-meet-requirements',
    );
    expect(AuthErrorCode.cancelled, 'cancelled');
  });
}
