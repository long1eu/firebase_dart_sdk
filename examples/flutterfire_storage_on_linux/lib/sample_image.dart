import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

/// A PNG of [size] by [size] pixels with a random colour per 16 pixel block and
/// noise inside it, so that it does not compress away: with the default size it
/// is about 1 MB, which is several chunks of a resumable upload.
Future<Uint8List> sampleImage({int size = 512, Random? random}) async {
  final Random rng = random ?? Random();
  final Uint8List pixels = Uint8List(size * size * 4);
  final List<int> base = List<int>.generate(3, (_) => rng.nextInt(256));
  for (int y = 0; y < size; y++) {
    for (int x = 0; x < size; x++) {
      final int offset = (y * size + x) * 4;
      for (int channel = 0; channel < 3; channel++) {
        pixels[offset + channel] =
            (base[channel] + (x ~/ 16) * 3 + (y ~/ 16) * 5 + rng.nextInt(64)) %
            256;
      }
      pixels[offset + 3] = 255;
    }
  }
  final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromUint8List(
    pixels,
  );
  final ui.ImageDescriptor descriptor = ui.ImageDescriptor.raw(
    buffer,
    width: size,
    height: size,
    pixelFormat: ui.PixelFormat.rgba8888,
  );
  final ui.Codec codec = await descriptor.instantiateCodec();
  final ui.Image image = (await codec.getNextFrame()).image;
  final ByteData? png = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  codec.dispose();
  descriptor.dispose();
  buffer.dispose();
  return png!.buffer.asUint8List();
}
