// One test per scenario of syncPointSpec.json, named by the scenario. Run one with
//   dart test test/spec/sync_point_spec_test.dart -N '<scenario name>'
import 'package:test/test.dart';

import 'sync_point_spec_runner.dart';

void main() {
  for (final SyncPointScenario scenario in loadSyncPointScenarios()) {
    test(scenario.name, () => runSyncPointScenario(scenario));
  }
}
