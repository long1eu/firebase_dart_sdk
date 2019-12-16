// File created by
// Lung Razvan <long1eu>
// on 07/12/2019

part of firebase_auth;

/// Types of OOB Confirmation Code requests.
class OobCodeType {
  const OobCodeType._(this._i, this.value);

  final String value;
  final int _i;

  /// Requests a password reset code.
  static const OobCodeType passwordReset = OobCodeType._(0, 'PASSWORD_RESET');

  /// Requests an email verification code.
  static const OobCodeType verifyEmail = OobCodeType._(1, 'VERIFY_EMAIL');

  /// Requests an email sign-in link.
  static const OobCodeType emailLinkSignIn = OobCodeType._(2, 'EMAIL_SIGNIN');

  /// Requests an verify before update email.
  static const OobCodeType verifyBeforeUpdateEmail = OobCodeType._(3, 'VERIFY_AND_CHANGE_EMAIL');

  static const List<OobCodeType> values = <OobCodeType>[
    passwordReset,
    verifyEmail,
    emailLinkSignIn,
    verifyBeforeUpdateEmail,
  ];

  static const List<String> _names = <String>[
    'passwordReset',
    'verifyEmail',
    'emailLinkSignIn',
    'verifyBeforeUpdateEmail',
  ];

  @override
  String toString() => 'OobCodeType.${_names[_i]}';
}
