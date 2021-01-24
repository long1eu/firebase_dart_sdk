///
//  Generated code. Do not modify.
//  source: firebase/firestore/proto/bundle.proto
//
// @dart = 2.7
// ignore_for_file: annotate_overrides,camel_case_types,unnecessary_const,non_constant_identifier_names,library_prefixes,unused_import,unused_shown_name,return_of_invalid_type,unnecessary_this,prefer_final_fields

const BundledQuery$json = const {
  '1': 'BundledQuery',
  '2': const [
    const {'1': 'parent', '3': 1, '4': 1, '5': 9, '10': 'parent'},
    const {'1': 'structured_query', '3': 2, '4': 1, '5': 11, '6': '.google.firestore.v1.StructuredQuery', '9': 0, '10': 'structuredQuery'},
    const {'1': 'limit_type', '3': 3, '4': 1, '5': 14, '6': '.firestore.BundledQuery.LimitType', '10': 'limitType'},
  ],
  '4': const [BundledQuery_LimitType$json],
  '8': const [
    const {'1': 'query_type'},
  ],
};

const BundledQuery_LimitType$json = const {
  '1': 'LimitType',
  '2': const [
    const {'1': 'FIRST', '2': 0},
    const {'1': 'LAST', '2': 1},
  ],
};

const NamedQuery$json = const {
  '1': 'NamedQuery',
  '2': const [
    const {'1': 'name', '3': 1, '4': 1, '5': 9, '10': 'name'},
    const {'1': 'bundled_query', '3': 2, '4': 1, '5': 11, '6': '.firestore.BundledQuery', '10': 'bundledQuery'},
    const {'1': 'read_time', '3': 3, '4': 1, '5': 11, '6': '.google.protobuf.Timestamp', '10': 'readTime'},
  ],
};

const BundledDocumentMetadata$json = const {
  '1': 'BundledDocumentMetadata',
  '2': const [
    const {'1': 'name', '3': 1, '4': 1, '5': 9, '10': 'name'},
    const {'1': 'read_time', '3': 2, '4': 1, '5': 11, '6': '.google.protobuf.Timestamp', '10': 'readTime'},
    const {'1': 'exists', '3': 3, '4': 1, '5': 8, '10': 'exists'},
    const {'1': 'queries', '3': 4, '4': 3, '5': 9, '10': 'queries'},
  ],
};

const BundleMetadata$json = const {
  '1': 'BundleMetadata',
  '2': const [
    const {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    const {'1': 'create_time', '3': 2, '4': 1, '5': 11, '6': '.google.protobuf.Timestamp', '10': 'createTime'},
    const {'1': 'version', '3': 3, '4': 1, '5': 13, '10': 'version'},
    const {'1': 'total_documents', '3': 4, '4': 1, '5': 13, '10': 'totalDocuments'},
    const {'1': 'total_bytes', '3': 5, '4': 1, '5': 4, '10': 'totalBytes'},
  ],
};

const BundleElement$json = const {
  '1': 'BundleElement',
  '2': const [
    const {'1': 'metadata', '3': 1, '4': 1, '5': 11, '6': '.firestore.BundleMetadata', '9': 0, '10': 'metadata'},
    const {'1': 'named_query', '3': 2, '4': 1, '5': 11, '6': '.firestore.NamedQuery', '9': 0, '10': 'namedQuery'},
    const {'1': 'document_metadata', '3': 3, '4': 1, '5': 11, '6': '.firestore.BundledDocumentMetadata', '9': 0, '10': 'documentMetadata'},
    const {'1': 'document', '3': 4, '4': 1, '5': 11, '6': '.google.firestore.v1.Document', '9': 0, '10': 'document'},
  ],
  '8': const [
    const {'1': 'element_type'},
  ],
};

