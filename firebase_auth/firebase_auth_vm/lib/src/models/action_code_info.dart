// File created by
// Lung Razvan <long1eu>
// on 11/12/2019

part of firebase_auth_vm;

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
    return (ToStringHelper(ActionCodeInfo)..add('operation', operation)..add('email', email)..add('forEmail', forEmail))
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

  /// The action code type value for verifying and changing email in the check action code response.
  static const ActionCodeOperation verifyAndChangeEmail = ActionCodeOperation._(4, 'VERIFY_AND_CHANGE_EMAIL');

  /// The action code type value for reverting second factor addition in the check action code response.
  static const ActionCodeOperation revertSecondFactorAddition =
      ActionCodeOperation._(5, 'REVERT_SECOND_FACTOR_ADDITION');

  static const List<ActionCodeOperation> values = <ActionCodeOperation>[
    passwordReset,
    verifyEmail,
    recoverEmail,
    emailSignIn,
    verifyAndChangeEmail,
    revertSecondFactorAddition,
  ];

  static const List<String> _names = <String>[
    'passwordReset',
    'verifyEmail',
    'recoverEmail',
    'emailSignIn',
    'verifyAndChangeEmail',
    'revertSecondFactorAddition',
  ];

  @override
  String toString() => 'ActionCodeOperation.${_names[_i]}';
}
