// Listing: folders are prefixes, one page with list(), every page with
// listPages(), everything with listAll().

import 'dart:typed_data';

import 'package:firebase_storage_dart/firebase_storage_dart.dart';

import 'common.dart';

Future<void> main() async {
  final FirebaseStorage storage = emulatorStorage();
  final Reference root = storage.ref(freshFolder('listing'));
  for (final String name in <String>[
    'a.txt',
    'b.txt',
    'c.txt',
    'd.txt',
    'sub/e.txt',
  ]) {
    await root.child(name).putBytes(Uint8List(1));
  }

  // One level: objects in items, folders in prefixes.
  final ListResult first = await root.list(maxResults: 2);
  print('page 1: ${_names(first.items)}, prefixes ${_names(first.prefixes)}');
  print('nextPageToken: ${first.nextPageToken}');

  final ListResult second = await root.list(
    maxResults: 2,
    pageToken: first.nextPageToken,
  );
  print('page 2: ${_names(second.items)}');

  // listPages follows nextPageToken as the stream is read.
  await for (final ListResult page in root.listPages(pageSize: 3)) {
    print('listPages: ${_names(page.items)}');
  }

  // listAll reads every page of one level. It does not go into sub/.
  final ListResult all = await root.listAll();
  print('listAll: ${_names(all.items)}, prefixes ${_names(all.prefixes)}');
  print('sub/: ${_names((await root.child('sub').listAll()).items)}');

  for (final Reference item in all.items) {
    await item.delete();
  }
  await root.child('sub/e.txt').delete();
  storage.close();
}

List<String> _names(List<Reference> references) => <String>[
  for (final Reference reference in references) reference.name,
];
