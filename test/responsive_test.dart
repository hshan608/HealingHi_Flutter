import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healing_hi/responsive.dart';

void main() {
  // 360×800(일반 안드로이드 폰)에서는 기준 폭 411.4 대비 배율 360/411.4 = 0.875가 적용되어
  // 자식은 항상 기준 폭 411.4로 레이아웃되고 화면에는 축소되어 그려진다.
  testWidgets('AppScale은 자식을 기준 폭으로 레이아웃하고 화면 폭에 맞춰 그린다', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    late Size logicalSize;
    late double scale;
    late EdgeInsets padding;
    final probeKey = GlobalKey();

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(360, 800),
          padding: EdgeInsets.only(top: 44, bottom: 22),
        ),
        child: AppScale(
          child: Builder(
            builder: (context) {
              logicalSize = MediaQuery.sizeOf(context);
              padding = MediaQuery.paddingOf(context);
              scale = AppScale.of(context);
              return Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  key: probeKey,
                  width: AppScale.referenceWidth,
                  height: 100,
                ),
              );
            },
          ),
        ),
      ),
    );

    const expectedScale = 360 / AppScale.referenceWidth;
    expect(scale, closeTo(expectedScale, 1e-9));
    expect(logicalSize.width, closeTo(AppScale.referenceWidth, 1e-9));
    expect(logicalSize.height, closeTo(800 / expectedScale, 1e-9));
    // SafeArea 인셋도 같은 배율로 나눠져 스케일된 좌표계에서 맞아야 한다.
    expect(padding.top, closeTo(44 / expectedScale, 1e-9));
    expect(padding.bottom, closeTo(22 / expectedScale, 1e-9));

    // 논리 폭 411.4인 자식이 실제 화면에서는 360폭으로 그려진다.
    final rect = tester.getRect(find.byKey(probeKey));
    expect(rect.left, closeTo(0, 1e-6));
    expect(rect.width, closeTo(360, 1e-6));
    expect(rect.height, closeTo(100 * expectedScale, 1e-6));
  });

  testWidgets('AppScale.unscaled는 실제 px 크기를 그대로 유지한다', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final adKey = GlobalKey();

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(360, 800)),
        child: AppScale(
          child: Builder(
            builder: (context) => Align(
              alignment: Alignment.topLeft,
              child: AppScale.unscaled(
                context,
                size: const Size(320, 50),
                child: SizedBox(key: adKey),
              ),
            ),
          ),
        ),
      ),
    );

    final rect = tester.getRect(find.byKey(adKey));
    expect(rect.width, closeTo(320, 1e-6));
    expect(rect.height, closeTo(50, 1e-6));
  });

  testWidgets('AppScale은 히트 테스트를 스케일된 좌표로 변환한다', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    var tapped = 0;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(360, 800)),
        child: AppScale(
          child: Align(
            alignment: Alignment.bottomRight,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => tapped++,
              child: const SizedBox(width: 100, height: 100),
            ),
          ),
        ),
      ),
    );

    // 논리 좌표 우하단 100×100 영역은 화면에서 약 88×88로 축소되어 우하단에 놓인다.
    await tester.tapAt(const Offset(359, 799));
    expect(tapped, 1);
    await tester.tapAt(const Offset(200, 400));
    expect(tapped, 1);
  });

  testWidgets('기준 기기(Pixel 9, 411.4dp)에서는 배율 1.0으로 그대로 그린다', (tester) async {
    const referenceSize = Size(1080 / 2.625, 2424 / 2.625);
    tester.view.physicalSize = const Size(1080, 2424);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);

    late double scale;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: referenceSize),
        child: AppScale(
          child: Builder(
            builder: (context) {
              scale = AppScale.of(context);
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );

    expect(scale, 1.0);
    expect(find.byType(Transform), findsNothing);
  });
}
