// File created by
// Lung Razvan <long1eu>
// on 23/10/2018

import 'package:firebase_storage_vm/src/network/network_request.dart';

import 'test_http_client_provider.dart';

TestHttpClientProvider ensureNetworkMock({String testName, bool isBinary}) {
  final TestHttpClientProvider mockConnectionFactory =
      TestHttpClientProvider(testName: testName, isBinary: isBinary);

  NetworkRequest.clientProvider = mockConnectionFactory;
  return mockConnectionFactory;
}
