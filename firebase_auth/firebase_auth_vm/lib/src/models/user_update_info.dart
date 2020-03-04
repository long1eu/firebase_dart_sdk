// File created by
// Lung Razvan <long1eu>
// on 11/12/2019

part of firebase_auth_vm;

/// Represents user profile data that can be updated by [updateProfile]
///
/// The purpose of having separate class with a map is to give possibility to check if value was set to null or not
/// provided
class UserUpdateInfo {
  /// Container of data that will be send in update request
  final Map<String, String> _updateData = <String, String>{};

  bool get hasDisplayName => _updateData.containsKey('displayName');

  set displayName(String displayName) => _updateData['displayName'] = displayName;

  String get displayName => _updateData['displayName'];

  bool get hasPhotoUrl => _updateData.containsKey('photoUrl');

  set photoUrl(String photoUri) => _updateData['photoUrl'] = photoUri;

  String get photoUrl => _updateData['photoUrl'];
}
