import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healing_hi/rank_medal.dart';
import 'package:healing_hi/resoner_image_helper.dart';
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

    expect(find.text('당신의 하루에 머무는 한마디'), findsOneWidget);
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
                  stepIndex: 2,
                  onNext: () {},
                  onSkip: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('함께 나누는 사람들을 만나보세요.'), findsOneWidget);
    expect(find.text('확인'), findsOneWidget);
  });

  testWidgets('튜토리얼 강조 영역은 실제 위젯 위치를 따라간다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned(
                left: 80,
                top: 120,
                width: 240,
                height: 56,
                child: SizedBox(key: TutorialTargets.searchField),
              ),
              TutorialOverlay(
                section: TutorialSection.search,
                stepIndex: 1,
                onNext: () {},
                onSkip: () {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 150));

    final targetBorder = find.byWidgetPredicate((widget) {
      if (widget is! DecoratedBox) return false;
      final decoration = widget.decoration;
      return decoration is BoxDecoration && decoration.border != null;
    });

    expect(targetBorder, findsOneWidget);
    // 검색 2단계는 입력 바 둘레에 4px 여백을 두고 강조한다.
    expect(
      tester.getRect(targetBorder),
      const Rect.fromLTWH(80, 120, 240, 56).inflate(4),
    );
  });

  testWidgets('홈 튜토리얼의 하트·공유 강조 영역은 같은 크기로 위젯 중심에 맞춘다', (tester) async {
    Future<Rect> highlightRectFor(int stepIndex) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                // 실제 홈 카드와 같은 크기: 하트 23×23, 공유 18×20
                Positioned(
                  left: 200,
                  top: 300,
                  width: 23,
                  height: 23,
                  child: SizedBox(key: TutorialTargets.homeLike),
                ),
                Positioned(
                  left: 300,
                  top: 302,
                  width: 18,
                  height: 20,
                  child: SizedBox(key: TutorialTargets.homeShare),
                ),
                TutorialOverlay(
                  section: TutorialSection.home,
                  stepIndex: stepIndex,
                  onNext: () {},
                  onSkip: () {},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 150));

      final targetBorder = find.byWidgetPredicate((widget) {
        if (widget is! DecoratedBox) return false;
        final decoration = widget.decoration;
        return decoration is BoxDecoration && decoration.border != null;
      });
      expect(targetBorder, findsOneWidget);
      return tester.getRect(targetBorder);
    }

    final likeRect = await highlightRectFor(1);
    final shareRect = await highlightRectFor(2);

    expect(likeRect.size, shareRect.size);
    expect(likeRect.center, const Offset(200 + 23 / 2, 300 + 23 / 2));
    expect(shareRect.center, const Offset(300 + 18 / 2, 302 + 20 / 2));
  });

  testWidgets('보관함 탭 강조 영역은 하단 바 위로 침범하지 않는다', (tester) async {
    const barTop = 520.0;
    const barHeight = 80.0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned(
                left: 0,
                top: barTop,
                width: 400,
                height: barHeight,
                child: Container(
                  key: TutorialTargets.bottomNavBar,
                  padding: const EdgeInsets.fromLTRB(11, 0, 11, 34),
                  child: Row(
                    children: [
                      const Expanded(child: SizedBox()),
                      const Expanded(child: SizedBox()),
                      // 실제 탭은 Column이 바 콘텐츠 높이(46)를 모두 채운다.
                      Expanded(
                        child: SizedBox.expand(
                          key: TutorialTargets.bookmarkTab,
                        ),
                      ),
                      const Expanded(child: SizedBox()),
                    ],
                  ),
                ),
              ),
              TutorialOverlay(
                section: TutorialSection.bookmarks,
                stepIndex: 0,
                onNext: () {},
                onSkip: () {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 150));

    final targetBorder = find.byWidgetPredicate((widget) {
      if (widget is! DecoratedBox) return false;
      final decoration = widget.decoration;
      return decoration is BoxDecoration && decoration.border != null;
    });
    expect(targetBorder, findsOneWidget);

    final highlight = tester.getRect(targetBorder);
    final tab = tester.getRect(find.byKey(TutorialTargets.bookmarkTab));
    // 위쪽은 바 상단에 맞춰지고, 아래·좌우 패딩은 바 안에서 유지된다.
    expect(highlight.top, barTop);
    expect(highlight.bottom, tab.bottom + 8);
    expect(highlight.left, tab.left - 8);
    expect(highlight.right, tab.right + 8);
    expect(highlight.bottom, lessThanOrEqualTo(barTop + barHeight));
  });

  testWidgets('프로필 튜토리얼의 건너뛰기 버튼은 강조 영역 위 최상위에 놓인다', (tester) async {
    var skipCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              // 프로필 제목 행처럼 화면 상단 전체 폭을 차지하는 강조 대상.
              Positioned(
                left: 0,
                top: 0,
                width: 800,
                height: 120,
                child: SizedBox(key: TutorialTargets.profileTitle),
              ),
              TutorialOverlay(
                section: TutorialSection.profile,
                stepIndex: 0,
                onNext: () {},
                onSkip: () => skipCount++,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 150));

    final skipButton = find.byKey(const ValueKey('tutorial_skip_button'));
    expect(skipButton, findsOneWidget);

    // 버튼이 강조 영역과 겹치는 상황을 재현한다.
    final highlight = tester.getRect(
      find.byWidgetPredicate((widget) {
        if (widget is! DecoratedBox) return false;
        final decoration = widget.decoration;
        return decoration is BoxDecoration && decoration.border != null;
      }),
    );
    expect(highlight.overlaps(tester.getRect(skipButton)), isTrue);

    // 오버레이 Stack의 마지막(최상위) 자식이 건너뛰기 버튼이어야 한다.
    final overlayStack = tester.widget<Stack>(
      find.descendant(
        of: find.byType(TutorialOverlay),
        matching: find.byType(Stack),
      ),
    );
    final topChild = overlayStack.children.last;
    expect(
      find.descendant(of: find.byWidget(topChild), matching: skipButton),
      findsOneWidget,
    );

    await tester.tap(skipButton);
    await tester.pump();
    expect(skipCount, 1);
  });

  testWidgets('랭킹 1~3위 메달은 리본 상단을 축으로 흔들리는 애니메이션을 재생한다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: AnimatedRankMedal(rank: 1))),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as AssetImage).assetName, 'assets/1_rank.png');
    expect(tester.getSize(find.byType(AnimatedRankMedal)), const Size(41, 41));

    // MaterialApp 내부에도 Transform이 있으므로 메달 위젯 하위로 한정한다.
    final medalTransform = find.descendant(
      of: find.byType(AnimatedRankMedal),
      matching: find.byType(Transform),
    );
    Transform currentTransform() => tester.widget<Transform>(medalTransform);
    expect(currentTransform().alignment, Alignment.topCenter);

    final first = currentTransform().transform;
    await tester.pump(const Duration(milliseconds: 700));
    final second = currentTransform().transform;
    expect(second, isNot(equals(first)));

    // 반복 애니메이션이므로 한 주기(1400ms) 뒤에는 같은 각도로 돌아온다.
    await tester.pump(const Duration(milliseconds: 1400));
    expect(currentTransform().transform, second);
  });

  testWidgets('애니메이션이 비활성화된 기기에서는 메달을 정지 이미지로 그린다', (tester) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          home: Scaffold(body: Center(child: AnimatedRankMedal(rank: 3))),
        ),
      ),
    );

    expect(
      find.descendant(
        of: find.byType(AnimatedRankMedal),
        matching: find.byType(Transform),
      ),
      findsNothing,
    );
    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as AssetImage).assetName, 'assets/3_rank.png');
  });

  testWidgets('같은 저자의 이미지 별칭은 하나의 대표 이미지로 통일된다', (tester) async {
    await ResonerImageHelper.load();

    const saintExuperyImage = 'assets/resoner/Saint-Exupéry.png';
    expect(
      ResonerImageHelper.resolve('Exupery', 'Antoine de Saint-Exupéry'),
      saintExuperyImage,
    );
    expect(
      ResonerImageHelper.resolve('Saint-Exupéry', 'Antoine de Saint-Exupéry'),
      saintExuperyImage,
    );

    const sunTzuImage = 'assets/resoner/Suntzu.png';
    expect(ResonerImageHelper.resolve('Suntzu', 'Sun Tzu'), sunTzuImage);
    expect(ResonerImageHelper.resolve('Tzu', 'Sun Tzu'), sunTzuImage);
  });
}
