// Copyright 2019 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:firebase_core_vm/firebase_core_vm.dart';
import 'package:firebase_dynamic_links/firebase_dynamic_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

final FirebaseAuth _auth = FirebaseAuth.instance;
final GoogleSignIn _googleSignIn = GoogleSignIn();

class SignInPage extends StatefulWidget {
  final String title = 'Sign in';

  @override
  State<StatefulWidget> createState() => SignInPageState();
}

class SignInPageState extends State<SignInPage> {
  // Example code for sign out.
  Future<void> _signOut() async {
    await _auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    print('_auth: ${FirebaseAuthPlatform.instance}');

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: <Widget>[
          Builder(builder: (BuildContext context) {
            return FlatButton(
              textColor: Theme.of(context).buttonColor,
              onPressed: () async {
                await _googleSignIn.signOut();
                final FirebaseUser user = await _auth.currentUser();
                if (user == null) {
                  Scaffold.of(context).showSnackBar(const SnackBar(
                    content: Text('No one has signed in.'),
                  ));
                  return;
                }
                await _signOut();
                final String uid = user.uid;
                Scaffold.of(context).showSnackBar(SnackBar(
                  content: Text('$uid has successfully signed out.'),
                ));
              },
              child: const Text('Sign out'),
            );
          })
        ],
      ),
      body: Builder(
        builder: (BuildContext context) {
          return ListView(
            scrollDirection: Axis.vertical,
            children: <Widget>[
              const _EmailPasswordForm(),
              if (kIsMobile) const _EmailLinkSignInSection(),
              const _AnonymouslySignInSection(),
              const _GoogleSignInSection(),
              _PhoneSignInSection(scaffold: Scaffold.of(context)),
              const _OtherProvidersSignInSection(),
            ],
          );
        },
      ),
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
  bool _success;
  String _userEmail;

