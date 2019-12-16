// File created by
// Lung Razvan <long1eu>
// on 11/12/2019

part of firebase_auth;

class ActionCodeInfo {
  const ActionCodeInfo._(this.operation, String email, String newEmail)
      : email = newEmail ?? email,
        forEmail = newEmail != null ? email : null;

  final ActionCodeOperation operation;

  /// The email address to which the code was sent. The new email address in the case of
  /// [ActionCodeOperation.recoverEmail].
  final String email;

  /// The current email address in the case of [ActionCodeOperation.recoverEmail].
  final String forEmail;

  @override
  String toString() {
    return (IndentingBuiltValueToStringHelper('ActionCodeInfo')
          ..add('operation', operation)
          ..add('email', email)
          ..add('forEmail', forEmail))
        .toString();
  }
}

/// Types of OOB Confirmation Code requests.
class ActionCodeOperation {
  const ActionCodeOperation._(this._i, this.value);

  final String value;
  final int _i;

  /// The action code type value for resetting password in the check action code response.
  static const ActionCodeOperation passwordReset = ActionCodeOperation._(0, 'PASSWORD_RESET');

  /// The action code type value for verifying email in the check action code response.
  static const ActionCodeOperation verifyEmail = ActionCodeOperation._(1, 'VERIFY_EMAIL');

  /// The action code type value for recovering email in the check action code response.
  static const ActionCodeOperation recoverEmail = ActionCodeOperation._(2, 'RECOVER_EMAIL');

  /// The action code type value for an email sign-in link in the check action code response.
  static const ActionCodeOperation emailSignIn = ActionCodeOperation._(3, 'EMAIL_SIGNIN');

  static const List<ActionCodeOperation> values = <ActionCodeOperation>[
    passwordReset,
    verifyEmail,
    recoverEmail,
    emailSignIn,
  ];

  static const List<String> _names = <String>[
    'passwordReset',
    'verifyEmail',
    'recoverEmail',
    'emailSignIn',
  ];

  @override
  String toString() => 'ActionCodeOperation.${_names[_i]}';
}
