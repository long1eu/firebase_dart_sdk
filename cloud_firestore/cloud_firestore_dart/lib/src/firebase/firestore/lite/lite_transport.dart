// Copyright 2026 Google LLC
//
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
// The transport Firestore Lite uses on this platform: gRPC where there are
// sockets, REST (without WebChannel) on the web.
export 'lite_transport_unsupported.dart'
    if (dart.library.io) 'lite_transport_io.dart'
    if (dart.library.js_interop) 'lite_transport_web.dart'
    show createLiteTransport;
