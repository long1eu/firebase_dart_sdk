// Two fixed 2048-bit RSA key pairs for the App Check tests: verifyToken refuses keys under 2048 bits, and
// generating such keys in Dart takes minutes. Test fixtures only; made with `openssl genrsa 2048`.

import 'support.dart';

/// Test key 1 (2048 bits).
final TestKey appCheckKey1 = TestKey.fixed(
  BigInt.parse(
    'e97fdfa158555b87cd8c46c584094ba768d45cb0148374bcc7acea3b907bfa85fb53904a3cb9223377ff944e8227983f'
    'dce65bbc962ee1e4a2e3169d12ae427757ae33b70fcad9c4a9fa5a1ccb96ad9266d0a71c3e7e28b785d6624011da38ac'
    'c326fe73e7dee0cef78f2c0641da35ea61dba1838e915a8aaf8a64dbfed8872f',
    radix: 16,
  ),
  BigInt.parse(
    'c8b30123216f02fadb468c28786eb20bb3ff8827f5d74f68a1d0a1ce204e0ca6e2cb8e5eaa2cda6742b9fee413b13eef'
    '4739fdf7b216f2e8fd9c801d097e69f4d2a9ab7f8995605cf7427633c50247f7752aa06046d27791a2e4a787ff164f9f'
    'd839c6ab4818191ce14171d372137d224da3084121115ff6d0d2dc68a10bd9ad',
    radix: 16,
  ),
);

/// Test key 2 (2048 bits).
final TestKey appCheckKey2 = TestKey.fixed(
  BigInt.parse(
    'fc4e90f7a564385dbf99b7490c5e3534648efcb31276cd678736558a068575d24011fae5294485c00f674c2e6e700624'
    '7e74b7215674dcce438f48c9b588fe0ded12bde5fb67d764d8d06f509fe4fd13a41cc8a04d56477394d2fb4422d5b479'
    'fed7204305380f6f5b4e4cffafe8e9b486bd22b1f4a4a05baadb622e85f73f0b',
    radix: 16,
  ),
  BigInt.parse(
    'c3bd279e2408d7d9113544fe8a216bd5d0c0a9e17d05f7fb05e714470135584e9ef64e883257bd468ba8670ebc24d8d8'
    '37ad5553af67c5b7803c3cbb6e2a37978a7b4e6c12ba9c43d51eac1ee95efa7177ed429a165d34bca907ae9080642746'
    '992d712830a831a01a8e4037d6885cb36d2fddfd2b50f9f9bc44287272381de3',
    radix: 16,
  ),
);
