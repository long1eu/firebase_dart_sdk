// One test per scenario of syncPointSpec.json, named by the scenario. Run one with
//   dart test test/spec/sync_point_spec_test.dart -N '<scenario name>'
// The scenarios come from the copy of the spec embedded in sync_point_spec.g.dart, so this runs on
// the VM and in a browser; sync_point_spec_embedded_test.dart keeps that copy equal to the file.
library;

import 'package:test/test.dart';

import 'sync_point_spec_runner.dart';

void main() {
  for (final SyncPointScenario scenario in loadSyncPointScenarios()) {
    test(scenario.name, () => runSyncPointScenario(scenario));
  }
}
