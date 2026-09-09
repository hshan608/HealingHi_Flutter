import 'package:flutter_test/flutter_test.dart';
import 'package:healing_hi/image_mime.dart';

void main() {
  test('jpg 확장자는 표준 MIME image/jpeg로 변환된다', () {
    // 버킷 allowed_mime_types에 image/jpg는 없으므로 image/jpeg여야 업로드가 통과한다.
    expect(ImageMime.fromPath('/cache/image_cropper_123.jpg'), 'image/jpeg');
    expect(ImageMime.fromPath(r'C:	mp\PHOTO.JPG'), 'image/jpeg');
    expect(ImageMime.fromPath('a.jpeg'), 'image/jpeg');
  });

  test('나머지 허용 확장자는 각자의 MIME으로 변환된다', () {
    expect(ImageMime.fromPath('a.png'), 'image/png');
    expect(ImageMime.fromPath('a.webp'), 'image/webp');
    expect(ImageMime.fromPath('a.heic'), 'image/heic');
    expect(ImageMime.fromPath('a.HEIF'), 'image/heif');
  });

  test('확장자가 없거나 미지원이면 jpg/image/jpeg로 처리한다', () {
    expect(ImageMime.extensionOf('/cache/noext'), 'jpg');
    expect(ImageMime.extensionOf('/cache.dir/noext'), 'jpg');
    expect(ImageMime.fromExtension('bmp'), 'image/jpeg');
  });

  test('확장자는 소문자로 정규화된다', () {
    expect(ImageMime.extensionOf('IMG_0001.PNG'), 'png');
  });
}
