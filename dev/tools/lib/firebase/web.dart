// File created by
// Lung Razvan <long1eu>
// on 06/03/2020

part of 'firebase.dart';

ProjectsWebAppsResourceApi get webApps => firebaseApi.projects.webApps;

Future<void> createWebApp({
  @required String path,
  @required String clientId,
  @required String displayName,
  String webPackagesVersion = '7.10.0',
}) async {
  assert(displayName != null && displayName.isNotEmpty);

  final WebAppConfig config = await _addWebAppToFirebase(displayName);
  final File htmlFile = File('$path/example/web/index.html');
  final String data = htmlFile.readAsStringSync();

  final String result = data.replaceAll(
      '<link rel="manifest" href="/manifest.json">',
      '''<link rel="manifest" href="/manifest.json">\n${getConfiguration(clientId, webPackagesVersion, config)}''');

  htmlFile.writeAsStringSync(result);
}

Future<WebAppConfig> _addWebAppToFirebase(String displayName) async {
  final WebApp app = await _runOperation(
    () => webApps.create(
      WebApp()..displayName = displayName,
      _parentProject,
    ),
    (Map<String, dynamic> data) => WebApp.fromJson(data),
  );

  return webApps.getConfig('${app.name}/config');
}

String getConfiguration(String clientId, String version, WebAppConfig config) {
  return '''
  <meta name="google-signin-client_id" content="$clientId">
  <script src="https://www.gstatic.com/firebasejs/$version/firebase-app.js"></script>
  <script src="https://www.gstatic.com/firebasejs/$version/firebase-auth.js"></script>
  <script src="https://www.gstatic.com/firebasejs/$version/firebase-analytics.js"></script>
  <script>
      firebase.initializeApp({
          "projectId": "${config.projectId}",
          "appId": "${config.appId}",
          "databaseURL": "${config.databaseURL}",
          "storageBucket": "${config.storageBucket}",
          "locationId": "${config.locationId}",
          "apiKey": "${config.apiKey}",
          "authDomain": "${config.authDomain}",
          "messagingSenderId": "${config.messagingSenderId}"
      });
  </script>''';
}
