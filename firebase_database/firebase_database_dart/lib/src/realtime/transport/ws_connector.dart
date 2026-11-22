/// The platform's WebSocket connector, chosen by conditional import (owner T).
///
/// The web branch comes first for `tool/check_web_imports.dart`; the VM takes
/// `ws_channel_io.dart` (test plan 2.1).
library;

import 'package:firebase_database_dart/src/realtime/transport/ws_channel.dart';
import 'package:firebase_database_dart/src/realtime/transport/ws_channel_web.dart'
    if (dart.library.io) 'package:firebase_database_dart/src/realtime/transport/ws_channel_io.dart'
    as platform;

/// The [WsConnector] of this platform. [maxMessageBytes] bounds one inbound message on the VM
/// (threat model T9); the browser applies its own limits.
WsConnector platformWsConnector({required int maxMessageBytes}) =>
    platform.createWsConnector(maxMessageBytes: maxMessageBytes);

/// Whether the connector of this platform sends upgrade headers: true on the VM, false in a
/// browser. `RealtimeTarget` puts `p` and `ac` in the URL when false (`rtdb_protocol.md` 2.3).
const bool wsConnectorSendsHeaders = platform.platformSendsHeaders;
