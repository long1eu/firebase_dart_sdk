// File created by
// Lung Razvan <long1eu>
// on 23/10/2018
import 'package:test/test.dart';

import 'network_layer_mock.dart';
import 'test_command_helper.dart';
import 'test_util.dart' as util;

void main() {
  setUp(util.setUp);

  tearDown(util.tearDown);

  test('deleteBlob', () async {
    ensureNetworkMock(testName: 'deleteBlob', isBinary: false);
    final StringBuffer task = await deleteBlob();
    await util.verifyTaskStateChanges('deleteBlob', contents: task.toString());
  });
}
