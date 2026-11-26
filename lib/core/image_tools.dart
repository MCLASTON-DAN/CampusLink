import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;

/// Lets the person choose a photo, then makes it small enough to upload fast:
/// longest side at most 1600 px, JPEG, under [maxBytes]. Returns null if they
/// cancel. Throws a readable message if the file is not a picture.
Future<Uint8List?> pickAndShrinkImage({int maxBytes = 900 * 1024, int maxSide = 1600}) async {
  final res = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
  final bytes = res?.files.single.bytes;
  if (bytes == null) return null;
  return shrinkImage(bytes, maxBytes: maxBytes, maxSide: maxSide);
}

Uint8List shrinkImage(Uint8List bytes, {int maxBytes = 900 * 1024, int maxSide = 1600}) {
  var image = img.decodeImage(bytes);
  if (image == null) throw const FormatException('That file is not a picture we can read');
  image = img.bakeOrientation(image); // keep phone photos the right way up
  var side = maxSide;
  while (true) {
    final resized = (image.width > side || image.height > side)
        ? img.copyResize(image, width: image.width >= image.height ? side : null, height: image.height > image.width ? side : null)
        : image;
    for (final q in [85, 75, 65, 55]) {
      final out = img.encodeJpg(resized, quality: q);
      if (out.length <= maxBytes) return out;
    }
    if (side <= (maxSide < 480 ? maxSide ~/ 2 : 480)) throw const FormatException('Could not make this picture small enough');
    side = (side * 0.75).round();
  }
}
