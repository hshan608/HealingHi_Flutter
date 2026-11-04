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

/// 공유 랭킹 1~3위 사용자의 프로필 사진을 둘러싸는 반짝이 효과
/// (Figma Settings `star_{n}`·`mist_{n}` GIF, 프로필 사진 위 숨김 레이어).
///
/// 큰 네 갈래 반짝이(star)와 아래쪽 작은 반짝이(mist)를 겹쳐 그린다.
/// 1위 무지개, 2위 금색, 3위 은색이며, 둘 다 가운데가 비어 있어 사진 중심에 맞춰 놓는다.
/// star 원본 GIF는 검정 배경 위에 그린 빛 번짐이 검정 테두리로 남아 있어, 어두운 가장자리를
/// 같은 색조의 반투명으로 바꾼 애니메이션 WebP를 쓴다(GIF는 반투명을 담지 못한다).
/// 둘 다 무한 반복 애니메이션이라 컨트롤러가 없다. 접근성 설정으로 애니메이션이 꺼진
/// 기기(`MediaQuery.disableAnimations`)에서는 장식이므로 그리지 않는다.
class RankSparkle extends StatelessWidget {
  const RankSparkle({super.key, required this.rank, this.width = 210})
    : assert(rank >= 1 && rank <= 3, 'rank must be 1..3');

  /// 1~3. `assets/{rank}_rank_star.webp`와 `assets/{rank}_rank_mist.gif`를 그린다.
  final int rank;

  /// 효과 영역 폭. Figma 배치 크기(194~218) 중간값. 높이는 GIF 원본 비율을 따른다.
  final double width;

  /// GIF 원본 크기 250×220의 가로세로 비.
  static const double aspectRatio = 250 / 220;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return const SizedBox.shrink();

    return IgnorePointer(
      child: SizedBox(
        width: width,
        height: width / aspectRatio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset('assets/${rank}_rank_mist.gif', fit: BoxFit.contain),
            Image.asset('assets/${rank}_rank_star.webp', fit: BoxFit.contain),
          ],
        ),
      ),
    );
  }
}
