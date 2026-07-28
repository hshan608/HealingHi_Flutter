import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healing_hi/tutorial.dart';

void main() {
  testWidgets('홈 튜토리얼이 단계 정보와 이동 버튼을 표시한다', (tester) async {
    var nextCount = 0;
    var skipCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox.expand(
            child: Stack(
              children: [
                const Positioned.fill(
                  child: ColoredBox(color: Color(0xFFDDE7DE)),
                ),
                TutorialOverlay(
                  section: TutorialSection.home,
                  stepIndex: 0,
                  onNext: () => nextCount++,
                  onSkip: () => skipCount++,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('힐링 하이의 명언 카드'), findsOneWidget);
    expect(find.text('다음'), findsOneWidget);
    expect(find.text('건너뛰기'), findsOneWidget);

    await tester.tap(find.text('다음'));
    await tester.tap(find.text('건너뛰기'));

    expect(nextCount, 1);
    expect(skipCount, 1);
  });

  testWidgets('마지막 단계는 확인 버튼을 표시한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox.expand(
            child: Stack(
              children: [
                const Positioned.fill(child: SizedBox.expand()),
                TutorialOverlay(
                  section: TutorialSection.profile,
                  stepIndex: 1,
                  onNext: () {},
                  onSkip: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('나의 공유 활동을 확인해요'), findsOneWidget);
    expect(find.text('확인'), findsOneWidget);
  });
}
