import 'dart:math';

const _adjectives = [
  '따사로운',
  '포근한',
  '은은한',
  '잔잔한',
  '고요한',
  '맑은',
  '부드러운',
  '다정한',
  '평화로운',
  '아늑한',
  '소중한',
  '빛나는',
  '사랑스러운',
  '행복한',
  '설레는',
  '눈부신',
  '따뜻한',
  '싱그러운',
  '청명한',
  '봄날의',
];

const _nouns = [
  '햇살',
  '바람',
  '노을',
  '달빛',
  '별빛',
  '꽃잎',
  '이슬',
  '구름',
  '하늘',
  '새벽',
  '무지개',
  '숲속',
  '옹달샘',
  '미소',
  '여행자',
  '나비',
  '소나기',
  '풀잎',
  '동산',
  '오솔길',
];

/// deviceId의 hashCode를 seed로 사용하여 같은 기기는 항상 같은 닉네임 반환
String generateNickname(String deviceId) {
  final random = Random(deviceId.hashCode);
  final adj = _adjectives[random.nextInt(_adjectives.length)];
  final noun = _nouns[random.nextInt(_nouns.length)];
  final num = 1000 + random.nextInt(9000);
  return '$adj$noun$num';
}
