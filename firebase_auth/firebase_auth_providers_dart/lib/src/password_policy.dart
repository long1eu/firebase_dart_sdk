import 'firebase_user_auth.dart';

/// The password policy of the project or of a tenant (`PasswordPolicy` of FlutterFire and of the JS SDK), as
/// `v2/passwordPolicy` of the Identity Toolkit API returns it. [FirebaseUserAuth.validatePassword] checks a password
/// against it.
class PasswordPolicy {
  /// Creates the policy. [PasswordPolicy.fromResponse] creates them; you need this only for tests.
  const PasswordPolicy({
    this.minPasswordLength = defaultMinPasswordLength,
    this.maxPasswordLength,
    this.containsLowercaseCharacter,
    this.containsUppercaseCharacter,
    this.containsNumericCharacter,
    this.containsNonAlphanumericCharacter,
    this.allowedNonAlphanumericCharacters = const <String>[],
    this.enforcementState = 'OFF',
    this.forceUpgradeOnSignin = false,
    this.schemaVersion = supportedSchemaVersion,
  });

  /// Reads the answer of `v2/passwordPolicy`, like the JS SDK's `PasswordPolicyImpl`: the minimum length defaults
  /// to [defaultMinPasswordLength], and the enforcement state `ENFORCEMENT_STATE_UNSPECIFIED` is `OFF`.
  factory PasswordPolicy.fromResponse(Map<String, Object?> response) {
    final Object? options = response['customStrengthOptions'];
    final Map<String, Object?> strength = options is Map<String, Object?>
        ? options
        : const <String, Object?>{};
    int? number(Object? value) => value is num ? value.toInt() : null;
    bool? flag(Object? value) => value is bool ? value : null;
    final Object? allowed = response['allowedNonAlphanumericCharacters'];
    final Object? enforcement = response['enforcementState'];
    final int? maxLength = number(strength['maxPasswordLength']);
    return PasswordPolicy(
      minPasswordLength:
          number(strength['minPasswordLength']) ?? defaultMinPasswordLength,
      // The JS SDK ignores a maximum of 0.
      maxPasswordLength: maxLength == null || maxLength == 0 ? null : maxLength,
      containsLowercaseCharacter: flag(strength['containsLowercaseCharacter']),
      containsUppercaseCharacter: flag(strength['containsUppercaseCharacter']),
      containsNumericCharacter: flag(strength['containsNumericCharacter']),
      containsNonAlphanumericCharacter: flag(
        strength['containsNonAlphanumericCharacter'],
      ),
      allowedNonAlphanumericCharacters: List<String>.unmodifiable(<String>[
        if (allowed is List)
          for (final Object? c in allowed)
            if (c is String) c,
      ]),
      enforcementState:
          enforcement is! String ||
              enforcement == 'ENFORCEMENT_STATE_UNSPECIFIED'
          ? 'OFF'
          : enforcement,
      forceUpgradeOnSignin: response['forceUpgradeOnSignin'] == true,
      schemaVersion: number(response['schemaVersion']) ?? 0,
    );
  }

  /// The minimum length when the policy names none (`MINIMUM_MIN_PASSWORD_LENGTH` of the JS SDK).
  static const int defaultMinPasswordLength = 6;

  /// The schema version this package understands (`EXPECTED_PASSWORD_POLICY_SCHEMA_VERSION` of the JS SDK).
  static const int supportedSchemaVersion = 1;

  /// The minimum length of a password.
  final int minPasswordLength;

  /// The maximum length of a password, or null for none.
  final int? maxPasswordLength;

  /// Whether a password needs a lower case letter (`a` to `z`); null when the policy does not say.
  final bool? containsLowercaseCharacter;

  /// Whether a password needs an upper case letter (`A` to `Z`).
  final bool? containsUppercaseCharacter;

  /// Whether a password needs a digit (`0` to `9`).
  final bool? containsNumericCharacter;

