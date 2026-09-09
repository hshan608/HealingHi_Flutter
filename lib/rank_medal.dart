import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 공유 랭킹 1~3위 카드의 메달 아이콘(Figma Settings (Ranking) `Icon_Medal 1/Gold·Silver·Bronze`, 41×41).
///
/// 리본에 매달린 메달이 살짝 흔들리는 반복 애니메이션을 재생한다.
/// 회전 축은 리본 상단(top-center)이라 메달이 아래로 늘어진 채 좌우로 흔들리는 인상을 준다.
/// 접근성 설정으로 애니메이션이 꺼진 기기(`MediaQuery.disableAnimations`)에서는 정지 이미지를 그린다.
class AnimatedRankMedal extends StatefulWidget {
  const AnimatedRankMedal({
    super.key,
    required this.rank,
    this.size = 41,
    this.duration = const Duration(milliseconds: 1400),
  }) : assert(rank >= 1 && rank <= 3, 'rank must be 1..3');

  /// 1~3. `assets/{rank}_rank.png`를 그린다.
  final int rank;

  /// 정사각 한 변 길이. Figma 랭크 카드 기준 41.
  final double size;

  /// 왼쪽 끝에서 오른쪽 끝까지 한 번 흔들리는 시간.
  final Duration duration;

  /// 최대 기울기(라디안). 약 ±6도.
  static const double maxSwingAngle = 6 * math.pi / 180;

  @override
  State<AnimatedRankMedal> createState() => _AnimatedRankMedalState();
}

class _AnimatedRankMedalState extends State<AnimatedRankMedal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _angle;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _angle =
        Tween<double>(
          begin: -AnimatedRankMedal.maxSwingAngle,
          end: AnimatedRankMedal.maxSwingAngle,
        ).animate(
          CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
        );
    _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant AnimatedRankMedal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration) {
      _controller.duration = widget.duration;
      if (_controller.isAnimating) _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = Image.asset(
      'assets/${widget.rank}_rank.png',
      width: widget.size,
      height: widget.size,
      fit: BoxFit.contain,
    );

    if (MediaQuery.disableAnimationsOf(context)) {
      return SizedBox(width: widget.size, height: widget.size, child: image);
    }

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _angle,
        child: image,
        builder: (context, child) => Transform.rotate(
          angle: _angle.value,
          alignment: Alignment.topCenter,
          child: child,
        ),
      ),
    );
  }
}
