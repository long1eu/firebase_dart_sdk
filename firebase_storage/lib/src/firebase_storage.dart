// File created by
// Lung Razvan <long1eu>
// on 22/10/2018

import 'package:firebase_common/firebase_common.dart';
import 'package:firebase_storage/src/internal/util.dart';
import 'package:firebase_storage/src/storage_reference.dart';
import 'package:meta/meta.dart';

/// [FirebaseStorage] is a service that supports uploading and downloading large
/// objects to Google Cloud Storage. Pass a custom instance of [FirebaseApp] to
/// [FirebaseStorage.getInstance] which will initialize it with a storage
/// location (bucket) specified via [FirebaseOptions.storageBucket].
///
/// Otherwise, if you call [FirebaseStorage.getReference] without a
/// FirebaseApp, the FirebaseStorage instance will initialize with the default
/// [FirebaseApp] obtainable from [FirebaseApp.instance]. The storage location
/// in this case will come the json configuration file downloaded from the web.
@publicApi
class FirebaseStorage {
  FirebaseStorage._(this.bucketName, this.app)
      : isNetworkConnected = app.isNetworkConnected;

  /// Returns the [FirebaseStorage], initialized with a custom [FirebaseApp]
  /// and/or a custom Storage Bucket.
  ///
  /// [url] is the gs:// url to your Firebase Storage Bucket.
  @publicApi
  factory FirebaseStorage.getInstance({FirebaseApp app, String url}) {
    if (app == null && url == null) {
      return instance;
    } else if (app == null) {
      final FirebaseApp app = FirebaseApp.instance;
      Preconditions.checkArgument(
          app != null, 'You must call FirebaseApp() first.');
      return FirebaseStorage.getInstance(app: app, url: url);
    } else if (url == null) {
      Preconditions.checkArgument(
          app != null, 'FirebaseApp should not be null.');

      final String storageBucket = app.options.storageBucket;
      if (storageBucket == null) {
        return FirebaseStorage._instanceImpl(app, null);
      } else {
        try {
          return FirebaseStorage._instanceImpl(
              app, normalize(app, 'gs://${app.options.storageBucket}'));
        } on FormatException catch (_) {
          Log.e(_tag, 'Unable to parse bucket: $storageBucket');
          throw ArgumentError(_kStorageUriParseException);
        }
      }
    } else {
      Preconditions.checkArgument(
          app != null, 'FirebaseApp should not be null.');

      if (!url.toLowerCase().startsWith('gs://')) {
        throw ArgumentError(
            'Please use a gs:// URL for your Firebase Storage bucket.');
      }

      try {
        return FirebaseStorage._instanceImpl(app, normalize(app, url));
      } on FormatException catch (_) {
        Log.e(_tag, 'Unable to parse url: $url');
        throw ArgumentError(_kStorageUriParseException);
      }
    }
  }

  factory FirebaseStorage._instanceImpl(FirebaseApp app, Uri url) {
    final String bucketName = url != null ? url.host : null;

    if (url != null && url.path != null && url.path.isNotEmpty) {
      throw ArgumentError(_kStorageBucketWithPathException);
    }

    Map<String, FirebaseStorage> storageBuckets = _storageMap[app.name];
    if (storageBuckets == null) {
      storageBuckets = <String, FirebaseStorage>{};
      _storageMap[app.name] = storageBuckets;
    }
    FirebaseStorage storage = storageBuckets[bucketName];
    if (storage == null) {
      storage = FirebaseStorage._(bucketName, app);
      storageBuckets[bucketName] = storage;
    }
    return storage;
  }

  static FirebaseStorage _defaultInstance;

  /// Returns the [FirebaseStorage], initialized with the default [FirebaseApp].
  @publicApi
  static FirebaseStorage get instance => _defaultInstance ??=
      FirebaseStorage.getInstance(app: FirebaseApp.instance);

