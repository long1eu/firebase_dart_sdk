/// How a project (or a tenant) protects a sign-in provider with reCAPTCHA Enterprise
/// (`EnforcementState` of the JS SDK).
enum RecaptchaEnforcementState {
  /// Requests without a valid token are refused: `ENFORCE`.
  enforce('ENFORCE'),

  /// Tokens are checked and logged, requests without one still pass: `AUDIT`.
  audit('AUDIT'),

  /// No protection: `OFF`.
  off('OFF'),

  /// `ENFORCEMENT_STATE_UNSPECIFIED`, and any value this package does not know.
  unspecified('ENFORCEMENT_STATE_UNSPECIFIED');

  const RecaptchaEnforcementState(this.value);

  /// The value on the wire.
  final String value;

  /// The state of [value], [unspecified] for one this package does not know (like
  /// `_parseEnforcementState` of the JS SDK).
  static RecaptchaEnforcementState parse(Object? value) {
    for (final RecaptchaEnforcementState state in values) {
      if (state.value == value) {
        return state;
      }
    }
    return unspecified;
  }
}

/// A sign-in provider that reCAPTCHA Enterprise can protect (`RecaptchaAuthProvider` of the JS
/// SDK).
enum RecaptchaProvider {
  /// Email and password: sign-in, sign-up and the emails of a password reset or an email link
  /// sign-in. `EMAIL_PASSWORD_PROVIDER`.
  emailPassword('EMAIL_PASSWORD_PROVIDER'),

  /// Phone numbers: the SMS of a phone sign-in and of an SMS second factor. `PHONE_PROVIDER`.
  phone('PHONE_PROVIDER');

  const RecaptchaProvider(this.value);

  /// The value on the wire.
  final String value;
}

/// The reCAPTCHA Enterprise configuration of a project or a tenant, as `v2/recaptchaConfig`
/// returns it (`RecaptchaConfig` of the JS SDK): the Enterprise site key and how each provider is
/// protected.
///
/// The answer also carries SMS toll fraud settings; the JS SDK reads none of them, and neither
/// does this class.
final class RecaptchaConfig {
  /// A configuration with [siteKey] and [enforcementStates].
  const RecaptchaConfig({
    required this.siteKey,
    this.enforcementStates =
        const <RecaptchaProvider, RecaptchaEnforcementState>{},
  });

  /// The configuration in [response], the answer of `v2/recaptchaConfig`:
  ///
  /// * the site key is the last part of `recaptchaKey` (`projects/<project>/keys/<site key>`);
  /// * each entry of `recaptchaEnforcementState` with a known `provider` gives its
  ///   `enforcementState` ([RecaptchaEnforcementState.parse]); the first entry of a provider wins,
  ///   as in the JS SDK.
  ///
  /// An answer without a `recaptchaKey` (a project that has never turned reCAPTCHA Enterprise on)
  /// gives a configuration without a site key. The JS SDK throws `recaptchaKey undefined` there,
  /// and its phone flow treats that as "not enabled"; here [siteKey] is null and the providers
  /// are as the answer says (usually none).
  factory RecaptchaConfig.fromResponse(Map<String, Object?> response) {
    final Map<RecaptchaProvider, RecaptchaEnforcementState> states =
        <RecaptchaProvider, RecaptchaEnforcementState>{};
    final Object? entries = response['recaptchaEnforcementState'];
    if (entries is List) {
      for (final Object? entry in entries) {
        if (entry is! Map) {
          continue;
        }
        for (final RecaptchaProvider provider in RecaptchaProvider.values) {
          if (entry['provider'] == provider.value) {
            states.putIfAbsent(
              provider,
              () => RecaptchaEnforcementState.parse(entry['enforcementState']),
            );
          }
        }
      }
    }
    return RecaptchaConfig(
      siteKey: _siteKeyOf(response['recaptchaKey']),
      enforcementStates:
          Map<RecaptchaProvider, RecaptchaEnforcementState>.unmodifiable(
            states,
          ),
    );
  }

  static final RegExp _keyName = RegExp(r'^projects/[^/]+/keys/([^/]+)$');

  static String? _siteKeyOf(Object? name) {
    if (name is! String) {
      return null;
    }
    return _keyName.firstMatch(name)?.group(1);
  }

  /// The reCAPTCHA Enterprise site key the tokens are made with, or null when the answer named
  /// none.
  final String? siteKey;

  /// The state of each provider the answer named.
  final Map<RecaptchaProvider, RecaptchaEnforcementState> enforcementStates;

  /// The state of [provider], or null when the answer did not name it
  /// (`getProviderEnforcementState`).
  RecaptchaEnforcementState? enforcementState(RecaptchaProvider provider) =>
      enforcementStates[provider];

  /// Whether [provider] is protected: [RecaptchaEnforcementState.enforce] or
  /// [RecaptchaEnforcementState.audit] (`isProviderEnabled`).
  bool isProviderEnabled(RecaptchaProvider provider) =>
      switch (enforcementState(provider)) {
        RecaptchaEnforcementState.enforce ||
        RecaptchaEnforcementState.audit => true,
        _ => false,
      };

  /// Whether any provider is protected (`isAnyProviderEnabled`).
  bool get isAnyProviderEnabled =>
      RecaptchaProvider.values.any(isProviderEnabled);

  /// Leaves out the site key.
  @override
  String toString() =>
      'RecaptchaConfig(${enforcementStates.entries.map(_describe).join(', ')})';

  static String _describe(
    MapEntry<RecaptchaProvider, RecaptchaEnforcementState> entry,
  ) => '${entry.key.name}: ${entry.value.name}';
}
