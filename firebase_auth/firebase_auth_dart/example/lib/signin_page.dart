// Copyright 2020 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:firebase_core_dart/firebase_core_dart.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:flutter_signin_button/flutter_signin_button.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Entrypoint example for various sign-in flows with Firebase.
class SignInPage extends StatelessWidget {
  const SignInPage({Key key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sign In & Out'),
        actions: <Widget>[
          Builder(builder: (BuildContext context) {
            return FlatButton(
              textColor: Theme.of(context).buttonColor,
              onPressed: () async {
                final User user = FirebaseAuth.instance.currentUser;
                if (user == null) {
                  Scaffold.of(context).showSnackBar(const SnackBar(content: Text('No one has signed in.')));
                  return;
                }
                await FirebaseAuth.instance.signOut();
                final String uid = user.uid;
                Scaffold.of(context).showSnackBar(SnackBar(content: Text('$uid has successfully signed out.')));
              },
              child: const Text('Sign out'),
            );
          })
        ],
      ),
      body: Builder(builder: (BuildContext context) {
        return ListView(
          padding: const EdgeInsets.all(16.0),
          scrollDirection: Axis.vertical,
          children: const <Widget>[
            _EmailPasswordForm(),
            _EmailLinkSignInSection(),
            _AnonymouslySignInSection(),
            _PhoneSignInSection(),
            _OtherProvidersSignInSection(),
          ],
        );
      }),
    );
  }
}

