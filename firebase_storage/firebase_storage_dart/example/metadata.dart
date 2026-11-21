// Metadata: read it, update it, and set or remove custom keys.

import 'dart:typed_data';

import 'package:firebase_storage_dart/firebase_storage_dart.dart';

import 'common.dart';

Future<void> main() async {
  final FirebaseStorage storage = emulatorStorage();
  final Reference file = storage
      .ref(freshFolder('metadata'))
      .child('report.csv');
  await file.putBytes(
    Uint8List.fromList('a,b\n1,2\n'.codeUnits),
    metadata: const SettableMetadata(
      contentType: 'text/csv',
      customMetadata: <String, String>{'team': 'finance', 'draft': 'yes'},
    ),
  );

  final FullMetadata before = await file.metadata();
  print('${before.name}: ${before.size} bytes, ${before.contentType}');
  print('custom: ${before.customMetadata}');
  print('created ${before.timeCreated}, md5 ${before.md5Hash}');

  // Fields that are null are left as they are. A custom key that is listed
  // is set; the keys that are not listed stay.
  final FullMetadata changed = await file.updateMetadata(
    const SettableMetadata(
      cacheControl: 'max-age=60',
      customMetadata: <String, String>{'team': 'accounting'},
    ),
  );
  print(
    'cacheControl ${changed.cacheControl}, custom ${changed.customMetadata}',
  );

  // MetadataField names what to remove.
  final FullMetadata cleared = await file.updateMetadata(
    const SettableMetadata(
      delete: <MetadataField>{
        MetadataField.cacheControl,
        MetadataField.customMetadata,
      },
    ),
  );
  print(
    'cacheControl ${cleared.cacheControl}, custom ${cleared.customMetadata}',
  );

  await file.delete();
  storage.close();
}
