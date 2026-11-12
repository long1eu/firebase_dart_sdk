// Copyright 2024 Google LLC
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

/// The distance measure used by a nearest-neighbour (vector) query.
enum DistanceMeasure {
  /// Measures the euclidean distance between the vectors.
  euclidean,

  /// Compares vectors based on the angle between them, which allows you to
  /// measure similarity that is not influenced by the magnitude of the
  /// vectors.
  cosine,

  /// Similar to cosine but is affected by the magnitude of the vectors.
  dotProduct,
}