class _EmailPasswordForm extends StatefulWidget {
  const _EmailPasswordForm({Key key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _EmailPasswordFormState();
}

class _EmailPasswordFormState extends State<_EmailPasswordForm> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  Future<void> _signInWithEmailAndPassword() async {
    try {
      final String email = _emailController.text.trim();
      final String password = _passwordController.text;

      final UserCredential userCredential =
          await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: password);
      final User user = userCredential.user;

      Scaffold.of(context).showSnackBar(SnackBar(content: Text('${user.email} signed in')));
    } catch (e) {
      Scaffold.of(context).showSnackBar(const SnackBar(content: Text('Failed to sign in with Email & Password')));
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                alignment: Alignment.center,
                child: const Text(
                  'Sign in with email and password',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(labelText: 'Email'),
                validator: (String value) {
                  if (value.isEmpty) {
                    return 'Please enter some text';
                  }
                  return null;
                },
              ),
              TextFormField(
                controller: _passwordController,
                decoration: const InputDecoration(labelText: 'Password'),
                validator: (String value) {
                  if (value.isEmpty) {
                    return 'Please enter some text';
                  }
                  return null;
                },
                obscureText: true,
              ),
              Container(
                padding: const EdgeInsets.only(top: 16.0),
                alignment: Alignment.center,
                child: SignInButton(
                  Buttons.Email,
                  text: 'Sign In',
                  onPressed: () {
                    if (_formKey.currentState.validate()) {
                      _signInWithEmailAndPassword();
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmailLinkSignInSection extends StatefulWidget {
  const _EmailLinkSignInSection({Key key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _EmailLinkSignInSectionState();
}

class _EmailLinkSignInSectionState extends State<_EmailLinkSignInSection> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();

  String _userEmail;

  Future<void> _signInWithEmailAndLink() async {
    try {
      _userEmail = _emailController.text;
      await FirebaseAuth.instance.sendSignInLinkToEmail(
        email: _userEmail,
        actionCodeSettings: ActionCodeSettings(
          url: 'https://react-native-firebase-testing.firebaseapp.com/emailSignin',
          handleCodeInApp: true,
          iOS: <String, String>{
            'bundleId': 'io.flutter.plugins.firebaseAuthExample',
          },
          android: <String, dynamic>{
            'packageName': 'io.flutter.plugins.firebaseauthexample',
            'androidInstallIfNotAvailable': true,
            'androidMinimumVersion': '1',
          },
        ),
      );

      Scaffold.of(context).showSnackBar(SnackBar(content: Text('An email has been sent to $_userEmail')));
    } catch (e) {
      print(e);
      Scaffold.of(context).showSnackBar(const SnackBar(content: Text('Sending email failed')));
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                alignment: Alignment.center,
                child: const Text(
                  'Test sign in with email and link',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(labelText: 'Email'),
                validator: (String value) {
                  if (value.isEmpty) {
                    return 'Please enter your email.';
                  }
                  return null;
                },
              ),
              Container(
                padding: const EdgeInsets.only(top: 16.0),
                alignment: Alignment.center,
                child: SignInButtonBuilder(
                  icon: Icons.insert_link,
                  text: 'Sign In',
                  backgroundColor: Colors.blueGrey[700],
                  onPressed: _signInWithEmailAndLink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnonymouslySignInSection extends StatefulWidget {
  const _AnonymouslySignInSection({Key key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _AnonymouslySignInSectionState();
}

class _AnonymouslySignInSectionState extends State<_AnonymouslySignInSection> {
  bool _success;
  String _uid;

  String get _message {
    if (_success == null) {
      return '';
    } else {
      if (_success) {
        return 'Successfully signed in, uid: $_uid';
      } else {
        return 'Sign in failed';
      }
    }
  }

  // Example code of how to sign in anonymously.
  Future<void> _signInAnonymously() async {
    try {
      final UserCredential userCredential = await FirebaseAuth.instance.signInAnonymously();
      final User user = userCredential.user;

      Scaffold.of(context).showSnackBar(SnackBar(content: Text('Signed in Anonymously as user ${user.uid}')));
    } catch (e) {
      Scaffold.of(context).showSnackBar(const SnackBar(content: Text('Failed to sign in Anonymously')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              alignment: Alignment.center,
              child: const Text(
                'Test sign in anonymously',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            Container(
              padding: const EdgeInsets.only(top: 16.0),
              alignment: Alignment.center,
              child: SignInButtonBuilder(
                text: 'Sign In',
                icon: Icons.person_outline,
                backgroundColor: Colors.deepPurple,
                onPressed: _signInAnonymously,
              ),
            ),
            Visibility(
              visible: _success != null,
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  _message,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}

class _PhoneSignInSection extends StatefulWidget {
  const _PhoneSignInSection({Key key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _PhoneSignInSectionState();
}

class _PhoneSignInSectionState extends State<_PhoneSignInSection> {
  final TextEditingController _phoneNumberController = TextEditingController();
  final TextEditingController _smsController = TextEditingController();

  String _message = '';
  String _verificationId;

  Future<void> _verifyPhoneNumber() async {
    setState(() {
      _message = '';
    });

    Future<void> verificationCompleted(PhoneAuthCredential phoneAuthCredential) async {
      await FirebaseAuth.instance.signInWithCredential(phoneAuthCredential);
      Scaffold.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Phone number automatically verified and user signed in: $phoneAuthCredential',
          ),
        ),
      );
    }

    void verificationFailed(FirebaseAuthException authException) {
      setState(() {
        _message = 'Phone number verification failed. Code: ${authException.code}. Message: ${authException.message}';
      });
    }

    void codeSent(String verificationId, [int forceResendingToken]) {
      Scaffold.of(context)
          .showSnackBar(const SnackBar(content: Text('Please check your phone for the verification code.')));
      _verificationId = verificationId;
    }

    void codeAutoRetrievalTimeout(String verificationId) {
      _verificationId = verificationId;
    }

    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: _phoneNumberController.text,
        timeout: const Duration(seconds: 5),
        verificationCompleted: verificationCompleted,
        verificationFailed: verificationFailed,
        codeSent: codeSent,
        codeAutoRetrievalTimeout: codeAutoRetrievalTimeout,
      );
    } catch (e) {
      Scaffold.of(context).showSnackBar(SnackBar(content: Text('Failed to Verify Phone Number: $e')));
    }
  }

  Future<void> _signInWithPhoneNumber() async {
    try {
      final String smsCode = _smsController.text.trim();
      final AuthCredential credential = PhoneAuthProvider.credential(verificationId: _verificationId, smsCode: smsCode);
      final UserCredential userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
      final User user = userCredential.user;

      Scaffold.of(context).showSnackBar(SnackBar(content: Text('Successfully signed in UID: ${user.uid}')));
    } catch (e) {
      print(e);
      Scaffold.of(context).showSnackBar(const SnackBar(content: Text('Failed to sign in')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              alignment: Alignment.center,
              child: const Text(
                'Test sign in with phone number',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            TextFormField(
              controller: _phoneNumberController,
              decoration: const InputDecoration(labelText: 'Phone number (+x xxx-xxx-xxxx)'),
              validator: (String value) {
                if (value.isEmpty) {
                  return 'Phone number (+x xxx-xxx-xxxx)';
                }
                return null;
              },
            ),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              alignment: Alignment.center,
              child: SignInButtonBuilder(
                icon: Icons.contact_phone,
                backgroundColor: Colors.deepOrangeAccent[700],
                text: 'Verify Number',
                onPressed: _verifyPhoneNumber,
              ),
            ),
            TextField(
              controller: _smsController,
              decoration: const InputDecoration(labelText: 'Verification code'),
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
              ],
            ),
            Container(
              padding: const EdgeInsets.only(top: 16.0),
              alignment: Alignment.center,
              child: SignInButtonBuilder(
                icon: Icons.phone,
                backgroundColor: Colors.deepOrangeAccent[400],
                onPressed: _signInWithPhoneNumber,
                text: 'Sign In',
              ),
            ),
            Visibility(
              visible: _message != null,
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  _message,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}

class _OtherProvidersSignInSection extends StatefulWidget {
  const _OtherProvidersSignInSection({Key key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _OtherProvidersSignInSectionState();
}

class _OtherProvidersSignInSectionState extends State<_OtherProvidersSignInSection> {
  final TextEditingController _tokenController = TextEditingController();
  final TextEditingController _tokenSecretController = TextEditingController();

  int _selection = 0;
  bool _showAuthSecretTextField = false;
  bool _showProviderTokenField = true;
  String _provider = 'GitHub';

  void _handleRadioButtonSelected(int value) {
    setState(() {
      _selection = value;

      switch (_selection) {
        case 0:
          _provider = 'GitHub';
          _showAuthSecretTextField = false;
          _showProviderTokenField = true;
          break;
        case 1:
          _provider = 'Facebook';
          _showAuthSecretTextField = false;
          _showProviderTokenField = true;
          break;
        case 2:
          _provider = 'Twitter';
          _showAuthSecretTextField = true;
          _showProviderTokenField = true;
          break;
        default:
          _provider = 'Google';
          _showAuthSecretTextField = false;
          _showProviderTokenField = false;
      }
    });
  }

  void _signInWithOtherProvider() {
    switch (_selection) {
      case 0:
        _signInWithGithub();
        break;
      case 1:
        _signInWithFacebook();
        break;
      case 2:
        _signInWithTwitter();
        break;
      default:
        _signInWithGoogle();
    }
  }

  Future<void> _signInWithGithub() async {
    try {
      UserCredential userCredential;
      if (kIsMobile) {
        final AuthCredential credential = GithubAuthProvider.credential(_tokenController.text);
        userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
      } else {
        final GithubAuthProvider githubProvider = GithubAuthProvider();
        userCredential = await FirebaseAuth.instance.signInWithPopup(githubProvider);
      }

      final User user = userCredential.user;
      Scaffold.of(context).showSnackBar(SnackBar(content: Text('Sign In ${user.uid} with GitHub')));
    } catch (e) {
      print(e);
      Scaffold.of(context).showSnackBar(SnackBar(content: Text('Failed to sign in with GitHub: $e')));
    }
  }

  Future<void> _signInWithFacebook() async {
    try {
      UserCredential userCredential;
      if (kIsMobile) {
        final AuthCredential credential = FacebookAuthProvider.credential(_tokenController.text);
        userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
      } else {
        final FacebookAuthProvider githubProvider = FacebookAuthProvider();
        userCredential = await FirebaseAuth.instance.signInWithPopup(githubProvider);
      }
      final User user = userCredential.user;

      Scaffold.of(context).showSnackBar(SnackBar(content: Text('Sign In ${user.uid} with Facebook')));
    } catch (e) {
      print(e);
      Scaffold.of(context).showSnackBar(SnackBar(content: Text('Failed to sign in with Facebook: $e')));
    }
  }

  Future<void> _signInWithTwitter() async {
    try {
      UserCredential userCredential;

      if (kIsMobile) {
        final AuthCredential credential =
            TwitterAuthProvider.credential(accessToken: _tokenController.text, secret: _tokenSecretController.text);
        userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
      } else {
        final TwitterAuthProvider twitterProvider = TwitterAuthProvider();
        userCredential = await FirebaseAuth.instance.signInWithPopup(twitterProvider);
      }

      final User user = userCredential.user;

      Scaffold.of(context).showSnackBar(SnackBar(content: Text('Sign In ${user.uid} with Twitter')));
    } catch (e) {
      print(e);
      Scaffold.of(context).showSnackBar(SnackBar(content: Text('Failed to sign in with Twitter: $e')));
    }
  }

  Future<void> _signInWithGoogle() async {
    try {
      final GoogleSignInAccount googleUser = await GoogleSignIn().signIn();
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final GoogleAuthCredential googleAuthCredential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final UserCredential userCredential = await FirebaseAuth.instance.signInWithCredential(googleAuthCredential);

      final User user = userCredential.user;
      Scaffold.of(context).showSnackBar(SnackBar(content: Text('Sign In ${user.uid} with Google')));
    } catch (e) {
      print(e);
      Scaffold.of(context).showSnackBar(SnackBar(content: Text('Failed to sign in with Google: $e')));
    }
  }

  Buttons get _button {
    switch (_provider) {
      case 'GitHub':
        return Buttons.GitHub;
      case 'Facebook':
        return Buttons.Facebook;
      case 'Twitter':
        return Buttons.Twitter;
      case 'GoogleDark':
        return Buttons.GoogleDark;
      default:
        throw FallThroughError();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              alignment: Alignment.center,
              child: const Text(
                'Social Authentication',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            Container(
              padding: const EdgeInsets.only(top: 16.0),
              alignment: Alignment.center,
              child: kIsWeb
                  ? const Text(
                      'When using Flutter Web, API keys are configured through the Firebase Console. The below providers demonstrate how this works',
                    )
                  : const Text(
                      'We do not provide an API to obtain the token for below providers apart from Google on Mobile platforms.'
                      'Please use a third party service to obtain token for other providers.',
                    ),
            ),
            Container(
              padding: const EdgeInsets.only(top: 16.0),
              alignment: Alignment.center,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  ListTile(
                    title: const Text('GitHub'),
                    leading: Radio<int>(
                      value: 0,
                      groupValue: _selection,
                      onChanged: _handleRadioButtonSelected,
                    ),
                  ),
                  Visibility(
                    visible: !kIsWeb,
                    child: ListTile(
                      title: const Text('Facebook'),
                      leading: Radio<int>(
                        value: 1,
                        groupValue: _selection,
                        onChanged: _handleRadioButtonSelected,
                      ),
                    ),
                  ),
                  ListTile(
                    title: const Text('Twitter'),
                    leading: Radio<int>(
                      value: 2,
                      groupValue: _selection,
                      onChanged: _handleRadioButtonSelected,
                    ),
                  ),
                  ListTile(
                    title: const Text('Google'),
                    leading: Radio<int>(
                      value: 3,
                      groupValue: _selection,
                      onChanged: _handleRadioButtonSelected,
                    ),
                  ),
                ],
              ),
            ),
            Visibility(
              visible: _showProviderTokenField && !kIsWeb,
              child: TextField(
                controller: _tokenController,
                decoration: const InputDecoration(labelText: 'Enter provider\'s token'),
              ),
            ),
            Visibility(
              visible: _showAuthSecretTextField && !kIsWeb,
              child: TextField(
                controller: _tokenSecretController,
                decoration: const InputDecoration(labelText: 'Enter provider\'s authTokenSecret'),
              ),
            ),
            Container(
              padding: const EdgeInsets.only(top: 16.0),
              alignment: Alignment.center,
              child: SignInButton(
                _button,
                text: 'Sign In',
                onPressed: _signInWithOtherProvider,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