  // Example code of how to sign in with email and password.
  Future<void> _signInWithEmailAndPassword() async {
    final FirebaseUser user = (await _auth.signInWithEmailAndPassword(
      email: _emailController.text,
      password: _passwordController.text,
    ))
        .user;
    if (user != null) {
      setState(() {
        _success = true;
        _userEmail = user.email;
      });
    } else {
      _success = false;
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(16),
            alignment: Alignment.center,
            child: const Text('Test sign in with email and password'),
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
          ),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            alignment: Alignment.center,
            child: RaisedButton(
              onPressed: () {
                if (_formKey.currentState.validate()) {
                  _signInWithEmailAndPassword();
                }
              },
              child: const Text('Submit'),
            ),
          ),
          Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              _success == null
                  ? ''
                  : (_success
                      ? 'Successfully signed in $_userEmail'
                      : 'Sign in failed'),
              style: TextStyle(color: Colors.red),
            ),
          )
        ],
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

  bool _success;
  String _userEmail;
  String _userID;

  @override
  void initState() {
    super.initState();
    FirebaseDynamicLinks.instance
        .onLink(onSuccess: _retrieveDynamicLink, onError: _dynamicLinkError);
    FirebaseDynamicLinks.instance.getInitialLink().then(_retrieveDynamicLink);
  }

  Future<void> _retrieveDynamicLink(PendingDynamicLinkData data) async {
    final Uri link = data?.link;

    if (link != null) {
      final FirebaseUser user = (await _auth.signInWithEmailAndLink(
        email: _userEmail,
        link: link.toString(),
      ))
          .user;

      if (user != null) {
        _userID = user.uid;
        _success = true;
      } else {
        _success = false;
      }

      setState(() {});
    }
  }

  Future<void> _dynamicLinkError(OnLinkErrorException error) async {
    setState(() {
      _success = false;
    });
  }

  Future<void> _signInWithEmailAndLink() async {
    _userEmail = _emailController.text;

    return _auth.sendSignInWithEmailLink(
      email: _userEmail,
      url: 'https://flutter-sdk.firebaseapp.com',
      handleCodeInApp: true,
      iOSBundleID: 'io.flutter.plugins.firebaseAuthExample',
      androidPackageName: 'io.flutter.plugins.firebaseauthexample',
      androidInstallIfNotAvailable: true,
      androidMinimumVersion: '1',
    );
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(16),
            alignment: Alignment.center,
            child: const Text('Test sign in with email and link'),
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
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            alignment: Alignment.center,
            child: RaisedButton(
              onPressed: () {
                if (_formKey.currentState.validate()) {
                  _signInWithEmailAndLink();
                }
              },
              child: const Text('Submit'),
            ),
          ),
          Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              _success == null
                  ? ''
                  : (_success
                      ? 'Successfully signed in, uid: $_userID'
                      : 'Sign in failed'),
              style: TextStyle(color: Colors.red),
            ),
          )
        ],
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
  String _userID;

  // Example code of how to sign in anonymously.
  Future<void> _signInAnonymously() async {
    final FirebaseUser user = (await _auth.signInAnonymously()).user;
    assert(user != null);
    assert(user.isAnonymous);
    assert(!user.isEmailVerified);
    assert(await user.getIdToken() != null);
    if (Platform.isIOS) {
      // Anonymous auth doesn't show up as a provider on iOS
      assert(user.providerData.isEmpty);
    } else if (Platform.isAndroid) {
      // Anonymous auth does show up as a provider on Android
      assert(user.providerData.length == 1);
      assert(user.providerData[0].providerId == 'firebase');
      assert(user.providerData[0].uid != null);
      assert(user.providerData[0].displayName == null);
      assert(user.providerData[0].photoUrl == null);
      assert(user.providerData[0].email == null);
    }

    final FirebaseUser currentUser = await _auth.currentUser();
    assert(user.uid == currentUser.uid);
    setState(() {
      if (user != null) {
        _success = true;
        _userID = user.uid;
      } else {
        _success = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(16),
          alignment: Alignment.center,
          child: const Text('Test sign in anonymously'),
        ),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 16.0),
          alignment: Alignment.center,
          child: RaisedButton(
            onPressed: _signInAnonymously,
            child: const Text('Sign in anonymously'),
          ),
        ),
        Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            _success == null
                ? ''
                : (_success
                    ? 'Successfully signed in, uid: $_userID'
                    : 'Sign in failed'),
            style: TextStyle(color: Colors.red),
          ),
        )
      ],
    );
  }
}

class _GoogleSignInSection extends StatefulWidget {
  const _GoogleSignInSection({Key key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _GoogleSignInSectionState();
}

class _GoogleSignInSectionState extends State<_GoogleSignInSection> {
  bool _success;
  String _userID;

  // Example code of how to sign in with google.
  Future<void> _signInWithGoogle() async {
    final GoogleSignInAccount googleUser = await _googleSignIn.signIn();
    final GoogleSignInAuthentication googleAuth =
        await googleUser.authentication;
    final AuthCredential credential = GoogleAuthProvider.getCredential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    final FirebaseUser user =
        (await _auth.signInWithCredential(credential)).user;

    assert(user.email != null);
    assert(!user.isAnonymous);
    assert(await user.getIdToken() != null);

    final FirebaseUser currentUser = await _auth.currentUser();
    assert(user.uid == currentUser.uid);
    setState(() {
      if (user != null) {
        _success = true;
        _userID = user.uid;
      } else {
        _success = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(16),
          alignment: Alignment.center,
          child: const Text('Test sign in with Google'),
        ),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 16.0),
          alignment: Alignment.center,
          child: RaisedButton(
            onPressed: _signInWithGoogle,
            child: const Text('Sign in with Google'),
          ),
        ),
        Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            _success == null
                ? ''
                : (_success
                    ? 'Successfully signed in, uid: $_userID'
                    : 'Sign in failed'),
            style: TextStyle(color: Colors.red),
          ),
        )
      ],
    );
  }
}

