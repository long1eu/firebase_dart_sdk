// File created by
// Lung Razvan <long1eu>
// on 04/12/2019

part of models;

abstract class ActionCodeSettings implements Built<ActionCodeSettings, ActionCodeSettingsBuilder> {
  /// Settings related to handling action codes.
  ///
  /// If [canHandleCodeInApp] is true you must specify the [iOSBundleId].
  /// If [androidInstallApp] is true you must specify the [androidPackageName].
  factory ActionCodeSettings({
    String continueUrl,
    String iOSBundleId,
    String androidPackageName,
    bool androidInstallApp,
    String androidMinimumVersion,
    bool canHandleCodeInApp = false,
    String dynamicLinkDomain,
  }) {
    return _$ActionCodeSettings((ActionCodeSettingsBuilder b) {
      b
        ..continueUrl = continueUrl
        ..iOSBundleId = iOSBundleId
        ..androidPackageName = androidPackageName
        ..androidInstallApp = androidInstallApp
        ..androidMinimumVersion = androidMinimumVersion
        ..canHandleCodeInApp = canHandleCodeInApp ?? false
        ..dynamicLinkDomain = dynamicLinkDomain;
    });
  }

  ActionCodeSettings._();

  /// This URL represents the state/Continue URL in the form of a universal link.
  @nullable
  String get continueUrl;

  /// The iOS bundle Identifier, if available.
  @nullable
  String get iOSBundleId;

  /// The Android package name, if available.
  @nullable
  String get androidPackageName;

  /// Indicates whether or not the Android app should be installed if not already available.
  @nullable
  bool get androidInstallApp;

  /// The minimum Android version supported, if available.
  @nullable
  String get androidMinimumVersion;

  /// Indicates whether the action code link will open the app directly after being redirected from a Firebase owned web
  /// widget.
  ///
  /// When set to true, the action code link will be sent as a universal link and will be open by the app if installed.
  /// In the false case, the code will be sent to the web widget first and then on continue will redirect to the app if
  /// installed.
  bool get canHandleCodeInApp;

  /// The Firebase Dynamic Link domain used for out of band code flow.
  ///
  /// Must be one of the 5 domains configured in the Firebase console.
  @nullable
  String get dynamicLinkDomain;
}
