import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// 기준 기기 폭 대비 비율 스케일.
///
/// 화면 코드는 Figma(440×956) px 값을 그대로 쓰고, 레이아웃 검수는 Pixel 9 에뮬레이터
/// (1080×2424 @ 420dpi = 411.4×923.4dp)에서 했다. 이 위젯이 앱 루트(`MaterialApp.builder`)
/// 에서 실제 기기 폭 ÷ [designWidth] 배율로 전체 트리를 확대·축소해, 어떤 기기에서도
/// 검수 기기와 같은 비율로 보이게 한다. 개별 위젯이 `.w` / `.sp` 같은 변환을 붙일 필요가 없다.
/// 기준 기기에서는 배율이 정확히 1.0이 되어 변환 없이 그대로 그린다.
///
/// 동작 방식
/// 1. 기기 짧은 변(세로 모드에서는 폭)을 [designWidth]로 나눠 배율을 구한다.
///    극단적인 기기(구형 소형 폰, 태블릿)에서는 [minScale]~[maxScale]로 제한하고
///    남는 공간은 기존처럼 `Expanded` 등 유연 레이아웃이 채운다.
/// 2. 자식은 (기기 크기 ÷ 배율)의 논리 크기로 레이아웃되고 `Transform.scale`로 그려진다.
///    히트 테스트도 함께 변환되므로 터치 위치가 어긋나지 않는다.
/// 3. `MediaQuery`의 size / padding / viewInsets / viewPadding를 배율로 나눠 덮어쓴다.
///    `SafeArea`, 키보드 인셋, `MediaQuery.sizeOf` 등이 스케일된 좌표계에서 정확히 맞는다.
///    `devicePixelRatio`는 배율을 곱해 실제 물리 픽셀 밀도를 유지한다.
///
/// 스케일에서 빼야 하는 것(광고 배너처럼 실제 px 크기가 고정돼야 하는 위젯)은
/// [AppScale.unscaled]로 감싼다.
class AppScale extends StatelessWidget {
  const AppScale({
    super.key,
    required this.child,
    this.designWidth = referenceWidth,
    this.minScale = 0.7,
    this.maxScale = 1.4,
  });

  /// 레이아웃 검수 기준 기기(Pixel 9 에뮬레이터)의 논리 폭.
  /// 1080px ÷ (420dpi / 160) 로 계산해 Flutter가 보고하는 값과 정확히 일치시킨다.
  static const double referenceWidth = 1080 / 2.625;

  final Widget child;

  /// 배율 1.0이 되는 기준 폭(논리 px)
  final double designWidth;
  final double minScale;
  final double maxScale;

  /// 현재 적용된 배율. [AppScale] 바깥이면 1.0
  static double of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_AppScaleScope>();
    return scope?.scale ?? 1.0;
  }

  /// [size](실제 논리 px) 크기를 그대로 유지해야 하는 위젯을 스케일에서 제외한다.
  ///
  /// 바깥에서는 `size ÷ 배율`만큼 공간을 차지하고, 안쪽 자식은 역배율로 그려져
  /// 화면에는 정확히 [size]로 보인다. AdMob 배너 등 크기 규격이 있는 위젯에 쓴다.
  static Widget unscaled(
    BuildContext context, {
    required Size size,
    required Widget child,
  }) {
    final scale = AppScale.of(context);
    if (scale == 1.0) {
      return SizedBox.fromSize(size: size, child: child);
    }
    // OverflowBox를 Transform 바깥에 두어 Transform 자체가 [size] 크기를 갖게 한다.
    // 반대로 두면 Transform의 히트 테스트 범위가 축소된 박스에 묶여 가장자리 터치가 빠진다.
    return SizedBox(
      width: size.width / scale,
      height: size.height / scale,
      child: OverflowBox(
        alignment: Alignment.topLeft,
        minWidth: 0,
        maxWidth: double.infinity,
        minHeight: 0,
        maxHeight: double.infinity,
        child: Transform.scale(
          scale: 1 / scale,
          alignment: Alignment.topLeft,
          child: SizedBox.fromSize(size: size, child: child),
        ),
      ),
    );
  }

  double _scaleFor(Size size) {
    if (size.isEmpty || !size.width.isFinite || !size.height.isFinite) {
      return 1.0;
    }
    // 가로 모드·태블릿에서도 글자가 과도하게 커지지 않도록 짧은 변을 기준으로 삼는다.
    final base = math.min(size.width, size.height);
    return (base / designWidth).clamp(minScale, maxScale);
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final scale = _scaleFor(mediaQuery.size);
    if (scale == 1.0) {
      return _AppScaleScope(scale: 1.0, child: child);
    }

    final logicalSize = Size(
      mediaQuery.size.width / scale,
      mediaQuery.size.height / scale,
    );

    return _AppScaleScope(
      scale: scale,
      child: MediaQuery(
        data: mediaQuery.copyWith(
          size: logicalSize,
          devicePixelRatio: mediaQuery.devicePixelRatio * scale,
          padding: mediaQuery.padding / scale,
          viewPadding: mediaQuery.viewPadding / scale,
          viewInsets: mediaQuery.viewInsets / scale,
          systemGestureInsets: mediaQuery.systemGestureInsets / scale,
        ),
        // OverflowBox(기기 크기) → Transform(논리 크기) 순서여야 화면 전체가 히트 테스트된다.
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: 0,
          maxWidth: double.infinity,
          minHeight: 0,
          maxHeight: double.infinity,
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.topLeft,
            child: SizedBox.fromSize(size: logicalSize, child: child),
          ),
        ),
      ),
    );
  }
}

class _AppScaleScope extends InheritedWidget {
  const _AppScaleScope({required this.scale, required super.child});

  final double scale;

  @override
  bool updateShouldNotify(_AppScaleScope oldWidget) => scale != oldWidget.scale;
}
