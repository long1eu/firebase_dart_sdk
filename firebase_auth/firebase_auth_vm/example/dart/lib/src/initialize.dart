// File created by
// Lung Razvan <long1eu>
// on 11/12/2019

part of firebase_auth_example;

Future<void> init(Map<String, String> config) async {
  Hive.init('./hives');

  await _initializeSecrets(config);

  final Box<String> firebaseBox =
      await Hive.openBox<String>('firebase_auth', encryptionCipher: HiveAesCipher(_hiveEncryptionKey.codeUnits));
  final Dependencies dependencies = Dependencies(box: firebaseBox);
  final FirebaseOptions options = FirebaseOptions(
    apiKey: _apiKey,
    appId: 'appId',
    messagingSenderId: 'null',
    projectId: 'null',
  );
  FirebaseApp.withOptions(options, dependencies: dependencies);
}

String _apiKey;
String _hiveEncryptionKey;
String _twitterConsumerKey;
String _twitterConsumerKeySecret;
String _twitterAccessToken;
String _twitterAccessTokenSecret;
String _facebookAccessToken;
String _googleClientId;
String _googleClientSecret;
String _githubClientId;
String _yahooClientId;
String _microsoftClientId;

final List<String> _variablesNames = <String>[
  'apiKey',
  'hiveEncryptionKey',
  'twitterConsumerKey',
  'twitterConsumerKeySecret',
  'twitterAccessToken',
  'twitterAccessTokenSecret',
  'facebookAccessToken',
  'googleClientId',
  'googleClientSecret',
  'githubClientId',
  'yahooClientId',
  'microsoftClientId',
];

Future<void> _initializeSecrets(Map<String, String> config) async {
  for (String variable in _variablesNames) {
    switch (variable) {
      case 'apiKey':
        _apiKey = config[variable];
        break;
      case 'hiveEncryptionKey':
        _hiveEncryptionKey = config[variable];
        break;
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
      case 'githubClientId':
        _githubClientId = config[variable];
        break;
      case 'yahooClientId':
        _yahooClientId = config[variable];
        break;
      case 'microsoftClientId':
        _microsoftClientId = config[variable];
        break;
    }
  }
}

class Dependencies extends PlatformDependencies {
  Dependencies({@required this.box});

  @override
  final Box<String> box;
}
