// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'package:cloud_firestore_dart/src/firebase/firestore/core/listent_sequence.dart';
import 'package:test/test.dart';

/// Ported from the JS SDK (test/unit/core/listen_sequence.test.ts). The port
/// follows Android: there is no multi-tab syncer, so the sequence numbers are
/// not written anywhere ("writes the new sequence number to the syncer" has no
/// counterpart) and the syncer notification is [ListenSequence.advanceTo].
void main() {
  test('bumps the next value based on notifications from the syncer', () {
    final ListenSequence listenSequence = ListenSequence(0)..advanceTo(5);
    expect(listenSequence.next, 6);
    expect(listenSequence.next, 7);
    listenSequence.advanceTo(18);
    expect(listenSequence.next, 19);
  });
}
