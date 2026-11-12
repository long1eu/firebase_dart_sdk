//
//  Generated code. Do not modify.
//  source: google/firestore/v1/query.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use structuredQueryDescriptor instead')
const StructuredQuery$json = {
  '1': 'StructuredQuery',
  '2': [
    {'1': 'select', '3': 1, '4': 1, '5': 11, '6': '.google.firestore.v1.StructuredQuery.Projection', '10': 'select'},
    {'1': 'from', '3': 2, '4': 3, '5': 11, '6': '.google.firestore.v1.StructuredQuery.CollectionSelector', '10': 'from'},
    {'1': 'where', '3': 3, '4': 1, '5': 11, '6': '.google.firestore.v1.StructuredQuery.Filter', '10': 'where'},
    {'1': 'order_by', '3': 4, '4': 3, '5': 11, '6': '.google.firestore.v1.StructuredQuery.Order', '10': 'orderBy'},
    {'1': 'start_at', '3': 7, '4': 1, '5': 11, '6': '.google.firestore.v1.Cursor', '10': 'startAt'},
    {'1': 'end_at', '3': 8, '4': 1, '5': 11, '6': '.google.firestore.v1.Cursor', '10': 'endAt'},
    {'1': 'offset', '3': 6, '4': 1, '5': 5, '10': 'offset'},
    {'1': 'limit', '3': 5, '4': 1, '5': 11, '6': '.google.protobuf.Int32Value', '10': 'limit'},
    {'1': 'find_nearest', '3': 9, '4': 1, '5': 11, '6': '.google.firestore.v1.StructuredQuery.FindNearest', '8': {}, '10': 'findNearest'},
  ],
  '3': [StructuredQuery_CollectionSelector$json, StructuredQuery_Filter$json, StructuredQuery_CompositeFilter$json, StructuredQuery_FieldFilter$json, StructuredQuery_UnaryFilter$json, StructuredQuery_Order$json, StructuredQuery_FieldReference$json, StructuredQuery_Projection$json, StructuredQuery_FindNearest$json],
  '4': [StructuredQuery_Direction$json],
};

@$core.Deprecated('Use structuredQueryDescriptor instead')
const StructuredQuery_CollectionSelector$json = {
  '1': 'CollectionSelector',
  '2': [
    {'1': 'collection_id', '3': 2, '4': 1, '5': 9, '10': 'collectionId'},
    {'1': 'all_descendants', '3': 3, '4': 1, '5': 8, '10': 'allDescendants'},
  ],
};

@$core.Deprecated('Use structuredQueryDescriptor instead')
const StructuredQuery_Filter$json = {
  '1': 'Filter',
  '2': [
    {'1': 'composite_filter', '3': 1, '4': 1, '5': 11, '6': '.google.firestore.v1.StructuredQuery.CompositeFilter', '9': 0, '10': 'compositeFilter'},
    {'1': 'field_filter', '3': 2, '4': 1, '5': 11, '6': '.google.firestore.v1.StructuredQuery.FieldFilter', '9': 0, '10': 'fieldFilter'},
    {'1': 'unary_filter', '3': 3, '4': 1, '5': 11, '6': '.google.firestore.v1.StructuredQuery.UnaryFilter', '9': 0, '10': 'unaryFilter'},
  ],
  '8': [
    {'1': 'filter_type'},
  ],
};

@$core.Deprecated('Use structuredQueryDescriptor instead')
const StructuredQuery_CompositeFilter$json = {
  '1': 'CompositeFilter',
  '2': [
    {'1': 'op', '3': 1, '4': 1, '5': 14, '6': '.google.firestore.v1.StructuredQuery.CompositeFilter.Operator', '10': 'op'},
    {'1': 'filters', '3': 2, '4': 3, '5': 11, '6': '.google.firestore.v1.StructuredQuery.Filter', '10': 'filters'},
  ],
  '4': [StructuredQuery_CompositeFilter_Operator$json],
};

@$core.Deprecated('Use structuredQueryDescriptor instead')
const StructuredQuery_CompositeFilter_Operator$json = {
  '1': 'Operator',
  '2': [
    {'1': 'OPERATOR_UNSPECIFIED', '2': 0},
    {'1': 'AND', '2': 1},
    {'1': 'OR', '2': 2},
  ],
};

