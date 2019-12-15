// File created by
// Lung Razvan <long1eu>
// on 11/12/2019

part of firebase_auth_example;

Future<void> init(File configFile) async {
  Hive.init('./hives');

  await _initializeSecrets(configFile);

  final Box<dynamic> firebaseBox =
      await Hive.openBox<dynamic>('firebase_auth', encryptionKey: 'dEtk7JiOCJirguAJEM7wOSkcNtfZO0DG'.codeUnits);
  final Dependencies dependencies = Dependencies(box: firebaseBox);
  final FirebaseOptions options =
      FirebaseOptions(apiKey: 'AIzaSyDsSL36xeTPP-JdGZBdadhEm2bxNpMqlUQ', applicationId: 'appId');
  FirebaseApp.withOptions(options, dependencies);
}

String _twitterConsumerKey;
String _twitterConsumerKeySecret;
String _twitterAccessToken;
String _twitterAccessTokenSecret;
String _facebookAccessToken;
String _googleClientId;
String _googleClientSecret;

final List<String> _variablesNames = <String>[
  'twitterConsumerKey',
  'twitterConsumerKeySecret',
  'twitterAccessToken',
  'twitterAccessTokenSecret',
  'facebookAccessToken',
  'googleClientId',
  'googleClientSecret',
];

Future<void> _initializeSecrets(File configFile) async {
  final Map<String, String> config = Map<String, String>.from(jsonDecode(await configFile.readAsString()));
  for (String variable in _variablesNames) {
    switch (variable) {
      case 'twitterConsumerKey':
        _twitterConsumerKey = config[variable];
        break;
      case 'twitterConsumerKeySecret':
        _twitterConsumerKeySecret = config[variable];
        break;
      case 'twitterAccessToken':
        _twitterAccessToken = config[variable];
        break;
      case 'twitterAccessTokenSecret':
        _twitterAccessTokenSecret = config[variable];
        break;
      case 'facebookAccessToken':
        _facebookAccessToken = config[variable];
        break;
      case 'googleClientId':
        _googleClientId = config[variable];
        break;
      case 'googleClientSecret':
        _googleClientSecret = config[variable];
        break;
    }
  }
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
