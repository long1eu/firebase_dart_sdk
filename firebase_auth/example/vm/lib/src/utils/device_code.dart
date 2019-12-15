// File created by
// Lung Razvan <long1eu>
// on 15/12/2019

part of firebase_auth_example;

/// Signature for building a CodeResponse form the response that we received from [DeviceLogin._requestCodeUrl]
typedef CodeResponseBuilder = CodeResponse Function(Map<String, dynamic> response);

/// Signature for validating the response of each pool. If the response is not valid, should return a non null value
/// witch will be thrown.
typedef CodePollValidator = String Function(Map<String, dynamic> pollResponse);

class DeviceLogin {
  DeviceLogin({
    @required Uri requestCodeUrl,
    @required Uri pollUrl,
    @required String providerName,
    @required CodePollValidator codePollValidator,
    @required CodeResponseBuilder codeResponseBuilder,
  })  : _requestCodeUrl = requestCodeUrl,
        _pollUrl = pollUrl,
        _client = Client(),
        _providerName = providerName,
        _codePollValidator = codePollValidator,
        _codeResponseBuilder = codeResponseBuilder;

  /// The url that will provide the user code
  final Uri _requestCodeUrl;

  /// The url were well poll to see if the user completed the authentication
  final Uri _pollUrl;

  final Client _client;

  /// The name of the provider used in the interaction with the user
  final String _providerName;

  /// Validate the response of each poll response.
  ///
  /// If the response is valid return a null value. The Future returned by [credentials] will complete with that value.
  /// If the response is not valid but you want to continue polling return an empty string else return the error message
  /// that will be thrown.
  final CodePollValidator _codePollValidator;

  /// Used to build a [CodeResponse] witch contains a unified or retrieving the user_code, verification_uri etc.
  final CodeResponseBuilder _codeResponseBuilder;

  Future<Map<String, dynamic>> get credentials async {
    final Progress progress = Progress('Fetching $_providerName code')..show();
    final Response response = await _client.post(_requestCodeUrl);
    await progress.cancel();

    final CodeResponse codeResponse = _codeResponseBuilder(Map<String, dynamic>.from(jsonDecode(response.body)));
    Uri verifyUri = Uri.parse(codeResponse.verificationUri);
    verifyUri = verifyUri
        .replace(queryParameters: <String, String>{...verifyUri.queryParameters, 'user_code': codeResponse.userCode});

    console //
      ..println(
          'Visit this link and enter ${codeResponse.userCode.yellow.reset} to get the $_providerName credentials.')
      ..println(verifyUri)
      ..println();

    final Completer<Map<String, dynamic>> completer = Completer<Map<String, dynamic>>();
    unawaited(_poll(codeResponse, completer));
    return completer.future;
  }

  Future<void> _poll(CodeResponse codeResponse, Completer<Map<String, dynamic>> completer) async {
    final Progress progress = Progress('Waiting for you authorization on $_providerName')..show();
    final DateTime start = DateTime.now();
    do {
      await Future<void>.delayed(codeResponse.interval);
      final Uri pollUrl =
          _pollUrl.replace(queryParameters: <String, String>{..._pollUrl.queryParameters, 'code': codeResponse.code});

      final Response response = await _client.post(pollUrl);
      final Map<String, dynamic> responseData = jsonDecode(response.body);

      final String error = _codePollValidator(responseData);

      if (error == null) {
        completer.complete(responseData);
        break;
      } else if (error != null && error.isNotEmpty) {
        throw StateError(error);
      }
    } while (start.difference(DateTime.now()) < codeResponse.expiresIn);
    await progress.cancel();
  }
}

class CodeResponse {
  CodeResponse({
    @required this.code,
    @required this.userCode,
    @required this.verificationUri,
    @required this.expiresIn,
    @required this.interval,
  });

  final String code;
  final String userCode;
  final String verificationUri;
  final Duration expiresIn;
  final Duration interval;
}
