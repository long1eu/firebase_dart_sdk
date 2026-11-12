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
}