@$core.Deprecated('Use structuredQueryDescriptor instead')
const StructuredQuery_FieldFilter$json = {
  '1': 'FieldFilter',
  '2': [
    {'1': 'field', '3': 1, '4': 1, '5': 11, '6': '.google.firestore.v1.StructuredQuery.FieldReference', '10': 'field'},
    {'1': 'op', '3': 2, '4': 1, '5': 14, '6': '.google.firestore.v1.StructuredQuery.FieldFilter.Operator', '10': 'op'},
    {'1': 'value', '3': 3, '4': 1, '5': 11, '6': '.google.firestore.v1.Value', '10': 'value'},
  ],
  '4': [StructuredQuery_FieldFilter_Operator$json],
};

@$core.Deprecated('Use structuredQueryDescriptor instead')
const StructuredQuery_FieldFilter_Operator$json = {
  '1': 'Operator',
  '2': [
    {'1': 'OPERATOR_UNSPECIFIED', '2': 0},
    {'1': 'LESS_THAN', '2': 1},
    {'1': 'LESS_THAN_OR_EQUAL', '2': 2},
    {'1': 'GREATER_THAN', '2': 3},
    {'1': 'GREATER_THAN_OR_EQUAL', '2': 4},
    {'1': 'EQUAL', '2': 5},
    {'1': 'NOT_EQUAL', '2': 6},
    {'1': 'ARRAY_CONTAINS', '2': 7},
    {'1': 'IN', '2': 8},
    {'1': 'ARRAY_CONTAINS_ANY', '2': 9},
    {'1': 'NOT_IN', '2': 10},
  ],
};

@$core.Deprecated('Use structuredQueryDescriptor instead')
const StructuredQuery_UnaryFilter$json = {
  '1': 'UnaryFilter',
  '2': [
    {'1': 'op', '3': 1, '4': 1, '5': 14, '6': '.google.firestore.v1.StructuredQuery.UnaryFilter.Operator', '10': 'op'},
    {'1': 'field', '3': 2, '4': 1, '5': 11, '6': '.google.firestore.v1.StructuredQuery.FieldReference', '9': 0, '10': 'field'},
  ],
  '4': [StructuredQuery_UnaryFilter_Operator$json],
  '8': [
    {'1': 'operand_type'},
  ],
};

@$core.Deprecated('Use structuredQueryDescriptor instead')
const StructuredQuery_UnaryFilter_Operator$json = {
  '1': 'Operator',
  '2': [
    {'1': 'OPERATOR_UNSPECIFIED', '2': 0},
    {'1': 'IS_NAN', '2': 2},
    {'1': 'IS_NULL', '2': 3},
    {'1': 'IS_NOT_NAN', '2': 4},
    {'1': 'IS_NOT_NULL', '2': 5},
  ],
};

@$core.Deprecated('Use structuredQueryDescriptor instead')
const StructuredQuery_Order$json = {
  '1': 'Order',
  '2': [
    {'1': 'field', '3': 1, '4': 1, '5': 11, '6': '.google.firestore.v1.StructuredQuery.FieldReference', '10': 'field'},
    {'1': 'direction', '3': 2, '4': 1, '5': 14, '6': '.google.firestore.v1.StructuredQuery.Direction', '10': 'direction'},
  ],
};

@$core.Deprecated('Use structuredQueryDescriptor instead')
const StructuredQuery_FieldReference$json = {
  '1': 'FieldReference',
  '2': [
    {'1': 'field_path', '3': 2, '4': 1, '5': 9, '10': 'fieldPath'},
  ],
};

@$core.Deprecated('Use structuredQueryDescriptor instead')
const StructuredQuery_Projection$json = {
  '1': 'Projection',
  '2': [
    {'1': 'fields', '3': 2, '4': 3, '5': 11, '6': '.google.firestore.v1.StructuredQuery.FieldReference', '10': 'fields'},
  ],
};

@$core.Deprecated('Use structuredQueryDescriptor instead')
const StructuredQuery_FindNearest$json = {
  '1': 'FindNearest',
  '2': [
    {'1': 'vector_field', '3': 1, '4': 1, '5': 11, '6': '.google.firestore.v1.StructuredQuery.FieldReference', '8': {}, '10': 'vectorField'},
    {'1': 'query_vector', '3': 2, '4': 1, '5': 11, '6': '.google.firestore.v1.Value', '8': {}, '10': 'queryVector'},
    {'1': 'distance_measure', '3': 3, '4': 1, '5': 14, '6': '.google.firestore.v1.StructuredQuery.FindNearest.DistanceMeasure', '8': {}, '10': 'distanceMeasure'},
    {'1': 'limit', '3': 4, '4': 1, '5': 11, '6': '.google.protobuf.Int32Value', '8': {}, '10': 'limit'},
    {'1': 'distance_result_field', '3': 5, '4': 1, '5': 9, '8': {}, '10': 'distanceResultField'},
    {'1': 'distance_threshold', '3': 6, '4': 1, '5': 11, '6': '.google.protobuf.DoubleValue', '8': {}, '10': 'distanceThreshold'},
  ],
  '4': [StructuredQuery_FindNearest_DistanceMeasure$json],
};

