import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';

import 'convert.dart';

// Multi-factor authentication is not supported yet. Each class below is where
// it goes: the resolver gets the pending credential of the sign-in as its
// session id, and the factors of a challenge as its hints, already today.

/// The multi-factor API of a user: every member throws `unimplemented`.
class DartMultiFactor extends MultiFactorPlatform {
  DartMultiFactor(super.auth);

  @override
  Future<MultiFactorSession> getSession() async =>
      throw unimplemented('MultiFactor.getSession', noMultiFactor);

  @override
  Future<void> enroll(
    MultiFactorAssertionPlatform assertion, {
    String? displayName,
  }) async => throw unimplemented('MultiFactor.enroll', noMultiFactor);

  @override
  Future<void> unenroll({
    String? factorUid,
    MultiFactorInfo? multiFactorInfo,
  }) async => throw unimplemented('MultiFactor.unenroll', noMultiFactor);

  @override
  Future<List<MultiFactorInfo>> getEnrolledFactors() async =>
      throw unimplemented('MultiFactor.getEnrolledFactors', noMultiFactor);
}

/// The resolver of a `multi-factor-auth-required` error: [hints] lists the
/// enrolled factors, the [session] id is the backend's pending credential, and
/// [resolveSignIn] throws `unimplemented`.
class DartMultiFactorResolver extends MultiFactorResolverPlatform {
  DartMultiFactorResolver(super.hints, super.session);

  @override
  Future<UserCredentialPlatform> resolveSignIn(
    MultiFactorAssertionPlatform assertion,
  ) async =>
      throw unimplemented('MultiFactorResolver.resolveSignIn', noMultiFactor);
}

/// `PhoneMultiFactorGenerator`: phone factors need SMS verification, which
/// this package does not have.
class DartPhoneMultiFactorGenerator extends PhoneMultiFactorGeneratorPlatform {
  @override
  MultiFactorAssertionPlatform getAssertion(PhoneAuthCredential credential) =>
      throw unimplemented('PhoneMultiFactorGenerator.getAssertion', noPhone);
}

/// `TotpMultiFactorGenerator`: every member throws `unimplemented` until TOTP
/// is supported.
class DartTotpMultiFactorGenerator extends TotpMultiFactorGeneratorPlatform {
  @override
  Future<TotpSecretPlatform> generateSecret(MultiFactorSession session) async =>
      throw unimplemented(
        'TotpMultiFactorGenerator.generateSecret',
        noMultiFactor,
      );

  @override
  Future<MultiFactorAssertionPlatform> getAssertionForEnrollment(
    TotpSecretPlatform secret,
    String oneTimePassword,
  ) async => throw unimplemented(
    'TotpMultiFactorGenerator.getAssertionForEnrollment',
    noMultiFactor,
  );

  @override
  Future<MultiFactorAssertionPlatform> getAssertionForSignIn(
    String enrollmentId,
    String oneTimePassword,
  ) async => throw unimplemented(
    'TotpMultiFactorGenerator.getAssertionForSignIn',
    noMultiFactor,
  );
}
