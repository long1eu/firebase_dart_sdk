// File created by
// Lung Razvan <long1eu>
// on 16/12/2019

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth_vm/firebase_auth_vm.dart';
import 'package:http/http.dart';
import 'package:meta/meta.dart';
import 'package:uuid/uuid.dart';

import 'extensions.dart';

class TwitterRequestToken {
  const TwitterRequestToken({this.token, this.tokenSecret});

  final String token;
  final String tokenSecret;
}

class TwitterClient extends BaseClient {
  TwitterClient({
    @required String consumerKey,
    @required String consumerKeySecret,
    @required String accessToken,
    @required String accessTokenSecret,
  })  : _client = Client(),
        _consumerKey = consumerKey,
        _accessToken = accessToken,
        _hasher =
            Hmac(sha1, utf8.encode('$consumerKeySecret&$accessTokenSecret'));

  final Hmac _hasher;
  final Client _client;
  final String _consumerKey;
  final String _accessToken;
  TwitterRequestToken _requestToken;
  HttpServer _server;

  TwitterRequestToken get requestToken => _requestToken;

  HttpServer get server => _server;

  Future<void> initialize() async {
    _server = await HttpServer.bind('localhost', 55937);
    _requestToken = await _getRequestToken();
  }

  Future<TwitterRequestToken> _getRequestToken() async {
    final Uri redirectUrl = Uri.http('localhost:55937', '__/auth/handler');

    final Response response = await this.post('oauth/request_token',
        headers: <String, String>{'oauth_callback': redirectUrl.toString()});

    final Map<String, String> responseData = response.body.queryParameters;
    final String token = responseData['oauth_token'];
    final String tokenSecret = responseData['oauth_token_secret'];
    final bool callbackConfirmed =
        responseData['oauth_callback_confirmed'] == 'true';
    assert(callbackConfirmed);

    return TwitterRequestToken(token: token, tokenSecret: tokenSecret);
  }

