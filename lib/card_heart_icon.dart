import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// 명언 카드의 하트 아이콘(Figma Like Toggle 23×19).
///
/// 보관(활성) 전환 효과는 `LikeButton`이 그리지만 해제 쪽은 아무 효과 없이 바로
/// 바뀌므로, 활성 → 비활성으로 바뀔 때 살짝 줄었다가 되돌아오며 색이 회색으로
/// 빠지는 해제 애니메이션을 여기서 재생한다. `LikeButton.likeBuilder` 안에 두면
/// 같은 자리의 State가 유지되어 `didUpdateWidget`에서 전환을 감지할 수 있다.
///
/// [identity]가 함께 바뀐 경우(목록 갱신으로 다른 명언이 같은 자리에 온 경우)는
/// 사용자가 해제한 것이 아니므로 재생하지 않는다.
class CardHeartIcon extends StatefulWidget {
  const CardHeartIcon({super.key, required this.isLiked, this.identity});

  /// Figma Like Toggle 활성 색.
  static const Color activeColor = Color(0xFFFF8788);

  /// Figma Dislike Toggle 비활성 색(SVG 원본 색과 같다).
  static const Color inactiveColor = Color(0xFF757575);

  static const Duration unlikeDuration = Duration(milliseconds: 380);

  final bool isLiked;
  final Object? identity;

  @override
  State<CardHeartIcon> createState() => _CardHeartIconState();
}

class _CardHeartIconState extends State<CardHeartIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    // 완료 상태(1.0)에서 시작해 처음 그릴 때는 아무 효과도 보이지 않게 한다.
    _controller = AnimationController(
      vsync: this,
      duration: CardHeartIcon.unlikeDuration,
      value: 1,
    );
    // 0.72배로 움츠렸다가 1.08배로 살짝 튀어 오른 뒤 원래 크기로 돌아온다.
    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: 0.72,
        ).chain(CurveTween(curve: Curves.easeIn)),
        weight: 35,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 0.72,
          end: 1.08,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.08,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 25,
      ),
    ]).animate(_controller);
    // 움츠러드는 동안 분홍 → 회색으로 바뀐다.
    _fade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.45, curve: Curves.easeOut),
    );
  }

  @override
  void didUpdateWidget(covariant CardHeartIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isLiked) {
      // 해제 애니메이션 도중 다시 보관하면 즉시 멈추고 활성 상태를 보여준다.
      if (_controller.isAnimating) _controller.value = 1;
      return;
    }
    final unliked = oldWidget.isLiked && oldWidget.identity == widget.identity;
    if (unliked && !MediaQuery.disableAnimationsOf(context)) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final animating = _controller.isAnimating;
        final Color? color = widget.isLiked
            ? CardHeartIcon.activeColor
            : animating
            ? Color.lerp(
                CardHeartIcon.activeColor,
                CardHeartIcon.inactiveColor,
                _fade.value,
              )
            : null; // 비활성 정지 상태는 SVG 원본 색(#757575)을 그대로 쓴다.
        return Transform.scale(
          scale: animating ? _scale.value : 1.0,
          child: SvgPicture.asset(
            'assets/icon/figma_card_heart.svg',
            width: 23,
            height: 19,
            colorFilter: color == null
                ? null
                : ColorFilter.mode(color, BlendMode.srcIn),
          ),
        );
      },
    );
  }
}
