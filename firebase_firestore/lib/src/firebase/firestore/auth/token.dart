// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'credentials_provider.dart';
import 'user.dart';

/// The current User and the authentication token provided by the underlying authentication
/// mechanism. This is the result of calling [CredentialsProvider.token].
///
/// The TypeScript client supports 1st party Oauth tokens (for the Firebase Console to auth as the
/// developer) and OAuth2 tokens for the node.js sdk to auth with a service account. We don't have
/// plans to support either case on mobile so there's no TokenType here.
class Token {
  const Token(this.value, this.user);

  /// Returns the actual raw token.
  final String value;

  /// Returns the user with which the token is associated (used for persisting user state on disk,
  /// etc.).
  final User user;
}