@$core.Deprecated('Use structuredQueryDescriptor instead')
const StructuredQuery_FindNearest_DistanceMeasure$json = {
  '1': 'DistanceMeasure',
  '2': [
    {'1': 'DISTANCE_MEASURE_UNSPECIFIED', '2': 0},
    {'1': 'EUCLIDEAN', '2': 1},
    {'1': 'COSINE', '2': 2},
    {'1': 'DOT_PRODUCT', '2': 3},
  ],
};

@$core.Deprecated('Use structuredQueryDescriptor instead')
const StructuredQuery_Direction$json = {
  '1': 'Direction',
  '2': [
    {'1': 'DIRECTION_UNSPECIFIED', '2': 0},
    {'1': 'ASCENDING', '2': 1},
    {'1': 'DESCENDING', '2': 2},
  ],
};

/// Descriptor for `StructuredQuery`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List structuredQueryDescriptor = $convert.base64Decode(
    'Cg9TdHJ1Y3R1cmVkUXVlcnkSRwoGc2VsZWN0GAEgASgLMi8uZ29vZ2xlLmZpcmVzdG9yZS52MS'
    '5TdHJ1Y3R1cmVkUXVlcnkuUHJvamVjdGlvblIGc2VsZWN0EksKBGZyb20YAiADKAsyNy5nb29n'
    'bGUuZmlyZXN0b3JlLnYxLlN0cnVjdHVyZWRRdWVyeS5Db2xsZWN0aW9uU2VsZWN0b3JSBGZyb2'
    '0SQQoFd2hlcmUYAyABKAsyKy5nb29nbGUuZmlyZXN0b3JlLnYxLlN0cnVjdHVyZWRRdWVyeS5G'
    'aWx0ZXJSBXdoZXJlEkUKCG9yZGVyX2J5GAQgAygLMiouZ29vZ2xlLmZpcmVzdG9yZS52MS5TdH'
    'J1Y3R1cmVkUXVlcnkuT3JkZXJSB29yZGVyQnkSNgoIc3RhcnRfYXQYByABKAsyGy5nb29nbGUu'
    'ZmlyZXN0b3JlLnYxLkN1cnNvclIHc3RhcnRBdBIyCgZlbmRfYXQYCCABKAsyGy5nb29nbGUuZm'
    'lyZXN0b3JlLnYxLkN1cnNvclIFZW5kQXQSFgoGb2Zmc2V0GAYgASgFUgZvZmZzZXQSMQoFbGlt'
    'aXQYBSABKAsyGy5nb29nbGUucHJvdG9idWYuSW50MzJWYWx1ZVIFbGltaXQSWQoMZmluZF9uZW'
    'FyZXN0GAkgASgLMjAuZ29vZ2xlLmZpcmVzdG9yZS52MS5TdHJ1Y3R1cmVkUXVlcnkuRmluZE5l'
    'YXJlc3RCBOJBAQFSC2ZpbmROZWFyZXN0GmIKEkNvbGxlY3Rpb25TZWxlY3RvchIjCg1jb2xsZW'
    'N0aW9uX2lkGAIgASgJUgxjb2xsZWN0aW9uSWQSJwoPYWxsX2Rlc2NlbmRhbnRzGAMgASgIUg5h'
    'bGxEZXNjZW5kYW50cxqoAgoGRmlsdGVyEmEKEGNvbXBvc2l0ZV9maWx0ZXIYASABKAsyNC5nb2'
    '9nbGUuZmlyZXN0b3JlLnYxLlN0cnVjdHVyZWRRdWVyeS5Db21wb3NpdGVGaWx0ZXJIAFIPY29t'
    'cG9zaXRlRmlsdGVyElUKDGZpZWxkX2ZpbHRlchgCIAEoCzIwLmdvb2dsZS5maXJlc3RvcmUudj'
    'EuU3RydWN0dXJlZFF1ZXJ5LkZpZWxkRmlsdGVySABSC2ZpZWxkRmlsdGVyElUKDHVuYXJ5X2Zp'
    'bHRlchgDIAEoCzIwLmdvb2dsZS5maXJlc3RvcmUudjEuU3RydWN0dXJlZFF1ZXJ5LlVuYXJ5Rm'
    'lsdGVySABSC3VuYXJ5RmlsdGVyQg0KC2ZpbHRlcl90eXBlGt4BCg9Db21wb3NpdGVGaWx0ZXIS'
    'TQoCb3AYASABKA4yPS5nb29nbGUuZmlyZXN0b3JlLnYxLlN0cnVjdHVyZWRRdWVyeS5Db21wb3'
    'NpdGVGaWx0ZXIuT3BlcmF0b3JSAm9wEkUKB2ZpbHRlcnMYAiADKAsyKy5nb29nbGUuZmlyZXN0'
    'b3JlLnYxLlN0cnVjdHVyZWRRdWVyeS5GaWx0ZXJSB2ZpbHRlcnMiNQoIT3BlcmF0b3ISGAoUT1'
    'BFUkFUT1JfVU5TUEVDSUZJRUQQABIHCgNBTkQQARIGCgJPUhACGqoDCgtGaWVsZEZpbHRlchJJ'
    'CgVmaWVsZBgBIAEoCzIzLmdvb2dsZS5maXJlc3RvcmUudjEuU3RydWN0dXJlZFF1ZXJ5LkZpZW'
    'xkUmVmZXJlbmNlUgVmaWVsZBJJCgJvcBgCIAEoDjI5Lmdvb2dsZS5maXJlc3RvcmUudjEuU3Ry'
    'dWN0dXJlZFF1ZXJ5LkZpZWxkRmlsdGVyLk9wZXJhdG9yUgJvcBIwCgV2YWx1ZRgDIAEoCzIaLm'
    'dvb2dsZS5maXJlc3RvcmUudjEuVmFsdWVSBXZhbHVlItIBCghPcGVyYXRvchIYChRPUEVSQVRP'
    'Ul9VTlNQRUNJRklFRBAAEg0KCUxFU1NfVEhBThABEhYKEkxFU1NfVEhBTl9PUl9FUVVBTBACEh'
    'AKDEdSRUFURVJfVEhBThADEhkKFUdSRUFURVJfVEhBTl9PUl9FUVVBTBAEEgkKBUVRVUFMEAUS'
    'DQoJTk9UX0VRVUFMEAYSEgoOQVJSQVlfQ09OVEFJTlMQBxIGCgJJThAIEhYKEkFSUkFZX0NPTl'
    'RBSU5TX0FOWRAJEgoKBk5PVF9JThAKGpUCCgtVbmFyeUZpbHRlchJJCgJvcBgBIAEoDjI5Lmdv'
    'b2dsZS5maXJlc3RvcmUudjEuU3RydWN0dXJlZFF1ZXJ5LlVuYXJ5RmlsdGVyLk9wZXJhdG9yUg'
    'JvcBJLCgVmaWVsZBgCIAEoCzIzLmdvb2dsZS5maXJlc3RvcmUudjEuU3RydWN0dXJlZFF1ZXJ5'
    'LkZpZWxkUmVmZXJlbmNlSABSBWZpZWxkIl4KCE9wZXJhdG9yEhgKFE9QRVJBVE9SX1VOU1BFQ0'
    'lGSUVEEAASCgoGSVNfTkFOEAISCwoHSVNfTlVMTBADEg4KCklTX05PVF9OQU4QBBIPCgtJU19O'
    'T1RfTlVMTBAFQg4KDG9wZXJhbmRfdHlwZRqgAQoFT3JkZXISSQoFZmllbGQYASABKAsyMy5nb2'
    '9nbGUuZmlyZXN0b3JlLnYxLlN0cnVjdHVyZWRRdWVyeS5GaWVsZFJlZmVyZW5jZVIFZmllbGQS'
    'TAoJZGlyZWN0aW9uGAIgASgOMi4uZ29vZ2xlLmZpcmVzdG9yZS52MS5TdHJ1Y3R1cmVkUXVlcn'
    'kuRGlyZWN0aW9uUglkaXJlY3Rpb24aLwoORmllbGRSZWZlcmVuY2USHQoKZmllbGRfcGF0aBgC'
    'IAEoCVIJZmllbGRQYXRoGlkKClByb2plY3Rpb24SSwoGZmllbGRzGAIgAygLMjMuZ29vZ2xlLm'
    'ZpcmVzdG9yZS52MS5TdHJ1Y3R1cmVkUXVlcnkuRmllbGRSZWZlcmVuY2VSBmZpZWxkcxrKBAoL'
    'RmluZE5lYXJlc3QSXAoMdmVjdG9yX2ZpZWxkGAEgASgLMjMuZ29vZ2xlLmZpcmVzdG9yZS52MS'
    '5TdHJ1Y3R1cmVkUXVlcnkuRmllbGRSZWZlcmVuY2VCBOJBAQJSC3ZlY3RvckZpZWxkEkMKDHF1'
    'ZXJ5X3ZlY3RvchgCIAEoCzIaLmdvb2dsZS5maXJlc3RvcmUudjEuVmFsdWVCBOJBAQJSC3F1ZX'
    'J5VmVjdG9yEnEKEGRpc3RhbmNlX21lYXN1cmUYAyABKA4yQC5nb29nbGUuZmlyZXN0b3JlLnYx'
    'LlN0cnVjdHVyZWRRdWVyeS5GaW5kTmVhcmVzdC5EaXN0YW5jZU1lYXN1cmVCBOJBAQJSD2Rpc3'
    'RhbmNlTWVhc3VyZRI3CgVsaW1pdBgEIAEoCzIbLmdvb2dsZS5wcm90b2J1Zi5JbnQzMlZhbHVl'
    'QgTiQQECUgVsaW1pdBI4ChVkaXN0YW5jZV9yZXN1bHRfZmllbGQYBSABKAlCBOJBAQFSE2Rpc3'
    'RhbmNlUmVzdWx0RmllbGQSUQoSZGlzdGFuY2VfdGhyZXNob2xkGAYgASgLMhwuZ29vZ2xlLnBy'
    'b3RvYnVmLkRvdWJsZVZhbHVlQgTiQQEBUhFkaXN0YW5jZVRocmVzaG9sZCJfCg9EaXN0YW5jZU'
    '1lYXN1cmUSIAocRElTVEFOQ0VfTUVBU1VSRV9VTlNQRUNJRklFRBAAEg0KCUVVQ0xJREVBThAB'
    'EgoKBkNPU0lORRACEg8KC0RPVF9QUk9EVUNUEAMiRQoJRGlyZWN0aW9uEhkKFURJUkVDVElPTl'
    '9VTlNQRUNJRklFRBAAEg0KCUFTQ0VORElORxABEg4KCkRFU0NFTkRJTkcQAg==');

