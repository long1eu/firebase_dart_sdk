import 'package:cloud_firestore_dart/src/firebase/firestore/auth/empty_credentials_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/channel_options_provider.dart';
import 'package:grpc/grpc.dart';
import 'package:test/test.dart';

void main() {
  test('adds the routing headers to every request', () async {
    final ChannelOptionsProvider provider = ChannelOptionsProvider(
      databaseId: DatabaseId.forDatabase('my-project', 'my-db'),
      credentialsProvider: EmptyCredentialsProvider(),
    );

    final Map<String, String> metadata = <String, String>{};
    for (MetadataProvider metadataProvider
        in provider.callOptions.metadataProviders) {
      await metadataProvider(metadata, 'uri');
    }

    const String prefix = 'projects/my-project/databases/my-db';
    // Kept until the emulators understand x-goog-request-params.
    expect(metadata['google-cloud-resource-prefix'], prefix);
    expect(metadata['x-goog-request-params'], prefix);
    expect(metadata['x-goog-api-client'], isNotEmpty);
  });

  // Review L12: the header used the whole `Platform.version`, which has spaces,
  // parentheses and quotes ("3.12.2 (stable) (...) on "macos_arm64"").
  test('x-goog-api-client is space-separated name/version tokens', () async {
    final ChannelOptionsProvider provider = ChannelOptionsProvider(
      databaseId: DatabaseId.forDatabase('my-project', 'my-db'),
      credentialsProvider: EmptyCredentialsProvider(),
    );

    final Map<String, String> metadata = <String, String>{};
    for (MetadataProvider metadataProvider
        in provider.callOptions.metadataProviders) {
      await metadataProvider(metadata, 'uri');
    }

    expect(
      metadata['x-goog-api-client'],
      matches(
        RegExp(
          r'^gl-dart/[0-9A-Za-z.+\-]+ fire/[0-9A-Za-z.+\-]+ grpc/[0-9A-Za-z.+\-]+$',
        ),
      ),
    );
  });
}
