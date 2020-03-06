// File created by
// Lung Razvan <long1eu>
// on 06/03/2020

part of 'firebase.dart';

ProjectsWebAppsResourceApi get webApps => _firebaseApi.projects.webApps;

Future<void> createWebApp(
    {@required String path, @required String displayName}) async {
  assert(displayName != null && displayName.isNotEmpty);

  final WebAppConfig config = await _addWebAppToFirebase(displayName);
  print(jsonEncode(config.toJson()));

  final Directory webDir = Directory('$path/example/web');

  final File htmlFile = File('$path/example/web/index.html');
  final String data = htmlFile.readAsStringSync();

  final Document document = HtmlParser(data).parse();
  print(document.head);
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
