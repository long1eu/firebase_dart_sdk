///
//  Generated code. Do not modify.
//  source: google/firebase/firestore/proto/maybe_document.proto
///
// ignore_for_file: camel_case_types,non_constant_identifier_names,library_prefixes,unused_import,unused_shown_name

const NoDocument$json = const {
  '1': 'NoDocument',
  '2': const [
    const {'1': 'name', '3': 1, '4': 1, '5': 9, '10': 'name'},
    const {'1': 'read_time', '3': 2, '4': 1, '5': 11, '6': '.google.protobuf.Timestamp', '10': 'readTime'},
  ],
};

const UnknownDocument$json = const {
  '1': 'UnknownDocument',
  '2': const [
    const {'1': 'name', '3': 1, '4': 1, '5': 9, '10': 'name'},
    const {'1': 'version', '3': 2, '4': 1, '5': 11, '6': '.google.protobuf.Timestamp', '10': 'version'},
  ],
};

const MaybeDocument$json = const {
  '1': 'MaybeDocument',
  '2': const [
    const {'1': 'no_document', '3': 1, '4': 1, '5': 11, '6': '.firestore.client.NoDocument', '9': 0, '10': 'noDocument'},
    const {'1': 'document', '3': 2, '4': 1, '5': 11, '6': '.google.firestore.v1beta1.Document', '9': 0, '10': 'document'},
    const {'1': 'unknown_document', '3': 3, '4': 1, '5': 11, '6': '.firestore.client.UnknownDocument', '9': 0, '10': 'unknownDocument'},
    const {'1': 'has_committed_mutations', '3': 4, '4': 1, '5': 8, '10': 'hasCommittedMutations'},
  ],
  '8': const [
    const {'1': 'document_type'},
  ],
};

