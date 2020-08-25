///
//  Generated code. Do not modify.
//  source: firebase/firestore/proto/mutation.proto
//
// @dart = 2.3
// ignore_for_file: camel_case_types,non_constant_identifier_names,library_prefixes,unused_import,unused_shown_name,return_of_invalid_type

const MutationQueue$json = const {
  '1': 'MutationQueue',
  '2': const [
    const {'1': 'last_acknowledged_batch_id', '3': 1, '4': 1, '5': 5, '10': 'lastAcknowledgedBatchId'},
    const {'1': 'last_stream_token', '3': 2, '4': 1, '5': 12, '10': 'lastStreamToken'},
  ],
};

const WriteBatch$json = const {
  '1': 'WriteBatch',
  '2': const [
    const {'1': 'batch_id', '3': 1, '4': 1, '5': 5, '10': 'batchId'},
    const {'1': 'writes', '3': 2, '4': 3, '5': 11, '6': '.google.firestore.v1.Write', '10': 'writes'},
    const {'1': 'local_write_time', '3': 3, '4': 1, '5': 11, '6': '.google.protobuf.Timestamp', '10': 'localWriteTime'},
    const {'1': 'base_writes', '3': 4, '4': 3, '5': 11, '6': '.google.firestore.v1.Write', '10': 'baseWrites'},
  ],
};