  @override
  Future<StreamedResponse> send(BaseRequest request) async {
    final Uri url =
        request.url.replace(scheme: 'https', host: 'api.twitter.com');
    final RequestImpl modifiedRequest =
        RequestImpl(request.method, url, request.finalize());

    final String nonce = Uuid().v4();
    // Add all the OAuth headers we'll need to use when constructing the hash.
    final Map<String, String> headers = <String, String>{
      'oauth_consumer_key': _consumerKey,
      'oauth_signature_method': 'HMAC-SHA1',
      'oauth_timestamp':
          (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString(),
      'oauth_nonce': nonce,
      'oauth_version': '1.0',
      'oauth_token': _accessToken,
      ...request.headers,
    };

    // Generate the OAuth signature and add it to our payload.
    headers['oauth_signature'] =
        _generateSignature(request.method, url, headers);

    // Build the OAuth HTTP Header from the data.
    final String value =
        headers.pairsWhere((String key) => key.startsWith('oauth')).join(', ');
    final String oAuthHeader = 'OAuth $value';

    modifiedRequest.headers
      ..clear()
      ..addAll(<String, String>{'Authorization': oAuthHeader});

    return _client.send(modifiedRequest);
  }

  String _generateSignature(String method, Uri url, Map<String, String> data) {
    return base64.encode(_hash(
        '$method&${_encode(url.toString())}&${_encode(data.pairs.join('&'))}'));
  }

  List<int> _hash(String data) => _hasher.convert(data.codeUnits).bytes;

  String _encode(String data) => percent.encode(data.codeUnits);
}

String get authSuccessHtml => '''<!DOCTYPE html>
<html class="mdl-js">
<head>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
    <style>.mdl-card{display:flex;flex-direction:column;font-size:16px;font-weight:400;min-height:200px;overflow:hidden;width:330px;z-index:1;position:relative;background:#fff;border-radius:2px;box-sizing:border-box}.mdl-card__title{align-items:center;color:#000;display:block;display:flex;justify-content:stretch;line-height:normal;padding:16px 16px;perspective-origin:165px 56px;transform-origin:165px 56px;box-sizing:border-box}.mdl-card__title-text{align-self:flex-end;color:inherit;display:block;display:flex;font-size:24px;font-weight:300;line-height:normal;overflow:hidden;transform-origin:149px 48px;margin:0}.mdl-card__subtitle-text{font-size:14px;color:rgba(0,0,0,.54);margin:0;text-align:center}@supports (-webkit-appearance:none){.mdl-progress:not(.mdl-progress--indeterminate):not(.mdl-progress--indeterminate)>.auxbar,.mdl-progress:not(.mdl-progress__indeterminate):not(.mdl-progress__indeterminate)>.auxbar{background-image:linear-gradient(to right,rgba(255,255,255,.7),rgba(255,255,255,.7)),linear-gradient(to right,#3f51b5 ,#3f51b5);mask:url(data:image/svg+xml;base64,PD94bWwgdmVyc2lvbj0iMS4wIj8+Cjxzdmcgd2lkdGg9IjEyIiBoZWlnaHQ9IjQiIHZpZXdQb3J0PSIwIDAgMTIgNCIgdmVyc2lvbj0iMS4xIiB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciPgogIDxlbGxpcHNlIGN4PSIyIiBjeT0iMiIgcng9IjIiIHJ5PSIyIj4KICAgIDxhbmltYXRlIGF0dHJpYnV0ZU5hbWU9ImN4IiBmcm9tPSIyIiB0bz0iLTEwIiBkdXI9IjAuNnMiIHJlcGVhdENvdW50PSJpbmRlZmluaXRlIiAvPgogIDwvZWxsaXBzZT4KICA8ZWxsaXBzZSBjeD0iMTQiIGN5PSIyIiByeD0iMiIgcnk9IjIiIGNsYXNzPSJsb2FkZXIiPgogICAgPGFuaW1hdGUgYXR0cmlidXRlTmFtZT0iY3giIGZyb209IjE0IiB0bz0iMiIgZHVyPSIwLjZzIiByZXBlYXRDb3VudD0iaW5kZWZpbml0ZSIgLz4KICA8L2VsbGlwc2U+Cjwvc3ZnPgo=)}}@keyframes indeterminate1{0%{left:0;width:0}50%{left:25%;width:75%}75%{left:100%;width:0}}@keyframes indeterminate2{0%{left:0;width:0}50%{left:0;width:0}75%{left:0;width:25%}100%{left:100%;width:0}}.firebase-container{background-color:#fff;box-sizing:border-box;-moz-box-sizing:border-box;-webkit-box-sizing:border-box;color:rgba(0,0,0,.87);direction:ltr;font:16px Roboto,arial,sans-serif;margin:0 auto;max-width:360px;overflow:hidden;padding-top:8px;position:relative;width:100%}.firebase-container#app-verification-screen{top:100px}.firebase-title{color:rgba(0,0,0,.87);direction:ltr;font-size:24px;font-weight:500;line-height:24px;margin:0;padding:0;text-align:center}@media (max-width:520px){.firebase-container{box-shadow:none;max-width:none;width:100%}}body{margin:0}.firebase-container{background-color:#fff;box-sizing:border-box;-moz-box-sizing:border-box;-webkit-box-sizing:border-box;color:rgba(0,0,0,.87);direction:ltr;font:16px Roboto,arial,sans-serif;margin:0 auto;max-width:360px;overflow:hidden;padding-top:8px;position:relative;width:100%}.firebase-container#app-verification-screen{top:100px}.firebase-title{color:rgba(0,0,0,.87);direction:ltr;font-size:24px;font-weight:500;line-height:24px;margin:0;padding:0;text-align:center}@media (max-width:520px){.firebase-container{box-shadow:none;max-width:none;width:100%}}</style>
</head>
<body>
<div>
    <div id="app-verification-screen" class="mdl-card mdl-shadow--2dp firebase-container">
        <div id="status-container">
            <h1 class="firebase-title" id="status-container-label">Application logged in.</h1>
            <h6 class="mdl-card__subtitle-text">This window can be closed now.</h6>
        </div>
    </div>
</div>
</body>
</html>''';
