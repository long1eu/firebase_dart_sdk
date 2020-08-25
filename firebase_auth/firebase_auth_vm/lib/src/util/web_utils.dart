// File created by
// Lung Razvan <long1eu>
// on 08/12/2019

part of firebase_auth_vm;

String randomString(int length) {
  final Random random = Random();
  const int max = 0x7A - 0x61 + 1;
  return String.fromCharCodes(
      List<int>.generate(length, (_) => random.nextInt(max) + 0x61));
}
