// File created by
// Lung Razvan <long1eu>
// on 06/03/2020

part of 'firebase.dart';

ProjectsIosAppsResourceApi get iosApps => _firebaseApi.projects.iosApps;

Future<IosAppConfig> createIosApp({
  @required String name,
  @required String bundleId,
}) async {
  assert(name != null && name.isNotEmpty);
  assert(bundleId != null && bundleId.isNotEmpty);

  final IosAppConfig config = await _addIosAppToFirebase(name, bundleId);


}

Future<IosAppConfig> _addIosAppToFirebase(String name, String bundleId) async {
  final IosApp app = await _runOperation(
    () => iosApps.create(
      IosApp()
        ..displayName = name
        ..bundleId = bundleId,
      _parentProject,
    ),
    (Map<String, dynamic> data) => IosApp.fromJson(data),
  );

  return iosApps.getConfig('${app.name}/config');
}
