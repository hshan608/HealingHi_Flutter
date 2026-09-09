import 'package:flutter_test/flutter_test.dart';
import 'package:healing_hi/typographic_quotes.dart';

void main() {
  test('곧은 큰따옴표 한 쌍을 둥근 따옴표로 바꾼다', () {
    expect(toTypographicQuotes('"삶은 여행이다"'), '“삶은 여행이다”');
  });

  test('문장 안의 인용구도 여닫는 방향을 구분한다', () {
    expect(
      toTypographicQuotes('그는 "괜찮다"고 말했다. 그리고 "다시" 웃었다.'),
      '그는 “괜찮다”고 말했다. 그리고 “다시” 웃었다.',
    );
  });

  test('줄바꿈과 괄호 뒤의 따옴표는 여는 따옴표다', () {
    expect(toTypographicQuotes('첫 줄\n"둘째 줄" ("셋째")'), '첫 줄\n“둘째 줄” (“셋째”)');
  });

  test('따옴표가 없으면 원문을 그대로 돌려준다', () {
    const text = '따옴표 없는 문장';
    expect(toTypographicQuotes(text), same(text));
  });

  test('이미 둥근 따옴표인 문장은 바꾸지 않는다', () {
    expect(toTypographicQuotes('“이미” 변환됨'), '“이미” 변환됨');
  });
}
