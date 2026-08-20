import 'package:flutter/services.dart';
import 'dart:convert';

class ResonerImageHelper {
  static Map<String, String>? _cache; // 파일명 -> asset 경로
  static Map<String, String>? _nameIndex; // 정규화된 이름 -> asset 경로

  static String _normalizeName(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'[\s.]+'), '');
  }

  static Future<void> load() async {
    if (_cache != null) return;
    try {
      final manifest =
          json.decode(await rootBundle.loadString('AssetManifest.json'))
              as Map<String, dynamic>;
      final cache = <String, String>{};
      final nameIndex = <String, String>{};
      for (final path in manifest.keys) {
        if (path.startsWith('assets/resoner/')) {
          final fileName = path.split('/').last;
          cache[fileName] = path;
          // 확장자 제거 후 소문자로 이름 인덱스 구성
          final key = _normalizeName(
            fileName.replaceFirst(RegExp(r'\.png$', caseSensitive: false), ''),
          );
          nameIndex[key] = path;
        }
      }
      _cache = cache;
      _nameIndex = nameIndex;
    } catch (e) {
      _cache = {};
      _nameIndex = {};
      print('ResonerImageHelper 로드 실패: $e');
    }
  }

  // imagefile 필드 값으로 직접 조회 (확장자 없으면 .png 자동 추가)
  static String? getPath(String? imageFile) {
    if (imageFile == null || imageFile.isEmpty) return null;
    final fileName = imageFile.contains('.') ? imageFile : '$imageFile.png';
    return _cache?[fileName];
  }

  // resoner_eng(영문 저자명)으로 fallback 조회
  // 예: "Maya Angelou" -> "angelou" -> assets/resoner/Angelou.png
  static String? getPathByEng(String? resonerEng) {
    if (resonerEng == null || resonerEng.isEmpty) return null;
    if (_nameIndex == null) return null;

    // 1. 전체 이름 정규화 매칭 (공백·마침표 제거)
    final normalized = _normalizeName(resonerEng);
    if (_nameIndex!.containsKey(normalized)) return _nameIndex![normalized];

    // 2. 성(last word) 매칭
    final lastName = _normalizeName(resonerEng.trim().split(' ').last);
    if (_nameIndex!.containsKey(lastName)) return _nameIndex![lastName];

    // 3. 이름 일부 포함 매칭
    for (final entry in _nameIndex!.entries) {
      if (entry.key.contains(lastName) || lastName.contains(entry.key)) {
        return entry.value;
      }
    }
    return null;
  }

  // 영문 저자명과 정확히 일치하는 자산을 저자의 대표 이미지로 선택한다.
  static String? _getCanonicalPathByEng(String? resonerEng) {
    if (resonerEng == null || resonerEng.isEmpty || _nameIndex == null) {
      return null;
    }

    final normalized = _normalizeName(resonerEng);
    final fullNamePath = _nameIndex![normalized];
    if (fullNamePath != null) return fullNamePath;

    final lastName = _normalizeName(resonerEng.trim().split(' ').last);
    return _nameIndex![lastName];
  }

  // 같은 저자는 항상 같은 대표 이미지를 사용하고, 없을 때만 imagefile을 사용한다.
  static String? resolve(String? imageFile, String? resonerEng) {
    return _getCanonicalPathByEng(resonerEng) ??
        getPath(imageFile) ??
        getPathByEng(resonerEng);
  }
}
