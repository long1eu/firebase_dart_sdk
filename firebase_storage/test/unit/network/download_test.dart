// File created by
// Lung Razvan <long1eu>
// on 24/10/2018

import 'dart:io';

import 'package:test/test.dart';

import 'network_layer_mock.dart';
import 'test_command_helper.dart';
import 'test_util.dart' as util;

void main() {
  setUp(util.setUp);

  tearDown(util.tearDown);

  test('fileDownload', () async {
    ensureNetworkMock(testName: 'deleteBlob', isBinary: false);

    final StringBuffer task = await deleteBlob();
    await util.verifyTaskStateChanges('deleteBlob', contents: task.toString());

    print('Starting test fileDownload.');

    final File outputFile =
        File('${Directory.current.path}/build/test/download.jpg')
          ..createSync(recursive: true);

    if (outputFile.existsSync()) {
      outputFile.deleteSync();
    }

    Uri destinationUri = Uri.fromFile(outputFile);
    ensureNetworkMock(testName: 'fileDownload', isBinary: true);

    bool completeHandlerInvoked = false;

    Task<StringBuilder> task =
        TestDownloadHelper.fileDownload(destinationUri, () {
      assertTrue(outputFile.existsSync());
      assertEquals(1076408, outputFile.length());
      completeHandlerInvoked = true;
    }, -1);

    for (int i = 0; i < 3000; i++) {
      Robolectric.flushForegroundThreadScheduler();
      if (task.isComplete()) {
        // success!
        factory.verifyOldMock();
        TestUtil.verifyTaskStateChanges(
            'fileDownload', task.getResult().toString());
        assertTrue(completeHandlerInvoked[0]);
        return;
      }
      Thread.sleep(1);
    }
    fail();
  });
}
