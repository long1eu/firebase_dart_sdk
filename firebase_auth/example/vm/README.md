# Firebase Auth Dart SDK - CLI example app

This app demonstrate most of the features Firebase Auth Dart SDK has to offer. You can run the `main.dart` file in the bin 
directory providing you configuration file:

```$json
{
  "apiKey": "",
  "hiveEncryptionKey": "",
  "twitterConsumerKey": "",
  "twitterConsumerKeySecret": "",
  "twitterAccessToken": "",
  "twitterAccessTokenSecret": "",
  "facebookAccessToken": "",
  "googleClientId": "",
  "googleClientSecret": "",
  "githubClientId": "",
  "githubClientSecret": "",
  "yahooClientId": "",
  "yahooClientSecret": "",
  "microsoftClientId": "",
  "microsoftClientSecret": ""
}
``` 

`dart main.dart config.json`

You can also use the binary `firebase_auth` found in the `bin` folder that points to the demo Firebase project. By using the file you agree with the Terms of 
Service and Privacy Policy mentioned at https://flutter-sdk.firebaseapp.com/tac.html and https://flutter-sdk.firebaseapp.com/pp.html.