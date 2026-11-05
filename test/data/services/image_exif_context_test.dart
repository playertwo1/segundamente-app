import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image/image.dart' show IfdValueRational;
import 'package:image/src/util/rational.dart' show Rational;
import 'package:memex/data/services/image_exif_context.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late String path;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('exif_ctx_');
    final image = img.Image(width: 8, height: 8);
    image.exif.exifIfd['DateTimeOriginal'] = '2026:11:05 10:00:00';
    // Cameras write GPS as degrees/minutes/seconds rationals.
    image.exif.gpsIfd.data[0x0002] = IfdValueRational.list(
        [Rational(23, 1), Rational(30, 1), Rational(0, 1)]);
    image.exif.gpsIfd.gpsLatitudeRef = 'S';
    image.exif.gpsIfd.data[0x0004] = IfdValueRational.list(
        [Rational(46, 1), Rational(36, 1), Rational(0, 1)]);
    image.exif.gpsIfd.gpsLongitudeRef = 'W';
    path = '${dir.path}/photo.jpg';
    File(path).writeAsBytesSync(img.encodeJpg(image));
  });

  tearDown(() => dir.deleteSync(recursive: true));

  test('with the location switch off a photo reports its time but no GPS',
      () async {
    final info = await buildImageExifInfo('u', path);

    expect(info, isNotNull);
    expect(info, contains('2026'));
    expect(info, isNot(contains('23.5')));
    expect(info, isNot(contains('46.6')));
    expect(info!.toLowerCase(), isNot(contains('gps')));
  });
}
