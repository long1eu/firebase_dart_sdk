// Copyright 2022 Google LLC
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

import 'package:cloud_firestore_dart/src/firebase/firestore/core/filter/filter.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/logic_utils.dart';
import 'package:test/test.dart';

import '../../../../util/test_util.dart';

/// Port of upstream util/LogicUtilsTest.
void main() {
  // Helper to get unique filters.
  FieldFilter nameFilter(String name) => filter('name', '==', name);

  final FieldFilter a = nameFilter('A');
  final FieldFilter b = nameFilter('B');
  final FieldFilter c = nameFilter('C');
  final FieldFilter d = nameFilter('D');
  final FieldFilter e = nameFilter('E');
  final FieldFilter f = nameFilter('F');
  final FieldFilter g = nameFilter('G');
  final FieldFilter h = nameFilter('H');
  final FieldFilter i = nameFilter('I');

  CompositeFilter and(List<Filter> filters) => andFilters(filters);
  CompositeFilter or(List<Filter> filters) => orFilters(filters);

  test('testFieldFilterAssociativity', () {
    final FieldFilter field = filter('foo', '==', 'bar');
    expect(LogicUtils.applyAssociation(field), field);
  });

  test('testCompositeFilterAssociativity', () {
    // AND(AND(X)) --> X
    expect(
        LogicUtils.applyAssociation(and(<Filter>[
          and(<Filter>[a])
        ])),
        a);

    // OR(OR(X)) --> X
    expect(
        LogicUtils.applyAssociation(or(<Filter>[
          or(<Filter>[a])
        ])),
        a);

    // (A | (B) | ((C) | (D | E)) | (F | (G & (H & I)))
    //   --> A | B | C | D | E | F | (G & H & I)
    final CompositeFilter complexFilter = or(<Filter>[
      a,
      and(<Filter>[b]),
      or(<Filter>[
        or(<Filter>[c]),
        or(<Filter>[d, e])
      ]),
      or(<Filter>[
        f,
        and(<Filter>[
          g,
          and(<Filter>[h, i])
        ])
      ]),
    ]);
    final CompositeFilter expectedResult = or(<Filter>[
      a,
      b,
      c,
      d,
      e,
      f,
      and(<Filter>[g, h, i])
    ]);
    expect(LogicUtils.applyAssociation(complexFilter), expectedResult);
  });

  test('testFieldFilterDistributionOverFieldFilter', () {
    expect(LogicUtils.applyDistribution(a, b), and(<Filter>[a, b]));
    expect(LogicUtils.applyDistribution(b, a), and(<Filter>[b, a]));
  });

  test('testFieldFilterDistributionOverAndFilter', () {
    // (A & B & C) & D = (A & B & C & D)
    expect(LogicUtils.applyDistribution(and(<Filter>[a, b, c]), d),
        and(<Filter>[a, b, c, d]));
  });

  test('testFieldFilterDistributionOverOrFilter', () {
    // A & (B | C | D) = (A & B) | (A & C) | (A & D)
    // (B | C | D) & A = (A & B) | (A & C) | (A & D)
    final CompositeFilter expected = or(<Filter>[
      and(<Filter>[a, b]),
      and(<Filter>[a, c]),
      and(<Filter>[a, d])
    ]);
    expect(LogicUtils.applyDistribution(a, or(<Filter>[b, c, d])), expected);
    expect(LogicUtils.applyDistribution(or(<Filter>[b, c, d]), a), expected);
  });

  // The following four tests cover:
  // AND distribution for AND filter and AND filter.
  // AND distribution for OR filter and AND filter.
  // AND distribution for AND filter and OR filter.
  // AND distribution for OR filter and OR filter.
  test('testAndFilterDistributionWithAndFilter', () {
    // (A & B) & (C & D) --> (A & B & C & D)
    expect(
        LogicUtils.applyDistribution(
            and(<Filter>[a, b]), and(<Filter>[c, d])),
        and(<Filter>[a, b, c, d]));
  });

  test('testAndFilterDistributionWithOrFilter', () {
    // (A & B) & (C | D) --> (A & B & C) | (A & B & D)
    expect(
        LogicUtils.applyDistribution(and(<Filter>[a, b]), or(<Filter>[c, d])),
        or(<Filter>[
          and(<Filter>[a, b, c]),
          and(<Filter>[a, b, d])
        ]));
  });

  test('testOrFilterDistributionWithAndFilter', () {
    // (A | B) & (C & D) --> (A & C & D) | (B & C & D)
    expect(
        LogicUtils.applyDistribution(or(<Filter>[a, b]), and(<Filter>[c, d])),
        or(<Filter>[
          and(<Filter>[c, d, a]),
          and(<Filter>[c, d, b])
        ]));
  });

  test('testOrFilterDistributionWithOrFilter', () {
    // (A | B) & (C | D) --> (A & C) | (A & D) | (B & C) | (B & D)
    expect(
        LogicUtils.applyDistribution(or(<Filter>[a, b]), or(<Filter>[c, d])),
        or(<Filter>[
          and(<Filter>[a, c]),
          and(<Filter>[a, d]),
          and(<Filter>[b, c]),
          and(<Filter>[b, d])
        ]));
  });

  test('testFieldFilterComputeDnf', () {
    expect(LogicUtils.computeDistributedNormalForm(a), a);
    expect(LogicUtils.getDnfTerms(and(<Filter>[a])), <Filter>[a]);
    expect(LogicUtils.getDnfTerms(or(<Filter>[a])), <Filter>[a]);
  });

  test('testComputeDnfFlatAndFilter', () {
    final CompositeFilter compositeFilter = and(<Filter>[a, b, c]);
    expect(LogicUtils.computeDistributedNormalForm(compositeFilter),
        compositeFilter);
    expect(LogicUtils.getDnfTerms(compositeFilter), <Filter>[compositeFilter]);
  });

  test('testComputeDnfFlatOrFilter', () {
    final CompositeFilter compositeFilter = or(<Filter>[a, b, c]);
    expect(LogicUtils.computeDistributedNormalForm(compositeFilter),
        compositeFilter);
    expect(LogicUtils.getDnfTerms(compositeFilter), <Filter>[a, b, c]);
  });

  void expectDnf(CompositeFilter input, List<Filter> expectedTerms) {
    expect(LogicUtils.computeDistributedNormalForm(input), or(expectedTerms));
    expect(LogicUtils.getDnfTerms(input), expectedTerms);
  }

  test('testComputeDnf1', () {
    // A & (B | C) --> (A & B) | (A & C)
    expectDnf(and(<Filter>[
      a,
      or(<Filter>[b, c])
    ]), <Filter>[
      and(<Filter>[a, b]),
      and(<Filter>[a, c])
    ]);
  });

  test('testComputeDnf2', () {
    // ((A)) & (B & C) --> A & B & C
    final CompositeFilter compositeFilter = and(<Filter>[
      and(<Filter>[
        and(<Filter>[a])
      ]),
      and(<Filter>[b, c])
    ]);
    final CompositeFilter expectedResult = and(<Filter>[a, b, c]);
    expect(LogicUtils.computeDistributedNormalForm(compositeFilter),
        expectedResult);
    expect(LogicUtils.getDnfTerms(compositeFilter), <Filter>[expectedResult]);
  });

  test('testComputeDnf3', () {
    // A | (B & C)
    final CompositeFilter compositeFilter = or(<Filter>[
      a,
      and(<Filter>[b, c])
    ]);
    expect(LogicUtils.computeDistributedNormalForm(compositeFilter),
        compositeFilter);
    expect(LogicUtils.getDnfTerms(compositeFilter), <Filter>[
      a,
      and(<Filter>[b, c])
    ]);
  });

  test('testComputeDnf4', () {
    // A | (B & C) | ( ((D)) | (E | F) | (G & H) )
    //   --> A | (B & C) | D | E | F | (G & H)
    expectDnf(
        or(<Filter>[
          a,
          and(<Filter>[b, c]),
          or(<Filter>[
            and(<Filter>[
              or(<Filter>[d])
            ]),
            or(<Filter>[e, f]),
            and(<Filter>[g, h])
          ])
        ]),
        <Filter>[
          a,
          and(<Filter>[b, c]),
          d,
          e,
          f,
          and(<Filter>[g, h])
        ]);
  });

  test('testComputeDnf5', () {
    //    A & (B | C) & ( ((D)) & (E | F) & (G & H) )
    // -> A & (B | C) & D & (E | F) & G & H
    // -> ((A & B) | (A & C)) & D & (E | F) & G & H
    // -> ((A & B & D) | (A & C & D)) & (E|F) & G & H
    // -> ((A & B & D & E) | (A & B & D & F) | (A & C & D & E) | (A & C & D & F)) & G & H
    // -> ((A&B&D&E&G) | (A & B & D & F & G) | (A & C & D & E & G) | (A & C & D & F & G)) & H
    // -> (A&B&D&E&G&H) | (A&B&D&F&G&H) | (A & C & D & E & G & H) | (A & C & D & F & G & H)
    expectDnf(
        and(<Filter>[
          a,
          or(<Filter>[b, c]),
          and(<Filter>[
            and(<Filter>[
              or(<Filter>[d])
            ]),
            or(<Filter>[e, f]),
            and(<Filter>[g, h])
          ])
        ]),
        <Filter>[
          and(<Filter>[d, e, g, h, a, b]),
          and(<Filter>[d, f, g, h, a, b]),
          and(<Filter>[d, e, g, h, a, c]),
          and(<Filter>[d, f, g, h, a, c])
        ]);
  });

  test('testComputeDnf6', () {
    // A & (B | (C & (D | (E & F))))
    // -> A & (B | (C & D) | (C & E & F))
    // -> (A & B) | (A & C & D) | (A & C & E & F)
    expectDnf(
        and(<Filter>[
          a,
          or(<Filter>[
            b,
            and(<Filter>[
              c,
              or(<Filter>[
                d,
                and(<Filter>[e, f])
              ])
            ])
          ])
        ]),
        <Filter>[
          and(<Filter>[a, b]),
          and(<Filter>[c, d, a]),
          and(<Filter>[e, f, c, a])
        ]);
  });

  test('testComputeDnf7', () {
    // ( (A|B) & (C|D) ) | ( (E|F) & (G|H) )
    // -> (A&C)|(A&D)|(B&C)(B&D)|(E&G)|(E&H)|(F&G)|(F&H)
    expectDnf(
        or(<Filter>[
          and(<Filter>[
            or(<Filter>[a, b]),
            or(<Filter>[c, d])
          ]),
          and(<Filter>[
            or(<Filter>[e, f]),
            or(<Filter>[g, h])
          ])
        ]),
        <Filter>[
          and(<Filter>[a, c]),
          and(<Filter>[a, d]),
          and(<Filter>[b, c]),
          and(<Filter>[b, d]),
          and(<Filter>[e, g]),
          and(<Filter>[e, h]),
          and(<Filter>[f, g]),
          and(<Filter>[f, h])
        ]);
  });

  test('testComputeDnf8', () {
    // ( (A&B) | (C&D) ) & ( (E&F) | (G&H) )
    // -> A&B&E&F | A&B&G&H | C&D&E&F | C&D&G&H
    expectDnf(
        and(<Filter>[
          or(<Filter>[
            and(<Filter>[a, b]),
            and(<Filter>[c, d])
          ]),
          or(<Filter>[
            and(<Filter>[e, f]),
            and(<Filter>[g, h])
          ])
        ]),
        <Filter>[
          and(<Filter>[e, f, a, b]),
          and(<Filter>[g, h, a, b]),
          and(<Filter>[e, f, c, d]),
          and(<Filter>[g, h, c, d])
        ]);
  });

  test('testInExpansionForFieldFilters', () {
    final FieldFilter input1 = filter('a', 'in', <int>[1, 2, 3]);
    final List<FieldFilter> others = <FieldFilter>[
      filter('a', '<', 1),
      filter('a', '<=', 1),
      filter('a', '==', 1),
      filter('a', '!=', 1),
      filter('a', '>', 1),
      filter('a', '>=', 1),
      filter('a', 'array-contains', 1),
      filter('a', 'array-contains-any', <int>[1, 2]),
      filter('a', 'not-in', <int>[1, 2]),
    ];

    expect(
        LogicUtils.computeInExpansion(input1),
        or(<Filter>[
          filter('a', '==', 1),
          filter('a', '==', 2),
          filter('a', '==', 3)
        ]));

    // Other operators should remain the same.
    for (FieldFilter other in others) {
      expect(LogicUtils.computeInExpansion(other), other);
    }
  });

  test('testInExpansionForCompositeFilters', () {
    final CompositeFilter cf1 = and(<Filter>[
      filter('a', '==', 1),
      filter('b', 'in', <int>[2, 3, 4])
    ]);
    expect(
        LogicUtils.computeInExpansion(cf1),
        and(<Filter>[
          filter('a', '==', 1),
          or(<Filter>[
            filter('b', '==', 2),
            filter('b', '==', 3),
            filter('b', '==', 4)
          ])
        ]));

    final CompositeFilter cf2 = or(<Filter>[
      filter('a', '==', 1),
      filter('b', 'in', <int>[2, 3, 4])
    ]);
    expect(
        LogicUtils.computeInExpansion(cf2),
        or(<Filter>[
          filter('a', '==', 1),
          or(<Filter>[
            filter('b', '==', 2),
            filter('b', '==', 3),
            filter('b', '==', 4)
          ])
        ]));

    final CompositeFilter cf3 = and(<Filter>[
      filter('a', '==', 1),
      or(<Filter>[
        filter('b', '==', 2),
        filter('c', 'in', <int>[2, 3, 4])
      ])
    ]);
    expect(
        LogicUtils.computeInExpansion(cf3),
        and(<Filter>[
          filter('a', '==', 1),
          or(<Filter>[
            filter('b', '==', 2),
            or(<Filter>[
              filter('c', '==', 2),
              filter('c', '==', 3),
              filter('c', '==', 4)
            ])
          ])
        ]));

    final CompositeFilter cf4 = or(<Filter>[
      filter('a', '==', 1),
      and(<Filter>[
        filter('b', '==', 2),
        filter('c', 'in', <int>[2, 3, 4])
      ])
    ]);
    expect(
        LogicUtils.computeInExpansion(cf4),
        or(<Filter>[
          filter('a', '==', 1),
          and(<Filter>[
            filter('b', '==', 2),
            or(<Filter>[
              filter('c', '==', 2),
              filter('c', '==', 3),
              filter('c', '==', 4)
            ])
          ])
        ]));
  });

  test('getDnfTerms expands in filters', () {
    // a == 1 && b in [2, 3]  -->  (a == 1 && b == 2) || (a == 1 && b == 3)
    expect(
        LogicUtils.getDnfTerms(and(<Filter>[
          filter('a', '==', 1),
          filter('b', 'in', <int>[2, 3])
        ])),
        <Filter>[
          and(<Filter>[filter('a', '==', 1), filter('b', '==', 2)]),
          and(<Filter>[filter('a', '==', 1), filter('b', '==', 3)]),
        ]);
    expect(LogicUtils.getDnfTerms(and(<Filter>[])), isEmpty);
  });
}
