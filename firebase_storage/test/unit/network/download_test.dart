// File created by
// Lung Razvan <long1eu>
// on 24/10/2018

import 'dart:io';

import 'package:test/test.dart';

import 'network_layer_mock.dart';
import 'test_download_helper.dart';
import 'test_util.dart' as util;

void main() {
  setUp(util.setUp);

  tearDown(util.tearDown);

  test('fileDownload', () async {
    print('Starting test fileDownload.');

    final File outputFile =
        File('${Directory.current.path}/build/test/download.jpg')
          ..createSync(recursive: true);

    if (outputFile.existsSync()) {
      outputFile.deleteSync();
    }

    ensureNetworkMock(testName: 'fileDownload', isBinary: true);

    bool completeHandlerInvoked = false;

    final StringBuffer result = await fileDownload(outputFile, () {
      expect(outputFile.existsSync(), isTrue);
      expect(outputFile.lengthSync(), 1076408);
      completeHandlerInvoked = true;
    }, -1);

    await util.verifyTaskStateChanges('fileDownload',
        contents: result.toString());
    expect(completeHandlerInvoked, isTrue);
  });
}