class _PhoneSignInSection extends StatefulWidget {
  const _PhoneSignInSection({Key key, this.scaffold}) : super(key: key);

  final ScaffoldState scaffold;

  @override
  State<StatefulWidget> createState() => _PhoneSignInSectionState();
}

class _PhoneSignInSectionState extends State<_PhoneSignInSection> {
  final TextEditingController _phoneNumberController = TextEditingController();
  final TextEditingController _smsController = TextEditingController();

  String _message = '';
  String _verificationId;

  // Example code of how to verify phone number
  Future<void> _verifyPhoneNumber() async {
    setState(() {
      _message = '';
    });
    void verificationCompleted(AuthCredential phoneAuthCredential) {
      _auth.signInWithCredential(phoneAuthCredential);
      setState(() {
        _message = 'Received phone auth credential: $phoneAuthCredential';
      });
    }

    void verificationFailed(AuthException authException) {
      setState(() {
        _message =
            'Phone number verification failed. Code: ${authException.code}. Message: ${authException.message}';
      });
    }

    Future<void> codeSent(String verificationId,
        [int forceResendingToken]) async {
      widget.scaffold.showSnackBar(const SnackBar(
        content: Text('Please check your phone for the verification code.'),
      ));
      _verificationId = verificationId;
    }

    void codeAutoRetrievalTimeout(String verificationId) {
      _verificationId = verificationId;
    }

    await _auth.verifyPhoneNumber(
      phoneNumber: _phoneNumberController.text,
      timeout: const Duration(seconds: 5),
      verificationCompleted: verificationCompleted,
      verificationFailed: verificationFailed,
      codeSent: codeSent,
      codeAutoRetrievalTimeout: codeAutoRetrievalTimeout,
    );
  }

  // Example code of how to sign in with phone.
  Future<void> _signInWithPhoneNumber() async {
    final AuthCredential credential = PhoneAuthProvider.getCredential(
      verificationId: _verificationId,
      smsCode: _smsController.text,
    );
    final FirebaseUser user =
        (await _auth.signInWithCredential(credential)).user;
    final FirebaseUser currentUser = await _auth.currentUser();
    assert(user.uid == currentUser.uid);
    setState(() {
      if (user != null) {
        _message = 'Successfully signed in, uid: ${user.uid}';
      } else {
        _message = 'Sign in failed';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(16),
          alignment: Alignment.center,
          child: const Text('Test sign in with phone number'),
        ),
        TextFormField(
          controller: _phoneNumberController,
          decoration: const InputDecoration(
              labelText: 'Phone number (+x xxx-xxx-xxxx)'),
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
          child: RaisedButton(
            onPressed: _verifyPhoneNumber,
            child: const Text('Verify phone number'),
          ),
        ),
        TextField(
          controller: _smsController,
          decoration: const InputDecoration(labelText: 'Verification code'),
        ),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 16.0),
          alignment: Alignment.center,
          child: RaisedButton(
            onPressed: _signInWithPhoneNumber,
            child: const Text('Sign in with phone number'),
          ),
        ),
        Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            _message,
            style: TextStyle(color: Colors.red),
          ),
        )
      ],
    );
  }
}