  static const String _tag = 'FirebaseStorage';
  static final Map<String /*App name*/,
          Map<String /*StorageBucket*/, FirebaseStorage>>
      _storageMap = <String, Map<String, FirebaseStorage>>{};

  static const String _kStorageUriParseException =
      'The storage Uri could not be parsed.';

  static const String _kStorageBucketWithPathException =
      'The storage Uri cannot contain a path element.';

  final IsNetworkConnected isNetworkConnected;

  @publicApi
  final FirebaseApp app;

  @publicApi
  final String bucketName;

  /// Returns the maximum time to retry an upload if a failure occurs.
  Duration maxUploadRetry = const Duration(minutes: 10);

  /// The maximum time to retry a download if a failure occurs.
  Duration maxDownloadRetry = const Duration(minutes: 10);

  /// Returns the maximum time to retry operations other than upload and
  /// download if a failure occurs.
  Duration maxOperationRetry = const Duration(minutes: 2);

  @visibleForTesting
  static void clearInstancesForTest() => _storageMap.clear();

  /// Creates a new [StorageReference] initialized at the root Firebase Storage
  /// location.
  @publicApi
  // TODO:{22/10/2018 11:38}-long1eu: cache this, there is no need to recalculate it
  StorageReference get reference {
    if (bucketName == null || bucketName.isEmpty) {
      throw StateError('FirebaseApp was not initialized with a bucket name.');
    }
    final Uri uri = Uri.parse('gs://$bucketName/');
    return _getReference(uri);
  }

  /// Creates a [StorageReference] given a gs:// or https:// URL pointing to a
  /// Firebase Storage location.
  ///
  /// [fullUrl] is a gs:// or http[s]:// URL used to initialize the reference.
  /// For example, you can pass in a download URL retrieved from
  /// [StorageReference.downloadUrl] or the uri retrieved from
  /// [StorageReference.toString]. An error is thrown if [fullUrl] is not
  /// associated with the [FirebaseApp] used to initialize this
  /// [FirebaseStorage].
  @publicApi
  StorageReference getReferenceFromUrl(String fullUrl) {
    Preconditions.checkArgument(fullUrl != null && fullUrl.isNotEmpty,
        'location must not be null or empty');
    final String lowerCaseLocation = fullUrl.toLowerCase();
    if (lowerCaseLocation.startsWith('gs://') ||
        lowerCaseLocation.startsWith('https://') ||
        lowerCaseLocation.startsWith('http://')) {
      try {
        final Uri uri = normalize(app, fullUrl);
        if (uri == null) {
          throw ArgumentError(_kStorageUriParseException);
        }
        return _getReference(uri);
      } on FormatException catch (_) {
        Log.e(_tag, 'Unable to parse location: $fullUrl');

        throw ArgumentError(_kStorageUriParseException);
      }
    } else {
      throw ArgumentError(_kStorageUriParseException);
    }
  }

  /// Creates a new [StorageReference] initialized with a child Firebase Storage
  /// location.
  ///
  /// [location] is a relative path from the root to initialize the reference
  /// with, for instance 'path/to/object'
  ///
  /// Returns an instance of [StorageReference] at the given child path.
  @publicApi
  StorageReference getReference(String location) {
    Preconditions.checkArgument(location != null && location.isNotEmpty,
        'location must not be null or empty');
    final String lowerCaseLocation = location.toLowerCase();
    if (lowerCaseLocation.startsWith('gs://') ||
        lowerCaseLocation.startsWith('https://') ||
        lowerCaseLocation.startsWith('http://')) {
      throw ArgumentError('location should not be a full URL.');
    }
    return reference.child(location);
  }

  StorageReference _getReference(Uri uri) {
    // ensure that the authority represents the correct bucket.
    Preconditions.checkNotNull(uri, 'uri must not be null');

    Preconditions.checkArgument(
        bucketName == null || bucketName.isEmpty || uri.authority == bucketName,
        'The supplied bucketname does not match the storage bucket of the '
        'current instance.');

    return StorageReference(uri, this);
  }
}
