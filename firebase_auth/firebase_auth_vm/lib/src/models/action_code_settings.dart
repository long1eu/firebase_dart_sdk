// File created by
// Lung Razvan <long1eu>
// on 06/12/2019

part of firebase_auth_vm;

class ActionCodeSettings {
  /// Settings related to handling action codes.
  ///
  /// If [handleCodeInApp] is true you must specify the [iOSBundleId].
  /// If [androidInstallIfNotAvailable] is true you must specify the [androidPackageName].
  ActionCodeSettings({
    this.continueUrl,
    this.iOSBundleId,
    this.androidPackageName,
    this.androidInstallIfNotAvailable,
    this.androidMinimumVersion,
    this.handleCodeInApp = false,
    this.dynamicLinkDomain,
  });

  /// This URL represents the state/Continue URL in the form of a universal link.
  /*@nullable*/
  final String continueUrl;

  /// The iOS bundle Identifier, if available.
  /*@nullable*/
  final String iOSBundleId;

  /// The Android package name, if available.
  /*@nullable*/
  final String androidPackageName;

  /// Indicates whether or not the Android app should be installed if not already available.
  /*@nullable*/
  final bool androidInstallIfNotAvailable;

  /// The minimum Android version supported, if available.
  /*@nullable*/
  final String androidMinimumVersion;

  /// Indicates whether the action code link will open the app directly after being redirected from a Firebase owned web
  /// widget.
  ///
  /// When set to true, the action code link will be sent as a universal link and will be open by the app if installed.
  /// In the false case, the code will be sent to the web widget first and then on continue will redirect to the app if
  /// installed.
  final bool handleCodeInApp;

  /// The Firebase Dynamic Link domain used for out of band code flow.
  ///
  /// Must be one of the 5 domains configured in the Firebase console.
  /*@nullable*/
  final String dynamicLinkDomain;

  @override
  String toString() {
    return (ToStringHelper(ActionCodeInfo)
          ..add('continueUrl', continueUrl)
          ..add('iOSBundleId', iOSBundleId)
          ..add('androidPackageName', androidPackageName)
          ..add('androidInstallIfNotAvailable', androidInstallIfNotAvailable)
          ..add('androidMinimumVersion', androidMinimumVersion)
          ..add('handleCodeInApp', handleCodeInApp)
          ..add('dynamicLinkDomain', dynamicLinkDomain))
        .toString();
  }
}
