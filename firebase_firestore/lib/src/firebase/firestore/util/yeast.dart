/// A Dart implementation of yeast. https://github.com/unshiftio/yeast
class Yeast {
  static List<int> alphabet =
      '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-_'
          .codeUnits;

  static Map<int, int> map = <int, int>{};

  static int length = 64;

  static int seed = 0;

  static String prev;

  Yeast();

  static void init() {
    map.clear();
    for (int i = 0; i < length; i++) {
      map[alphabet[i]] = i;
    }
  }

  static String encode(int num) {
    final List<int> encoded = <int>[];

    do {
      encoded.insert(0, alphabet[num.remainder(length).toInt()]);
      num = (num / length).floor();
    } while (num > 0);

    return String.fromCharCodes(encoded);
  }

  static int decode(String str) {
    init();
    int decoded = 0;

    for (int i = 0; i < str.length; i++) {
      decoded = decoded * length + map[str.codeUnitAt(i)];
    }

    return decoded;
  }

  static String yeast() {
    final String now = encode(DateTime.now().millisecondsSinceEpoch);

    if (now != prev) {
      seed = 0;
      prev = now;
      return now;
    }

    return '$now.${encode(seed++)}';
  }
}