class _OtherProvidersSignInSection extends StatefulWidget {
  const _OtherProvidersSignInSection({Key key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _OtherProvidersSignInSectionState();
}

class _OtherProvidersSignInSectionState
    extends State<_OtherProvidersSignInSection> {
  final TextEditingController _tokenController = TextEditingController();
  final TextEditingController _tokenSecretController = TextEditingController();

  String _message = '';
  int _selection = 0;
  bool _showAuthSecretTextField = false;

  void _handleRadioButtonSelected(int value) {
    setState(() {
      _selection = value;
      if (_selection == 2) {
        _showAuthSecretTextField = true;
      } else {
        _showAuthSecretTextField = false;
      }
    });
  }

  // Example code of how to sign in with Github.
  Future<void> _signInWithGithub() async {
    final AuthCredential credential = GithubAuthProvider.getCredential(
      token: _tokenController.text,
    );
    final FirebaseUser user =
        (await _auth.signInWithCredential(credential)).user;
    assert(user.email != null);
    assert(user.displayName != null);
    assert(!user.isAnonymous);
    assert(await user.getIdToken() != null);

    final FirebaseUser currentUser = await _auth.currentUser();
    assert(user.uid == currentUser.uid);
    setState(() {
      if (user != null) {
        _message = 'Successfully signed in with Github. ${user.uid}';
      } else {
        _message = 'Failed to sign in with Github. ';
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
    }
  }

  // Example code of how to sign in with Facebook.
  Future<void> _signInWithFacebook() async {
    final AuthCredential credential = FacebookAuthProvider.getCredential(
      accessToken: _tokenController.text,
    );
    final FirebaseUser user =
        (await _auth.signInWithCredential(credential)).user;
    assert(user.email != null);
    assert(user.displayName != null);
    assert(!user.isAnonymous);
    assert(await user.getIdToken() != null);

    final FirebaseUser currentUser = await _auth.currentUser();
    assert(user.uid == currentUser.uid);
    setState(() {
      if (user != null) {
        _message = 'Successfully signed in with Facebook. ${user.uid}';
      } else {
        _message = 'Failed to sign in with Facebook. ';
      }
    });
  }

  // Example code of how to sign in with Twitter.
  Future<void> _signInWithTwitter() async {
    final AuthCredential credential = TwitterAuthProvider.getCredential(
        authToken: _tokenController.text,
        authTokenSecret: _tokenSecretController.text);
    final FirebaseUser user =
        (await _auth.signInWithCredential(credential)).user;
    assert(user.email != null);
    assert(user.displayName != null);
    assert(!user.isAnonymous);
    assert(await user.getIdToken() != null);

    final FirebaseUser currentUser = await _auth.currentUser();
    assert(user.uid == currentUser.uid);
    setState(() {
      if (user != null) {
        _message = 'Successfully signed in with Twitter. ${user.uid}';
      } else {
        _message = 'Failed to sign in with Twitter. ';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(16),
          alignment: Alignment.center,
          child: const Text(
              'Test other providers authentication. (We do not provide an API to obtain the token for below providers. Please use a third party service to obtain token for below providers.)'),
        ),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 16.0),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Radio<int>(
                value: 0,
                groupValue: _selection,
                onChanged: _handleRadioButtonSelected,
              ),
              const Text(
                'Github',
                style: TextStyle(fontSize: 16.0),
              ),
              Radio<int>(
                value: 1,
                groupValue: _selection,
                onChanged: _handleRadioButtonSelected,
              ),
              const Text(
                'Facebook',
                style: TextStyle(
                  fontSize: 16.0,
                ),
              ),
              Radio<int>(
                value: 2,
                groupValue: _selection,
                onChanged: _handleRadioButtonSelected,
              ),
              const Text(
                'Twitter',
                style: TextStyle(fontSize: 16.0),
              ),
            ],
          ),
        ),
        TextField(
          controller: _tokenController,
          decoration:
              const InputDecoration(labelText: 'Enter provider\'s token'),
        ),
        Container(
          child: _showAuthSecretTextField
              ? TextField(
                  controller: _tokenSecretController,
                  decoration: const InputDecoration(
                      labelText: 'Enter provider\'s authTokenSecret'),
                )
              : null,
        ),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 16.0),
          alignment: Alignment.center,
          child: RaisedButton(
            onPressed: () async {
              _signInWithOtherProvider();
            },
            child: const Text('Sign in'),
          ),
        ),
        Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            _message,
            style: TextStyle(color: Colors.red),
          ),
        )
      ],
    );
  }
}
