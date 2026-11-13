import 'auth_exception.dart';

/// Where the link of an action email (password reset, email verification, ...) leads, like `ActionCodeSettings`
/// of the JS SDK.
class ActionCodeSettings {
  /// Creates the settings. [url] is the continue URL, passed to the action page (or the app) after the action.
  const ActionCodeSettings({
    required this.url,
    this.handleCodeInApp,
    this.iOSBundleId,
    this.androidPackageName,
    this.androidInstallApp,
    this.androidMinimumVersion,
    this.linkDomain,
  });

  /// The continue URL. Must not be empty (`invalid-continue-uri`).
  final String url;

  /// Whether the link is opened in the app (a mobile app or a web page that handles the code) rather than on the
  /// action page of Firebase Hosting.
  final bool? handleCodeInApp;

  /// The bundle id of the iOS app that opens the link. Must not be empty when set (`missing-ios-bundle-id`).
  final String? iOSBundleId;

  /// The package name of the Android app that opens the link. Must not be empty when set
  /// (`missing-android-pkg-name`).
  final String? androidPackageName;

  /// Whether the Android app is installed when it is missing.
  final bool? androidInstallApp;

  /// The minimum version of the Android app.
  final String? androidMinimumVersion;

  /// The Firebase Hosting domain of the link. Must not be empty when set (`invalid-hosting-link-domain`).
  final String? linkDomain;

  /// The fields of the request, checked like the JS SDK (`_setActionCodeSettingsOnRequest`).
  Map<String, Object?> toRequest() {
    if (url.isEmpty) {
      throw const FirebaseAuthProviderException(
        'invalid-continue-uri',
        'The continue URL provided in the request is invalid.',
      );
    }
    if (linkDomain != null && linkDomain!.isEmpty) {
      throw const FirebaseAuthProviderException(
        'invalid-hosting-link-domain',
        'The provided Hosting link domain is not configured for the project.',
      );
    }
    if (iOSBundleId != null && iOSBundleId!.isEmpty) {
      throw const FirebaseAuthProviderException(
        'missing-ios-bundle-id',
        'An iOS bundle id must be provided.',
      );
    }
    if (androidPackageName != null && androidPackageName!.isEmpty) {
      throw const FirebaseAuthProviderException(
        'missing-android-pkg-name',
        'An Android package name must be provided.',
      );
    }
    return <String, Object?>{
      'continueUrl': url,
      if (linkDomain != null) 'linkDomain': linkDomain,
      if (handleCodeInApp != null) 'canHandleCodeInApp': handleCodeInApp,
      if (iOSBundleId != null) 'iOSBundleId': iOSBundleId,
      if (androidPackageName != null) ...<String, Object?>{
        'androidPackageName': androidPackageName,
        if (androidInstallApp != null) 'androidInstallApp': androidInstallApp,
        if (androidMinimumVersion != null)
          'androidMinimumVersionCode': androidMinimumVersion,
      },
    };
  }
}

/// What an action code is for (`ActionCodeOperation` of the JS SDK).
enum ActionCodeOperation {
  /// A password reset.
  passwordReset('PASSWORD_RESET'),

  /// The verification of the email address.
  verifyEmail('VERIFY_EMAIL'),

  /// The verification of a new email address, which becomes the address of the account (`verifyBeforeUpdateEmail`).
  verifyAndChangeEmail('VERIFY_AND_CHANGE_EMAIL'),

  /// The undoing of a change of the email address.
  recoverEmail('RECOVER_EMAIL'),

  /// An email link sign-in.
  emailSignIn('EMAIL_SIGNIN'),

  /// The undoing of the enrolment of a second factor.
  revertSecondFactorAddition('REVERT_SECOND_FACTOR_ADDITION');

  const ActionCodeOperation(this.serverName);

  /// The name the backend uses.
  final String serverName;
}

/// What an action code does, from `checkActionCode` (`ActionCodeInfo` of the JS SDK, without the multi-factor
/// information).
class ActionCodeInfo {
  /// Creates the information.
  const ActionCodeInfo(this.operation, {this.email, this.previousEmail});

  /// Reads the answer of `accounts:resetPassword` with only an `oobCode`, checked like the JS SDK.
  factory ActionCodeInfo.fromResponse(Map<String, Object?> response) {
    const FirebaseAuthProviderException malformed =
        FirebaseAuthProviderException(
          'internal-error',
          'The authentication service returned an incomplete action code.',
        );
    final Object? requestType = response['requestType'];
    ActionCodeOperation? operation;
    for (final ActionCodeOperation value in ActionCodeOperation.values) {
      if (value.serverName == requestType) {
        operation = value;
      }
    }
    if (operation == null) {
      throw malformed;
    }
    final Object? email = response['email'];
    final Object? newEmail = response['newEmail'];
    switch (operation) {
      case ActionCodeOperation.emailSignIn:
        break;
      case ActionCodeOperation.verifyAndChangeEmail:
        if (newEmail is! String) {
          throw malformed;
        }
      default:
        if (email is! String) {
          throw malformed;
        }
    }
    final bool changesEmail =
        operation == ActionCodeOperation.verifyAndChangeEmail;
    String? nonEmpty(Object? value) =>
        value is String && value.isNotEmpty ? value : null;
    return ActionCodeInfo(
      operation,
      email: nonEmpty(changesEmail ? newEmail : email),
      previousEmail: nonEmpty(changesEmail ? email : newEmail),
    );
  }

  /// What the code is for.
  final ActionCodeOperation operation;

  /// The email address the code is about: for [ActionCodeOperation.verifyAndChangeEmail] the new address.
  final String? email;

  /// The address before the change, for [ActionCodeOperation.verifyAndChangeEmail] and
  /// [ActionCodeOperation.recoverEmail].
  final String? previousEmail;

  @override
  String toString() => 'ActionCodeInfo(${operation.name})';
}
