// Copyright 2019 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// ignore_for_file: public_member_api_docs

import 'dart:async';
import 'dart:convert';

import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:googleapis_auth/googleapis_auth.dart';
import 'package:html_unescape/html_unescape.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_dartio/google_sign_in_dartio.dart';
import 'package:googleapis/gmail/v1.dart';
import 'package:googleapis/people/v1.dart';

import 'platform_js.dart' if (dart.library.io) 'platform_io.dart';

GoogleSignIn _googleSignIn = GoogleSignIn(scopes: <String>[
  'email',
  'profile',
  PeopleServiceApi.contactsReadonlyScope
]);

Future<void> main() async {
  if (isDesktop) {
    await GoogleSignInDart.register(
      exchangeEndpoint:
          'https://us-central1-flutter-sdk.cloudfunctions.net/authHandler',
      clientId:
          '233259864964-go57eg1ones74e03adlqvbtg2av6tivb.apps.googleusercontent.com',
    );
  }

  runApp(
    MaterialApp(
      title: 'Google Sign In',
      home: SignInDemo(),
    ),
  );
}

class SignInDemo extends StatefulWidget {
  @override
  State createState() => SignInDemoState();
}

class SignInDemoState extends State<SignInDemo> {
  StreamSubscription<GoogleSignInAccount> sub;
  AuthClient _client;
  GoogleSignInAccount _currentUser;
  String _contactText;
  String _emailText;

  @override
  void initState() {
    super.initState();
    sub = _googleSignIn.onCurrentUserChanged.listen(_onUserChanged);
    _googleSignIn.signInSilently();
  }

  Future<void> _onUserChanged(GoogleSignInAccount account) async {
    setState(() => _currentUser = account);
    if (_currentUser != null) {
      _client = await _googleSignIn.authenticatedClient();
      await _handleGetContact();
    }
  }

  Future<void> _handleGetContact() async {
    setState(() => _contactText = 'Loading contact info...');

    final PeopleConnectionsResource connectionsApi =
        PeopleServiceApi(_client).people.connections;

    final ListConnectionsResponse listResult = await connectionsApi.list(
      'people/me',
      requestMask_includeField: 'person.names',
    );

    String contact;
    final List<Person> connections = listResult.connections;
    if (connections != null && connections.isNotEmpty) {
      connections.shuffle();
      final Person person = connections.firstWhere(
        (Person person) =>
            person.names.any((Name name) => name.displayName != null),
        orElse: () => null,
      );

      if (person != null) {
        final Name name =
            person.names.firstWhere((Name name) => name.displayName != null);
        contact = name.displayName;
      }
    }

    setState(() {
      if (contact != null) {
        _contactText = contact;
      } else {
        _contactText = 'No contacts to display.';
      }
    });
  }

  Future<void> _handleGetEmail() async {
    setState(() => _emailText = 'Loading emails...');

    final bool granted = await _googleSignIn
        .requestScopes(<String>[GmailApi.gmailReadonlyScope]);

    if (!granted) {
      setState(() => _emailText = 'Gmail scope was not granted by the user.');
      return;
    }

    _client = await _googleSignIn.authenticatedClient();
    final UsersMessagesResource messagesApi = GmailApi(_client).users.messages;

    final ListMessagesResponse listResult = await messagesApi.list('me');

    String messageSnippet;
    if (listResult.messages != null && listResult.messages.isNotEmpty) {
      for (Message message in listResult.messages..shuffle()) {
        message = await messagesApi.get('me', message.id, format: 'FULL');
        final String snippet = message.snippet;
        if (snippet != null && snippet.trim().isNotEmpty) {
          messageSnippet = HtmlUnescape().convert(snippet);
          break;
        }
      }
    }

    setState(() {
      if (messageSnippet != null) {
        _emailText = messageSnippet;
      } else {
        _emailText = 'No contacts to display.';
      }
    });
  }

  Future<void> _handleSignIn() async {
    try {
      await _googleSignIn.signIn();
    } catch (error) {
      print(error);
    }
  }

  void _handleSignOut() {
    _googleSignIn.disconnect();
  }

  @override
  void dispose() {
    sub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Google Sign In'),
      ),
      body: Builder(
        builder: (BuildContext context) {
          if (_currentUser == null) {
            return Center(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  const Text('You are not currently signed in.'),
                  const SizedBox(height: 16.0),
                  ElevatedButton(
                    onPressed: _handleSignIn,
                    child: const Text('SIGN IN'),
                  ),
                ],
              ),
            );
          }

          return ListView(
            children: <Widget>[
              ListTile(
                leading: kIsWeb
                    ? GoogleUserCircleAvatar(
                        identity: _currentUser,
                      )
                    : ClipOval(
                        child: Image.network(
                          _currentUser.photoUrl ??
                              'https://lh3.googleusercontent.com/a/default-user=s160-c',
                        ),
                      ),
                title: Text(_currentUser.displayName ?? ''),
                subtitle: Text(_currentUser.email ?? ''),
              ),
              if (_contactText != null)
                ListTile(
                  title: Text(
                    _contactText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: const Text('People Api'),
                ),
              if (_emailText != null)
                ListTile(
                  title: Text(
                    _emailText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: const Text('Gmail Api'),
                ),
              ButtonBar(
                children: <Widget>[
                  TextButton(
                    onPressed: _handleSignOut,
                    child: const Text('SIGN OUT'),
                  ),
                  TextButton(
                    onPressed: () {
                      _handleGetContact();
                      _handleGetEmail();
                    },
                    child: const Text('REFRESH'),
                  ),
                  TextButton(
                    onPressed: _handleGetEmail,
                    child: const Text('ADD GMAIL SCOPE'),
                  ),
                ],
              )
            ],
          );
        },
      ),
    );
  }
}