  /// Whether a password needs one of [allowedNonAlphanumericCharacters].
  final bool? containsNonAlphanumericCharacter;

  /// The characters that count as symbols.
  final List<String> allowedNonAlphanumericCharacters;

  /// `ENFORCE` (a sign-up or a password change with a password that fails the policy is refused with
  /// `password-does-not-meet-requirements`), `AUDIT`, or `OFF`.
  final String enforcementState;

  /// Whether users whose password fails the policy must change it when they sign in.
  final bool forceUpgradeOnSignin;

  /// The schema version of the policy.
  final int schemaVersion;

  /// Checks [password] against the policy, like `PasswordPolicyImpl.validatePassword` of the JS SDK.
  PasswordValidationStatus validate(String password) {
    bool contains(bool Function(String c) test) {
      for (int i = 0; i < password.length; i++) {
        if (test(password[i])) {
          return true;
        }
      }
      return false;
    }

    final String symbols = allowedNonAlphanumericCharacters.join();
    final bool meetsMin = password.length >= minPasswordLength;
    final int? max = maxPasswordLength;
    final bool meetsMax = max == null || password.length <= max;
    final bool lower =
        containsLowercaseCharacter != true ||
        contains((String c) => c.compareTo('a') >= 0 && c.compareTo('z') <= 0);
    final bool upper =
        containsUppercaseCharacter != true ||
        contains((String c) => c.compareTo('A') >= 0 && c.compareTo('Z') <= 0);
    final bool digits =
        containsNumericCharacter != true ||
        contains((String c) => c.compareTo('0') >= 0 && c.compareTo('9') <= 0);
    final bool symbol =
        containsNonAlphanumericCharacter != true ||
        contains((String c) => symbols.contains(c));
    return PasswordValidationStatus(
      isValid: meetsMin && meetsMax && lower && upper && digits && symbol,
      passwordPolicy: this,
      meetsMinPasswordLength: meetsMin,
      meetsMaxPasswordLength: meetsMax,
      meetsLowercaseRequirement: lower,
      meetsUppercaseRequirement: upper,
      meetsDigitsRequirement: digits,
      meetsSymbolsRequirement: symbol,
    );
  }

  @override
  String toString() =>
      'PasswordPolicy(minPasswordLength: $minPasswordLength, enforcementState: $enforcementState)';
}

/// The result of [FirebaseUserAuth.validatePassword] (`PasswordValidationStatus` of FlutterFire and of the JS SDK).
/// A requirement the policy does not have counts as met.
class PasswordValidationStatus {
  /// Creates the status. [PasswordPolicy.validate] creates them; you need this only for tests.
  const PasswordValidationStatus({
    required this.isValid,
    required this.passwordPolicy,
    this.meetsMinPasswordLength = true,
    this.meetsMaxPasswordLength = true,
    this.meetsLowercaseRequirement = true,
    this.meetsUppercaseRequirement = true,
    this.meetsDigitsRequirement = true,
    this.meetsSymbolsRequirement = true,
  });

  /// Whether the password meets every requirement.
  final bool isValid;

  /// The policy the password was checked against.
  final PasswordPolicy passwordPolicy;

  /// Whether the password is long enough.
  final bool meetsMinPasswordLength;

  /// Whether the password is short enough.
  final bool meetsMaxPasswordLength;

  /// Whether the password has a lower case letter, if the policy needs one (the JS SDK's
  /// `containsLowercaseLetter`).
  final bool meetsLowercaseRequirement;

  /// Whether the password has an upper case letter, if the policy needs one.
  final bool meetsUppercaseRequirement;

  /// Whether the password has a digit, if the policy needs one.
  final bool meetsDigitsRequirement;

  /// Whether the password has a symbol, if the policy needs one.
  final bool meetsSymbolsRequirement;

  @override
  String toString() => 'PasswordValidationStatus(isValid: $isValid)';
}