@$core.Deprecated('Use structuredAggregationQueryDescriptor instead')
const StructuredAggregationQuery$json = {
  '1': 'StructuredAggregationQuery',
  '2': [
    {'1': 'structured_query', '3': 1, '4': 1, '5': 11, '6': '.google.firestore.v1.StructuredQuery', '9': 0, '10': 'structuredQuery'},
    {'1': 'aggregations', '3': 3, '4': 3, '5': 11, '6': '.google.firestore.v1.StructuredAggregationQuery.Aggregation', '8': {}, '10': 'aggregations'},
  ],
  '3': [StructuredAggregationQuery_Aggregation$json],
  '8': [
    {'1': 'query_type'},
  ],
};

@$core.Deprecated('Use structuredAggregationQueryDescriptor instead')
const StructuredAggregationQuery_Aggregation$json = {
  '1': 'Aggregation',
  '2': [
    {'1': 'count', '3': 1, '4': 1, '5': 11, '6': '.google.firestore.v1.StructuredAggregationQuery.Aggregation.Count', '9': 0, '10': 'count'},
    {'1': 'sum', '3': 2, '4': 1, '5': 11, '6': '.google.firestore.v1.StructuredAggregationQuery.Aggregation.Sum', '9': 0, '10': 'sum'},
    {'1': 'avg', '3': 3, '4': 1, '5': 11, '6': '.google.firestore.v1.StructuredAggregationQuery.Aggregation.Avg', '9': 0, '10': 'avg'},
    {'1': 'alias', '3': 7, '4': 1, '5': 9, '8': {}, '10': 'alias'},
  ],
  '3': [StructuredAggregationQuery_Aggregation_Count$json, StructuredAggregationQuery_Aggregation_Sum$json, StructuredAggregationQuery_Aggregation_Avg$json],
  '8': [
    {'1': 'operator'},
  ],
};

