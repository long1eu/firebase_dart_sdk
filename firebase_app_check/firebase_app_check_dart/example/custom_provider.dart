// A custom provider whose callback asks an HTTP endpoint of your own server for
// an App Check token. The server mints it with the Firebase Admin SDK
// (`appCheck().createToken(appId)`) after it has checked that the caller is
// your app, and answers with JSON:
//
//     {"token": "<App Check token>", "expireTimeMillis": 1767225600000}
//
// The callback is told what the request is for: `limitedUse` asks for a token
// to be consumed once, `forceRefresh` says that the previous token was
// rejected and must be replaced by a different one.
//
//     dart run example/custom_provider.dart --token-url https://example.com/app-check-token \
//       --api-key <key> --app-id <id> --project-id <project>

import 'dart:convert';

import 'package:args/args.dart';
import 'package:firebase_app_check_dart/firebase_app_check_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:http/http.dart' as http;

import 'common.dart';

Future<void> main(List<String> arguments) async {
  final ArgParser parser = exampleParser()
    ..addOption(
      'token-url',
      help: 'The endpoint of your server that mints tokens.',
    );
  final ArgResults results = parser.parse(arguments);
  final FirebaseApp app = exampleApp(parser, results);
  final String? tokenUrl = results.option('token-url');
  if (tokenUrl == null) {
    print('Usage: dart run example/custom_provider.dart ${parser.usage}');
    return;
  }
  final http.Client client = http.Client();
  final FirebaseAppCheck appCheck = FirebaseAppCheck(
    app,
    provider: CustomAppCheckProvider(
      getToken: ({required bool limitedUse, required bool forceRefresh}) async {
        final Uri url = Uri.parse(tokenUrl).replace(
          queryParameters: <String, String>{
            if (limitedUse) 'limitedUse': 'true',
            if (forceRefresh) 'forceRefresh': 'true',
          },
        );
        final http.Response response = await client.post(url);
        if (response.statusCode != 200) {
          throw StateError('The token server answered ${response.statusCode}.');
        }
        final Map<String, Object?> body =
            jsonDecode(response.body) as Map<String, Object?>;
        return AppCheckToken(
          token: body['token']! as String,
          expireTime: DateTime.fromMillisecondsSinceEpoch(
            body['expireTimeMillis']! as int,
            isUtc: true,
          ),
        );
      },
    ),
    logger: exampleLogger,
    autoRefresh: false,
  );
  try {
    print(describeToken(await appCheck.getToken()));
    print(describeToken(await appCheck.getLimitedUseToken()));
  } on FirebaseAppCheckException catch (e) {
    // A failure of the callback arrives as `provider-error`; the error the
    // callback threw is in `cause`, never in the message.
    print('Failed: ${e.code}: ${e.message}');
  } finally {
    client.close();
    await appCheck.close();
  }
}
