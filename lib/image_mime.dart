/// 업로드 이미지의 확장자 ↔ MIME 타입 변환.
///
/// Supabase `avatars` 버킷은 `allowed_mime_types`로 표준 MIME만 허용한다
/// (`image/jpeg`, `image/png`, `image/webp`, `image/heic`, `image/heif`).
/// 확장자를 그대로 `image/$ext`로 붙이면 `.jpg` 파일이 `image/jpg`가 되어
/// 415(invalid_mime_type)로 거절되므로 반드시 이 헬퍼를 거쳐야 한다.
class ImageMime {
  ImageMime._();

  static const Map<String, String> _byExtension = <String, String>{
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
    'heic': 'image/heic',
    'heif': 'image/heif',
  };

  /// 경로에서 소문자 확장자를 뽑는다. 확장자가 없으면 `jpg`로 본다.
  static String extensionOf(String path) {
    final fileName = path.split(RegExp(r'[\/]')).last;
    final dot = fileName.lastIndexOf('.');
    if (dot <= 0 || dot == fileName.length - 1) return 'jpg';
    return fileName.substring(dot + 1).toLowerCase();
  }

  /// 확장자에 대응하는 표준 MIME 타입. 미지원 확장자는 `image/jpeg`로 보낸다.
  static String fromExtension(String extension) =>
      _byExtension[extension.toLowerCase()] ?? 'image/jpeg';

  /// 경로에서 바로 MIME 타입을 얻는다.
  static String fromPath(String path) => fromExtension(extensionOf(path));
}
