/// 화면에 표시하는 문장의 곧은 큰따옴표(")를 둥근 따옴표(“ ”)로 바꾼다.
///
/// 짝을 이루는 따옴표는 앞에 오는 문자를 기준으로 여는지 닫는지 판정한다.
/// 문장 시작·공백·여는 괄호 뒤는 여는 따옴표(“), 그 밖은 닫는 따옴표(”)다.
/// 검색·비교에는 원문을 그대로 쓰고, 표시 직전에만 이 함수를 거친다.
String toTypographicQuotes(String input) {
  if (!input.contains('"')) return input;

  final buffer = StringBuffer();
  var open = false;
  for (var i = 0; i < input.length; i++) {
    final char = input[i];
    if (char != '"') {
      buffer.write(char);
      continue;
    }
    final previous = i == 0 ? '' : input[i - 1];
    final startsQuote = !open && _isOpeningContext(previous);
    if (startsQuote) {
      buffer.write('“'); // “
      open = true;
    } else {
      buffer.write('”'); // ”
      open = false;
    }
  }
  return buffer.toString();
}

bool _isOpeningContext(String previous) {
  if (previous.isEmpty) return true;
  return previous.trim().isEmpty || '([{<‘“'.contains(previous);
}
