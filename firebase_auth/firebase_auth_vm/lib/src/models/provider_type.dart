// File created by
// Lung Razvan <long1eu>
// on 05/12/2019

part of firebase_auth_vm;

abstract class ProviderType {
  ProviderType._();

  static const String password = 'password';
  static const String phone = 'phone';
  static const String facebook = 'facebook.com';
  static const String gameCenter = 'gc.apple.com';
  static const String github = 'github.com';
  static const String google = 'google.com';
  static const String twitter = 'twitter.com';
  static const String apple = 'apple.com';
}

abstract class ProviderMethod {
  ProviderMethod._();

  static const String password = 'password';
  static const String emailLink = 'emailLink';
  static const String phone = 'phone';
  static const String facebook = 'facebook.com';
  static const String gameCenter = 'gc.apple.com';
  static const String github = 'github.com';
  static const String google = 'google.com';
  static const String twitter = 'twitter.com';
  static const String apple = 'apple.com';
  static const String oauth = 'oauth';
}
