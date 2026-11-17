import 'auth_exception.dart';

/// Where the link of an action email (password reset, email verification, ...) leads, like `ActionCodeSettings`
/// of the JS SDK.
///
/// Pass it to `FirebaseUserAuth.sendPasswordResetEmail`, `FirebaseUserAuth.sendEmailVerification` or
/// `FirebaseUserAuth.verifyBeforeUpdateEmail`. Without it the link opens the action page of the project. The
/// iOS and Android fields of the JS SDK are flattened; `dynamicLinkDomain` is not supported. The values are checked
/// when the email is requested ([toRequest]); the URL and the domains must also be authorized for the project.
///
/// ```dart
/// await auth.sendPasswordResetEmail(
///   'ada@example.com',
///   actionCodeSettings: const ActionCodeSettings(
///     url: 'https://my-project.web.app/signed-in',
///     handleCodeInApp: true,
///     androidPackageName: 'com.example.app',
///     androidInstallApp: true,
///   ),
/// );
/// ```
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

  /// The fields of the request, checked like the JS SDK (`_setActionCodeSettingsOnRequest`). Called by
  /// `FirebaseUserAuth`; you do not need it.
  ///
  /// Throws a [FirebaseAuthException] with the code `invalid-continue-uri` (empty [url]),
  /// `invalid-hosting-link-domain` (empty [linkDomain]), `missing-ios-bundle-id` (empty [iOSBundleId]) or
  /// `missing-android-pkg-name` (empty [androidPackageName]). [androidInstallApp] and [androidMinimumVersion] are
  /// sent only with an [androidPackageName].
  Map<String, Object?> toRequest() {
    if (url.isEmpty) {
      throw const FirebaseAuthException(
        code: 'invalid-continue-uri',
        message: 'The continue URL provided in the request is invalid.',
      );
    }
    if (linkDomain != null && linkDomain!.isEmpty) {
      throw const FirebaseAuthException(
        code: 'invalid-hosting-link-domain',
        message:
            'The provided Hosting link domain is not configured for the project.',
      );
    }
    if (iOSBundleId != null && iOSBundleId!.isEmpty) {
      throw const FirebaseAuthException(
        code: 'missing-ios-bundle-id',
        message: 'An iOS bundle id must be provided.',
      );
    }
    if (androidPackageName != null && androidPackageName!.isEmpty) {
      throw const FirebaseAuthException(
        code: 'missing-android-pkg-name',
        message: 'An Android package name must be provided.',
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

/// What an action code is for (`ActionCodeOperation` of the JS SDK): [ActionCodeInfo.operation].
///
/// ```dart
/// final ActionCodeInfo info = await auth.checkActionCode(code);
/// if (info.operation == ActionCodeOperation.passwordReset) {
///   await auth.confirmPasswordReset(code: code, newPassword: newPassword);
/// } else {
///   await auth.applyActionCode(code);
/// }
/// ```
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
  revertSecondFactorAddition('REVERT_SECOND_FACTOR_ADDITION'),

  /// An operation this package does not know (FlutterFire's `ActionCodeInfoOperation.unknown`): the backend's
  /// name is in [ActionCodeInfo.requestType]. Its [serverName] is empty.
  unknown('');

  const ActionCodeOperation(this.serverName);

  /// The name the backend uses.
  final String serverName;
}

/// What an action code does, from `FirebaseUserAuth.checkActionCode` (`ActionCodeInfo` of the JS SDK).
///
/// ```dart
/// final ActionCodeInfo info = await auth.checkActionCode(code);
/// print('${info.operation.name} for ${info.email}');
/// ```
class ActionCodeInfo {
  /// Creates the information. `FirebaseUserAuth.checkActionCode` creates them; you need this only for tests.
  ///
  /// [requestType] defaults to the [ActionCodeOperation.serverName] of [operation].
  const ActionCodeInfo(
    this.operation, {
    this.email,
    this.previousEmail,
    this.multiFactorInfo,
    String? requestType,
  }) : _requestType = requestType;

  /// Reads the answer of `accounts:resetPassword` with only an `oobCode`, checked like `checkActionCode` of the JS
  /// SDK: an operation the package does not know is [ActionCodeOperation.unknown], with the backend's name in
  /// [requestType].
  ///
  /// Throws a [FirebaseAuthException] with the code `internal-error` when the answer has no operation or lacks the
  /// email address (or the multi-factor information) the operation needs.
  factory ActionCodeInfo.fromResponse(Map<String, Object?> response) {
    const FirebaseAuthException malformed = FirebaseAuthException(
      code: 'internal-error',
      message: 'The authentication service returned an incomplete action code.',
    );
    final Object? requestType = response['requestType'];
    if (requestType is! String || requestType.isEmpty) {
      throw malformed;
    }
    ActionCodeOperation operation = ActionCodeOperation.unknown;
    for (final ActionCodeOperation value in ActionCodeOperation.values) {
      if (value.serverName == requestType) {
        operation = value;
      }
    }
    String? nonEmpty(Object? value) =>
        value is String && value.isNotEmpty ? value : null;
    final String? email = nonEmpty(response['email']);
    final String? newEmail = nonEmpty(response['newEmail']);
    final MultiFactorInfo? multiFactorInfo = MultiFactorInfo.fromResponse(
      response['mfaInfo'],
    );
    switch (operation) {
      case ActionCodeOperation.emailSignIn:
        break;
      case ActionCodeOperation.verifyAndChangeEmail:
        if (newEmail == null) {
          throw malformed;
        }
      case ActionCodeOperation.revertSecondFactorAddition:
        if (response['mfaInfo'] == null || email == null) {
          throw malformed;
        }
      default:
        // Also an operation this package does not know, like the JS SDK.
        if (email == null) {
          throw malformed;
        }
    }
    final bool changesEmail =
        operation == ActionCodeOperation.verifyAndChangeEmail;
    return ActionCodeInfo(
      operation,
      email: changesEmail ? newEmail : email,
      previousEmail: changesEmail ? email : newEmail,
      multiFactorInfo: multiFactorInfo,
      requestType: requestType,
    );
  }

  /// What the code is for; [ActionCodeOperation.unknown] for an operation this package does not know.
  final ActionCodeOperation operation;

  final String? _requestType;

  /// The name of the operation as the backend gave it, for example `PASSWORD_RESET`; also for an
  /// [ActionCodeOperation.unknown] operation (the JS SDK returns this string as the operation).
  String get requestType => _requestType ?? operation.serverName;

  /// The email address the code is about: for [ActionCodeOperation.verifyAndChangeEmail] the new address.
  final String? email;

  /// The address before the change, for [ActionCodeOperation.verifyAndChangeEmail] and
  /// [ActionCodeOperation.recoverEmail].
  final String? previousEmail;

  /// The second factor that [ActionCodeOperation.revertSecondFactorAddition] removes, when the backend sent it.
  final MultiFactorInfo? multiFactorInfo;

  @override
  String toString() =>
      'ActionCodeInfo(${operation == ActionCodeOperation.unknown ? requestType : operation.name})';
}
