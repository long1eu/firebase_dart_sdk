// File created by
// Lung Razvan <long1eu>
// on 06/03/2020

part of 'firebase.dart';

ProjectsWebAppsResourceApi get webApps => _firebaseApi.projects.webApps;

Future<WebAppConfig> createWebApp({@required String displayName}) async {
  assert(displayName != null && displayName.isNotEmpty);

  final WebApp app = await _runOperation(
    () => webApps.create(
      WebApp()..displayName = displayName,
      _parentProject,
    ),
    (Map<String, dynamic> data) => WebApp.fromJson(data),
  );

  return webApps.getConfig('${app.name}/config');
}
