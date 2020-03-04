// File created by
// Lung Razvan <long1eu>
// on 09/12/2019

part of firebase_auth_vm;

/// Indicates the type of operation performed for RPCs that support the operation parameter.
class AuthOperationType {
  const AuthOperationType._(this._i, this.value);

  final String value;
  final int _i;

  /// Indicates that the operation type is unspecified.
  static const AuthOperationType unspecified = AuthOperationType._(0, 'VERIFY_OP_UNSPECIFIED');

  /// Indicates that the operation type is sign in or sign up.
  static const AuthOperationType signUpOrSignIn = AuthOperationType._(1, 'SIGN_UP_OR_IN');

  /// Indicates that the operation type is reauthentication.
  static const AuthOperationType reauthenticate = AuthOperationType._(2, 'REAUTH');

  /// Indicates that the operation type is update.
  static const AuthOperationType update = AuthOperationType._(3, 'UPDATE');

  /// Indicates that the operation type is link.
  static const AuthOperationType link = AuthOperationType._(4, 'LINK');

  static const List<AuthOperationType> values = <AuthOperationType>[
    unspecified,
    signUpOrSignIn,
    reauthenticate,
    update,
    link,
  ];

  static const List<String> _names = <String>[
    'unspecified',
    'signUpOrSignIn',
    'reauthenticate',
    'update',
    'link',
  ];

  @override
  String toString() => 'AuthOperationType.${_names[_i]}';
}
