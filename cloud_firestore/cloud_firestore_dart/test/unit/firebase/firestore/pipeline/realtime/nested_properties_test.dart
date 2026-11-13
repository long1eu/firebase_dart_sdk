// Copyright 2025 Google LLC
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

// Ported from the Android SDK:
// firebase-firestore/src/test/java/com/google/firebase/firestore/pipeline/NestedPropertiesTests.kt
//
// The port keeps the names and the structure of the Kotlin tests;
// realtime_pipeline_test_util.dart has the functions they call. Where the
// expected result differs from Android's, a comment says why.

// ignore_for_file: prefer_single_quotes, always_specify_types
// ignore_for_file: lines_longer_than_80_chars, prefer_final_locals
// ignore_for_file: omit_local_variable_types, unused_local_variable
// ignore_for_file: prefer_const_declarations, prefer_const_constructors

// The documents hold doubles with integral values (1.0, -0.0) and 64-bit
// integers, which compiled to JavaScript are not what they are on the VM.
@TestOn('vm')
library;

import 'package:test/test.dart' show TestOn, test;

import 'realtime_pipeline_test_util.dart';

void main() {
  test('where equality deeply nested', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'a': <String, Object?>{
        'b': <String, Object?>{
          'c': <String, Object?>{
            'd': <String, Object?>{
              'e': <String, Object?>{
                'f': <String, Object?>{
                  'g': <String, Object?>{
                    'h': <String, Object?>{
                      'i': <String, Object?>{
                        'j': <String, Object?>{'k': 42},
                      },
                    },
                  },
                },
              },
            },
          },
        },
      },
    }); // Match
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'a': <String, Object?>{
        'b': <String, Object?>{
          'c': <String, Object?>{
            'd': <String, Object?>{
              'e': <String, Object?>{
                'f': <String, Object?>{
                  'g': <String, Object?>{
                    'h': <String, Object?>{
                      'i': <String, Object?>{
                        'j': <String, Object?>{'k': '42'},
                      },
                    },
                  },
                },
              },
            },
          },
        },
      },
    });
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'a': <String, Object?>{
        'b': <String, Object?>{
          'c': <String, Object?>{
            'd': <String, Object?>{
              'e': <String, Object?>{
                'f': <String, Object?>{
                  'g': <String, Object?>{
                    'h': <String, Object?>{
                      'i': <String, Object?>{
                        'j': <String, Object?>{'k': 0},
                      },
                    },
                  },
                },
              },
            },
          },
        },
      },
    });
    final documents = [doc1, doc2, doc3];

    final pipeline = RealtimePipelineSource()
        .collection('/users')
        .where(field('a.b.c.d.e.f.g.h.i.j.k').equal(constant(42)));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc1]);
  });

  test('where inequality deeply nested', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'a': <String, Object?>{
        'b': <String, Object?>{
          'c': <String, Object?>{
            'd': <String, Object?>{
              'e': <String, Object?>{
                'f': <String, Object?>{
                  'g': <String, Object?>{
                    'h': <String, Object?>{
                      'i': <String, Object?>{
                        'j': <String, Object?>{'k': 42},
                      },
                    },
                  },
                },
              },
            },
          },
        },
      },
    }); // Match
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'a': <String, Object?>{
        'b': <String, Object?>{
          'c': <String, Object?>{
            'd': <String, Object?>{
              'e': <String, Object?>{
                'f': <String, Object?>{
                  'g': <String, Object?>{
                    'h': <String, Object?>{
                      'i': <String, Object?>{
                        'j': <String, Object?>{'k': '42'},
                      },
                    },
                  },
                },
              },
            },
          },
        },
      },
    });
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'a': <String, Object?>{
        'b': <String, Object?>{
          'c': <String, Object?>{
            'd': <String, Object?>{
              'e': <String, Object?>{
                'f': <String, Object?>{
                  'g': <String, Object?>{
                    'h': <String, Object?>{
                      'i': <String, Object?>{
                        'j': <String, Object?>{'k': 0},
                      },
                    },
                  },
                },
              },
            },
          },
        },
      },
    }); // Match
    final documents = [doc1, doc2, doc3];

    final pipeline = RealtimePipelineSource()
        .collection('/users')
        .where(field('a.b.c.d.e.f.g.h.i.j.k').greaterThanOrEqual(constant(0)))
        .sort([Field.of(FieldPath.documentIdField).ascending()]);

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc1, doc3]).inOrder();
  });

  test('where equality', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'address': <String, Object?>{
        'city': 'San Francisco',
        'state': 'CA',
        'zip': 94105,
      },
    });
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'address': <String, Object?>{
        'street': '76',
        'city': 'New York',
        'state': 'NY',
        'zip': 10011,
      },
    }); // Match
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'address': <String, Object?>{
        'city': 'Mountain View',
        'state': 'CA',
        'zip': 94043,
      },
    });
    final doc4 = doc('users/d', 1000, <String, Object?>{});
    final documents = [doc1, doc2, doc3, doc4];

    final pipeline = RealtimePipelineSource()
        .collection('/users')
        .where(field('address.street').equal(constant('76')));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc2]);
  });

  test('multiple filters', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'address': <String, Object?>{
        'city': 'San Francisco',
        'state': 'CA',
        'zip': 94105,
      },
    }); // Match
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'address': <String, Object?>{
        'street': '76',
        'city': 'New York',
        'state': 'NY',
        'zip': 10011,
      },
    });
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'address': <String, Object?>{
        'city': 'Mountain View',
        'state': 'CA',
        'zip': 94043,
      },
    });
    final doc4 = doc('users/d', 1000, <String, Object?>{});
    final documents = [doc1, doc2, doc3, doc4];

    final pipeline = RealtimePipelineSource()
        .collection('/users')
        .where(field('address.city').equal(constant('San Francisco')))
        .where(field('address.zip').greaterThan(constant(90000)));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc1]);
  });

  test('multiple filters redundant', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'address': <String, Object?>{
        'city': 'San Francisco',
        'state': 'CA',
        'zip': 94105,
      },
    }); // Match
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'address': <String, Object?>{
        'street': '76',
        'city': 'New York',
        'state': 'NY',
        'zip': 10011,
      },
    });
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'address': <String, Object?>{
        'city': 'Mountain View',
        'state': 'CA',
        'zip': 94043,
      },
    });
    final doc4 = doc('users/d', 1000, <String, Object?>{});
    final documents = [doc1, doc2, doc3, doc4];

    final pipeline = RealtimePipelineSource()
        .collection('/users')
        .where(
          field('address').equal(
            map(<String, Object?>{
              'city': 'San Francisco',
              'state': 'CA',
              'zip': 94105,
            }),
          ),
        )
        .where(field('address.zip').greaterThan(constant(90000)));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc1]);
  });

  test('multiple filters with composite index', () {
    // This test is functionally identical to MultipleFilters
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'address': <String, Object?>{
        'city': 'San Francisco',
        'state': 'CA',
        'zip': 94105,
      },
    }); // Match
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'address': <String, Object?>{
        'street': '76',
        'city': 'New York',
        'state': 'NY',
        'zip': 10011,
      },
    });
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'address': <String, Object?>{
        'city': 'Mountain View',
        'state': 'CA',
        'zip': 94043,
      },
    });
    final doc4 = doc('users/d', 1000, <String, Object?>{});
    final documents = [doc1, doc2, doc3, doc4];

    final pipeline = RealtimePipelineSource()
        .collection('/users')
        .where(field('address.city').equal(constant('San Francisco')))
        .where(field('address.zip').greaterThan(constant(90000)));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc1]);
  });

  test('where inequality', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'address': <String, Object?>{
        'city': 'San Francisco',
        'state': 'CA',
        'zip': 94105,
      },
    }); // zip > 90k
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'address': <String, Object?>{
        'street': '76',
        'city': 'New York',
        'state': 'NY',
        'zip': 10011,
      },
    }); // zip < 90k
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'address': <String, Object?>{
        'city': 'Mountain View',
        'state': 'CA',
        'zip': 94043,
      },
    }); // zip > 90k
    final doc4 = doc('users/d', 1000, <String, Object?>{});
    final doc5 = doc('users/d', 1000, <String, Object?>{
      'address': '1 Front Street',
    });
    final doc6 = doc('users/d', 1000, <String, Object?>{'address': null});
    final doc7 = doc('users/d', 1000, <String, Object?>{
      'different': <String, Object?>{'zip': 94105},
    });
    final doc8 = doc('users/d', 1000, <String, Object?>{
      'not-address': '1 Front Street',
    });
    final documents = [doc1, doc2, doc3, doc4, doc5, doc6, doc7, doc8];

    final pipeline1 = RealtimePipelineSource()
        .collection('/users')
        .where(field('address.zip').greaterThan(constant(90000)));
    assertThat(runPipeline(pipeline1, documents)).containsExactly([doc1, doc3]);

    final pipeline2 = RealtimePipelineSource()
        .collection('/users')
        .where(field('address.zip').lessThan(constant(90000)));
    assertThat(runPipeline(pipeline2, documents)).containsExactly([doc2]);

    final pipeline3 = RealtimePipelineSource()
        .collection('/users')
        .where(field('address.zip').lessThan(constant(0)));
    assertThat(runPipeline(pipeline3, documents)).isEmpty();

    final pipeline4 = RealtimePipelineSource()
        .collection('/users')
        .where(field('address.zip').notEqual(constant(10011)));
    assertThat(
      runPipeline(pipeline4, documents),
    ).containsExactly([doc1, doc3, doc4, doc5, doc6, doc7, doc8]);
  });

  test('where exists', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'address': <String, Object?>{
        'city': 'San Francisco',
        'state': 'CA',
        'zip': 94105,
      },
    });
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'address': <String, Object?>{
        'street': '76',
        'city': 'New York',
        'state': 'NY',
        'zip': 10011,
      },
    }); // Match
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'address': <String, Object?>{
        'city': 'Mountain View',
        'state': 'CA',
        'zip': 94043,
      },
    });
    final doc4 = doc('users/d', 1000, <String, Object?>{});
    final documents = [doc1, doc2, doc3, doc4];

    final pipeline = RealtimePipelineSource()
        .collection('/users')
        .where(exists(field('address.street')));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc2]);
  });

  test('where not exists', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'address': <String, Object?>{
        'city': 'San Francisco',
        'state': 'CA',
        'zip': 94105,
      },
    }); // Match
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'address': <String, Object?>{
        'street': '76',
        'city': 'New York',
        'state': 'NY',
        'zip': 10011,
      },
    });
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'address': <String, Object?>{
        'city': 'Mountain View',
        'state': 'CA',
        'zip': 94043,
      },
    }); // Match
    final doc4 = doc('users/d', 1000, <String, Object?>{}); // Match
    final documents = [doc1, doc2, doc3, doc4];

    final pipeline = RealtimePipelineSource()
        .collection('/users')
        .where(not(exists(field('address.street'))));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc1, doc3, doc4]).inOrder();
  });

  test('where is null', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'address': <String, Object?>{
        'city': 'San Francisco',
        'state': 'CA',
        'zip': 94105,
        'street': null,
      },
    }); // Match
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'address': <String, Object?>{
        'street': '76',
        'city': 'New York',
        'state': 'NY',
        'zip': 10011,
      },
    });
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'address': <String, Object?>{
        'city': 'Mountain View',
        'state': 'CA',
        'zip': 94043,
      },
    });
    final documents = [doc1, doc2, doc3];

    final pipeline = RealtimePipelineSource()
        .collection('/users')
        .where(field('address.street').equal(nullValue()));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc1]);
  });

  test('where is not null', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'address': <String, Object?>{
        'city': 'San Francisco',
        'state': 'CA',
        'zip': 94105,
        'street': null,
      },
    });
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'address': <String, Object?>{
        'street': '76',
        'city': 'New York',
        'state': 'NY',
        'zip': 10011,
      },
    }); // Match
    final doc3 = doc(
      'users/c',
      1000,
      <String, Object?>{
        'address': <String, Object?>{
          'city': 'Mountain View',
          'state': 'CA',
          'zip': 94043,
        },
      },
    ); // street is missing, so it's not 'not null' in the context of this filter
    final documents = [doc1, doc2, doc3];

    final pipeline = RealtimePipelineSource()
        .collection('/users')
        .where(
          and(
            exists(field('address.street')),
            field('address.street').notEqual(nullValue()),
          ),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc2]);
  });

  test('sort with exists', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'address': <String, Object?>{
        'street': '41',
        'city': 'San Francisco',
        'state': 'CA',
        'zip': 94105,
      },
    }); // Match
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'address': <String, Object?>{
        'street': '76',
        'city': 'New York',
        'state': 'NY',
        'zip': 10011,
      },
    }); // Match
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'address': <String, Object?>{
        'city': 'Mountain View',
        'state': 'CA',
        'zip': 94043,
      },
    });
    final doc4 = doc('users/d', 1000, <String, Object?>{});
    final documents = [doc1, doc2, doc3, doc4];

    final pipeline = RealtimePipelineSource()
        .collection('/users')
        .where(exists(field('address.street')))
        .sort([field('address.street').ascending()]);

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc1, doc2]).inOrder();
  });

  test('sort without exists', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'address': <String, Object?>{
        'street': '41',
        'city': 'San Francisco',
        'state': 'CA',
        'zip': 94105,
      },
    });
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'address': <String, Object?>{
        'street': '76',
        'city': 'New York',
        'state': 'NY',
        'zip': 10011,
      },
    });
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'address': <String, Object?>{
        'city': 'Mountain View',
        'state': 'CA',
        'zip': 94043,
      },
    });
    final doc4 = doc('users/d', 1000, <String, Object?>{});
    final documents = [doc1, doc2, doc3, doc4];

    final pipeline = RealtimePipelineSource().collection('/users').sort([
      field('address.street').ascending(),
    ]);

    final result = runPipeline(pipeline, documents);
    // Missing fields sort first, then by key (c < d). Then existing fields by value ('41' < '76').
    assertThat(result).containsExactly([doc3, doc4, doc1, doc2]).inOrder();
  });

  test('quoted nested property filter nested', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'address.city': 'San Francisco',
    });
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'address': <String, Object?>{'city': 'San Francisco'},
    }); // Match
    final doc3 = doc('users/c', 1000, <String, Object?>{});
    final documents = [doc1, doc2, doc3];

    final pipeline = RealtimePipelineSource()
        .collection('/users')
        .where(field('address.city').equal(constant('San Francisco')));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc2]);
  });

  test('quoted nested property filter quoted nested', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'address.city': 'San Francisco',
    }); // Match
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'address': <String, Object?>{'city': 'San Francisco'},
    });
    final doc3 = doc('users/c', 1000, <String, Object?>{});
    final documents = [doc1, doc2, doc3];

    final pipeline = RealtimePipelineSource()
        .collection('/users')
        .where(
          Field.of(
            FieldPath.of(<String>['address.city']),
          ).equal(constant('San Francisco')),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc1]);
  });
}
