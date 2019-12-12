// File created by
// Lung Razvan <long1eu>
// on 11/12/2019

part of firebase_auth_example;

Future<void> init() async {
  Hive.init('./hives');

  final Box<dynamic> box =
      await Hive.openBox<dynamic>('firebase_auth', encryptionKey: 'dEtk7JiOCJirguAJEM7wOSkcNtfZO0DG'.codeUnits);
  final Dependencies dependencies = Dependencies(box: box);
  final FirebaseOptions options =
      FirebaseOptions(apiKey: 'AIzaSyDsSL36xeTPP-JdGZBdadhEm2bxNpMqlUQ', applicationId: 'appId');
  FirebaseApp.withOptions(options, dependencies);
}

class Dependencies extends PlatformDependencies {
  Dependencies({@required this.box}) : headersBuilder = null;

  @override
  final Box<dynamic> box;

  @override
  final HeaderBuilder headersBuilder;

  @override
  InternalTokenProvider get authProvider => null;

  @override
  AuthUrlPresenter get authUrlPresenter => null;

  @override
  bool get isBackground => false;

  @override
  Future<bool> get isNetworkConnected => Future<bool>.value(true);

  @override
  String get locale => 'en';

  @override
  Stream<bool> get isBackgroundChanged => Stream<bool>.fromIterable(<bool>[false]);
}
