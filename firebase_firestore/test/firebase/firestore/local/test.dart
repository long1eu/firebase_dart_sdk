// File created by
// Lung Razvan <long1eu>
// on 30/09/2018

void main() {
  final Set<int> documentKeys = Set.from(List<int>.generate(100, (i) => i));

  const int chunkSize = 9;
  final int len = documentKeys.length;
  final Set<int> uniqueBatchIds = Set<int>();

  for (int i = 0; i < len; i += chunkSize) {
    final List<String> args = <String>[];
    args.add('0');

    final String result = documentKeys
        .map((int it) => '$it'.padLeft(2, ' '))
        .skip(i)
        .take(chunkSize)
        .join(', ');

    print(result);
  }
}