@$core.Deprecated('Use structuredAggregationQueryDescriptor instead')
const StructuredAggregationQuery_Aggregation_Count$json = {
  '1': 'Count',
  '2': [
    {'1': 'up_to', '3': 1, '4': 1, '5': 11, '6': '.google.protobuf.Int64Value', '8': {}, '10': 'upTo'},
  ],
};

@$core.Deprecated('Use structuredAggregationQueryDescriptor instead')
const StructuredAggregationQuery_Aggregation_Sum$json = {
  '1': 'Sum',
  '2': [
    {'1': 'field', '3': 1, '4': 1, '5': 11, '6': '.google.firestore.v1.StructuredQuery.FieldReference', '10': 'field'},
  ],
};

@$core.Deprecated('Use structuredAggregationQueryDescriptor instead')
const StructuredAggregationQuery_Aggregation_Avg$json = {
  '1': 'Avg',
  '2': [
    {'1': 'field', '3': 1, '4': 1, '5': 11, '6': '.google.firestore.v1.StructuredQuery.FieldReference', '10': 'field'},
  ],
};

/// Descriptor for `StructuredAggregationQuery`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List structuredAggregationQueryDescriptor = $convert.base64Decode(
    'ChpTdHJ1Y3R1cmVkQWdncmVnYXRpb25RdWVyeRJRChBzdHJ1Y3R1cmVkX3F1ZXJ5GAEgASgLMi'
    'QuZ29vZ2xlLmZpcmVzdG9yZS52MS5TdHJ1Y3R1cmVkUXVlcnlIAFIPc3RydWN0dXJlZFF1ZXJ5'
    'EmUKDGFnZ3JlZ2F0aW9ucxgDIAMoCzI7Lmdvb2dsZS5maXJlc3RvcmUudjEuU3RydWN0dXJlZE'
    'FnZ3JlZ2F0aW9uUXVlcnkuQWdncmVnYXRpb25CBOJBAQFSDGFnZ3JlZ2F0aW9ucxqfBAoLQWdn'
    'cmVnYXRpb24SWQoFY291bnQYASABKAsyQS5nb29nbGUuZmlyZXN0b3JlLnYxLlN0cnVjdHVyZW'
    'RBZ2dyZWdhdGlvblF1ZXJ5LkFnZ3JlZ2F0aW9uLkNvdW50SABSBWNvdW50ElMKA3N1bRgCIAEo'
    'CzI/Lmdvb2dsZS5maXJlc3RvcmUudjEuU3RydWN0dXJlZEFnZ3JlZ2F0aW9uUXVlcnkuQWdncm'
    'VnYXRpb24uU3VtSABSA3N1bRJTCgNhdmcYAyABKAsyPy5nb29nbGUuZmlyZXN0b3JlLnYxLlN0'
    'cnVjdHVyZWRBZ2dyZWdhdGlvblF1ZXJ5LkFnZ3JlZ2F0aW9uLkF2Z0gAUgNhdmcSGgoFYWxpYX'
    'MYByABKAlCBOJBAQFSBWFsaWFzGj8KBUNvdW50EjYKBXVwX3RvGAEgASgLMhsuZ29vZ2xlLnBy'
    'b3RvYnVmLkludDY0VmFsdWVCBOJBAQFSBHVwVG8aUAoDU3VtEkkKBWZpZWxkGAEgASgLMjMuZ2'
    '9vZ2xlLmZpcmVzdG9yZS52MS5TdHJ1Y3R1cmVkUXVlcnkuRmllbGRSZWZlcmVuY2VSBWZpZWxk'
    'GlAKA0F2ZxJJCgVmaWVsZBgBIAEoCzIzLmdvb2dsZS5maXJlc3RvcmUudjEuU3RydWN0dXJlZF'
    'F1ZXJ5LkZpZWxkUmVmZXJlbmNlUgVmaWVsZEIKCghvcGVyYXRvckIMCgpxdWVyeV90eXBl');

@$core.Deprecated('Use cursorDescriptor instead')
const Cursor$json = {
  '1': 'Cursor',
  '2': [
    {'1': 'values', '3': 1, '4': 3, '5': 11, '6': '.google.firestore.v1.Value', '10': 'values'},
    {'1': 'before', '3': 2, '4': 1, '5': 8, '10': 'before'},
  ],
};

/// Descriptor for `Cursor`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List cursorDescriptor = $convert.base64Decode(
    'CgZDdXJzb3ISMgoGdmFsdWVzGAEgAygLMhouZ29vZ2xlLmZpcmVzdG9yZS52MS5WYWx1ZVIGdm'
    'FsdWVzEhYKBmJlZm9yZRgCIAEoCFIGYmVmb3Jl');

