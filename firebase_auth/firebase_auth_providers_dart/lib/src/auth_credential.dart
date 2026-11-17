// The provider ids and sign-in method names are FlutterFire's (and the JS SDK's) constants, in their upper case.
// ignore_for_file: constant_identifier_names

import 'action_code.dart';
import 'firebase_user_auth.dart';

/// Proof of an identity that [FirebaseUserAuth.signInWithCredential], [FirebaseUserAuth.linkWithCredential] and
/// [FirebaseUserAuth.reauthenticateWithCredential] take (`AuthCredential` of FlutterFire and of the JS SDK). Make one
/// with a provider: [EmailAuthProvider].
///
/// A credential holds a secret (a password, an email link, a token): [toString] shows only the provider and the
/// sign-in method.
abstract class AuthCredential {
  /// Constructor for subclasses. Only the credentials of this package can be used to sign in.
  const AuthCredential({required this.providerId, required this.signInMethod});

  /// The provider: `password`, `google.com`, `oidc.<name>`, ...
  final String providerId;

  /// How the credential signs in: `password`, `emailLink`, or the provider id for the federated providers.
  final String signInMethod;

  @override
  String toString() =>
      '$runtimeType(providerId: $providerId, signInMethod: $signInMethod)';
}

/// A credential of the email and password provider: an email address with a password, or with an email link
/// (FlutterFire's `EmailAuthCredential`). Make it with [EmailAuthProvider.credential] or
/// [EmailAuthProvider.credentialWithLink].
class EmailAuthCredential extends AuthCredential {
  const EmailAuthCredential._(
    String signInMethod, {
    required this.email,
    this.password,
    this.emailLink,
  }) : super(
         providerId: EmailAuthProvider.PROVIDER_ID,
         signInMethod: signInMethod,
       );

  /// The email address.
  final String email;

  /// The password, for [EmailAuthProvider.EMAIL_PASSWORD_SIGN_IN_METHOD]. Not part of [toString].
  final String? password;

  /// The sign-in link of the email, for [EmailAuthProvider.EMAIL_LINK_SIGN_IN_METHOD]. Not part of [toString].
  final String? emailLink;
}

/// The email and password provider (`EmailAuthProvider` of FlutterFire and of the JS SDK): makes the credentials of
/// an email address with a password or with an email link.
///
/// ```dart
/// final AuthCredential credential = EmailAuthProvider.credential(
///   email: 'ada@example.com',
///   password: 'correct horse',
/// );
/// await auth.reauthenticateWithCredential(credential);
/// ```
abstract final class EmailAuthProvider {
  /// The provider id: `password`.
  static const String PROVIDER_ID = 'password';

  /// The sign-in method of an email address with a password: `password`.
  static const String EMAIL_PASSWORD_SIGN_IN_METHOD = 'password';

  /// The sign-in method of an email link: `emailLink`.
  static const String EMAIL_LINK_SIGN_IN_METHOD = 'emailLink';

  /// The credential of [email] and [password].
  static EmailAuthCredential credential({
    required String email,
    required String password,
  }) => EmailAuthCredential._(
    EMAIL_PASSWORD_SIGN_IN_METHOD,
    email: email,
    password: password,
  );

  /// The credential of [email] and the sign-in link of the email [FirebaseUserAuth.sendSignInLinkToEmail] sent
  /// to it ([emailLink], the whole link, as the app received it).
  ///
  /// The link is checked when the credential is used: one that is not a sign-in link
  /// ([ActionCodeURL.parseLink]) fails with `argument-error`.
  static EmailAuthCredential credentialWithLink({
    required String email,
    required String emailLink,
  }) => EmailAuthCredential._(
    EMAIL_LINK_SIGN_IN_METHOD,
    email: email,
    emailLink: emailLink,
  );
}
