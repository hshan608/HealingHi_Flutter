import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'installation_identity.dart';
import 'nickname_generator.dart';

enum TutorialSection {
  home('home_v1'),
  search('search_v1'),
  bookmarks('bookmarks_v1'),
  profile('profile_v1');

  const TutorialSection(this.storageKey);

  final String storageKey;
}

class TutorialTargets {
  TutorialTargets._();

  static final homeCard = GlobalKey(debugLabel: 'tutorial_home_card');
  static final homeLike = GlobalKey(debugLabel: 'tutorial_home_like');
  static final homeShare = GlobalKey(debugLabel: 'tutorial_home_share');
  static final searchTabs = GlobalKey(debugLabel: 'tutorial_search_tabs');
  static final searchField = GlobalKey(debugLabel: 'tutorial_search_field');
  static final bookmarkTab = GlobalKey(debugLabel: 'tutorial_bookmark_tab');
  // 하단 바 전체. 탭 강조 영역이 바 밖(본문 쪽)으로 번지지 않도록 경계로 쓴다.
  static final bottomNavBar = GlobalKey(debugLabel: 'tutorial_bottom_nav_bar');
  static final bookmarkLike = GlobalKey(debugLabel: 'tutorial_bookmark_like');
  static final profileTitle = GlobalKey(debugLabel: 'tutorial_profile_title');
  static final profileImage = GlobalKey(debugLabel: 'tutorial_profile_image');
  static final profileName = GlobalKey(debugLabel: 'tutorial_profile_name');
  static final profileShareLevel = GlobalKey(
    debugLabel: 'tutorial_profile_share_level',
  );
  static final profileAchievement = GlobalKey(
    debugLabel: 'tutorial_profile_achievement',
  );
}

class TutorialProgressStore {
  TutorialProgressStore(this._client);

  final SupabaseClient _client;
  String? _deviceId;

  Future<Map<String, bool>> load() async {
    _deviceId = await _readDeviceId();
    if (_deviceId == null) return <String, bool>{};

    try {
      final user = await _client
          .from('users')
          .select('tutorial_progress')
          .eq('device_id', _deviceId!)
          .maybeSingle();
      return _asProgress(user?['tutorial_progress']);
    } catch (error) {
      debugPrint('튜토리얼 진행 상태를 불러오지 못했습니다: $error');
      return <String, bool>{};
    }
  }

  Future<void> save(Map<String, bool> progress) async {
    final deviceId = _deviceId ?? await _readDeviceId();
    if (deviceId == null) return;
    _deviceId = deviceId;

    final payload = <String, dynamic>{
      'device_id': deviceId,
      'tutorial_progress': progress,
    };

    try {
      final existingUser = await _client
          .from('users')
          .select('idx')
          .eq('device_id', deviceId)
          .maybeSingle();

      if (existingUser == null) {
        payload.addAll(<String, dynamic>{
          'user_id': generateNickname(deviceId),
          'language': 'kor',
        });
        await _client.from('users').upsert(payload, onConflict: 'device_id');
      } else {
        await _client
            .from('users')
            .update(<String, dynamic>{'tutorial_progress': progress})
            .eq('device_id', deviceId);
      }
    } catch (error) {
      debugPrint('튜토리얼 진행 상태를 저장하지 못했습니다: $error');
      rethrow;
    }
  }

  Map<String, bool> _asProgress(dynamic value) {
    if (value is! Map) return <String, bool>{};
    return value.map<String, bool>(
      (dynamic key, dynamic item) =>
          MapEntry<String, bool>(key.toString(), item == true),
    );
  }

  Future<String?> _readDeviceId() async {
    return InstallationIdentity.id;
  }
}

class TutorialOverlay extends StatefulWidget {
  const TutorialOverlay({
    super.key,
    required this.section,
    required this.stepIndex,
    required this.onNext,
    required this.onSkip,
  });

  final TutorialSection section;
  final int stepIndex;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  @override
  State<TutorialOverlay> createState() => _TutorialOverlayState();
}

class _TutorialOverlayState extends State<TutorialOverlay> {
  final GlobalKey _overlayKey = GlobalKey(debugLabel: 'tutorial_overlay');
  Timer? _targetRefreshTimer;
  Rect? _measuredTarget;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshTarget());
    _targetRefreshTimer = Timer.periodic(
      const Duration(milliseconds: 120),
      (_) => _refreshTarget(),
    );
  }

  @override
  void didUpdateWidget(TutorialOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.section != widget.section ||
        oldWidget.stepIndex != widget.stepIndex) {
      _measuredTarget = null;
      _refreshTarget();
    }
  }

  @override
  void dispose() {
    _targetRefreshTimer?.cancel();
    super.dispose();
  }

  void _refreshTarget() {
    if (!mounted) return;
    final steps = _stepsFor(widget.section);
    final safeStepIndex = widget.stepIndex.clamp(0, steps.length - 1);
    final measured = _measureTarget(steps[safeStepIndex]);
    if (measured == null || measured == _measuredTarget) return;
    setState(() => _measuredTarget = measured);
  }

  Rect? _measureTarget(_TutorialStep step) {
    final overlayBox =
        _overlayKey.currentContext?.findRenderObject() as RenderBox?;
    if (overlayBox == null || !overlayBox.hasSize) return null;

    Rect? combined;
    for (final targetKey in step.targetKeys) {
      final targetBox =
          targetKey.currentContext?.findRenderObject() as RenderBox?;
      if (targetBox == null || !targetBox.hasSize || !targetBox.attached) {
        continue;
      }
      final globalTopLeft = targetBox.localToGlobal(Offset.zero);
      final localTopLeft = overlayBox.globalToLocal(globalTopLeft);
      final rect = localTopLeft & targetBox.size;
      combined = combined == null ? rect : combined.expandToInclude(rect);
    }

    if (combined == null) return null;
    final adjusted = Rect.fromLTRB(
      combined.left,
      combined.top,
      combined.right,
      combined.bottom - step.targetBottomInset,
    );
    var padded = _applyMinSize(
      adjusted.inflate(step.targetPadding),
      step.minTargetSize,
    );
    // 경계 위젯이 지정된 단계는 패딩까지 포함한 강조 영역을 그 위젯 사각형 안으로 제한한다.
    final bounds = _measureBounds(step.boundsKey, overlayBox);
    if (bounds != null) {
      padded = padded.intersect(bounds);
    }
    final clipped = padded.intersect(Offset.zero & overlayBox.size);
    return clipped.isEmpty ? null : clipped;
  }

  Rect? _measureBounds(GlobalKey? boundsKey, RenderBox overlayBox) {
    if (boundsKey == null) return null;
    final boundsBox =
        boundsKey.currentContext?.findRenderObject() as RenderBox?;
    if (boundsBox == null || !boundsBox.hasSize || !boundsBox.attached) {
      return null;
    }
    final localTopLeft = overlayBox.globalToLocal(
      boundsBox.localToGlobal(Offset.zero),
    );
    return localTopLeft & boundsBox.size;
  }

  /// 측정된 사각형을 중심 고정으로 [minSize] 이상으로 키운다.
  /// 하트·공유처럼 위젯 자체 크기가 다른 버튼도 같은 크기의 강조 영역을 갖게 한다.
  static Rect _applyMinSize(Rect rect, Size? minSize) {
    if (minSize == null) return rect;
    final width = rect.width < minSize.width ? minSize.width : rect.width;
    final height = rect.height < minSize.height ? minSize.height : rect.height;
    return Rect.fromCenter(center: rect.center, width: width, height: height);
  }

  @override
  Widget build(BuildContext context) {
    final steps = _stepsFor(widget.section);
    final safeStepIndex = widget.stepIndex.clamp(0, steps.length - 1);
    final step = steps[safeStepIndex];
    final isLast = safeStepIndex == steps.length - 1;

    return Positioned.fill(
      child: Material(
        color: Colors.transparent,
        child: SizedBox.expand(
          key: _overlayKey,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = constraints.biggest;
              final safeTop = MediaQuery.paddingOf(context).top;
              final target =
                  _measuredTarget ?? step.fallbackTarget(size, safeTop);
              final calloutWidth = (size.width - 48).clamp(0.0, 420.0);
              final calloutTop = step.calloutTop(size, safeTop, target);

              return Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(painter: _SpotlightPainter(target)),
                  ),
                  Positioned.fromRect(
                    rect: target,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.9),
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 24,
                    top: calloutTop,
                    width: calloutWidth,
                    child: _TutorialCallout(
                      number: safeStepIndex + 1,
                      title: step.title,
                      description: step.description,
                      stepIndex: safeStepIndex,
                      stepCount: steps.length,
                      buttonLabel: isLast ? '확인' : '다음',
                      onPressed: widget.onNext,
                    ),
                  ),
                  // 건너뛰기는 항상 최상위에 둔다. 프로필 1단계처럼 강조 영역이
                  // 화면 상단 전체 폭을 덮는 경우 밝은 구멍 안에 놓이므로,
                  // 어두운 배경 위에서도 밝은 배경 위에서도 읽히는 진한 알약 배경을 쓴다.
                  Positioned(
                    top: safeTop + 10,
                    right: 14,
                    child: TextButton(
                      key: const ValueKey('tutorial_skip_button'),
                      onPressed: widget.onSkip,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: Colors.black.withValues(alpha: 0.6),
                        shape: const StadiumBorder(),
                      ),
                      child: const Text('건너뛰기'),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _TutorialCallout extends StatelessWidget {
  const _TutorialCallout({
    required this.number,
    required this.title,
    required this.description,
    required this.stepIndex,
    required this.stepCount,
    required this.buttonLabel,
    required this.onPressed,
  });

  final int number;
  final String title;
  final String description;
  final int stepIndex;
  final int stepCount;
  final String buttonLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: Color(0xFFF8E3DF),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$number',
                  style: const TextStyle(
                    color: Color(0xFF9B5D5D),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFF292929),
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      description,
                      style: const TextStyle(
                        color: Color(0xFF626262),
                        fontSize: 14,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              ...List<Widget>.generate(
                stepCount,
                (index) => AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: index == stepIndex ? 18 : 6,
                  height: 6,
                  margin: const EdgeInsets.only(right: 5),
                  decoration: BoxDecoration(
                    color: index == stepIndex
                        ? const Color(0xFF81A684)
                        : const Color(0xFFD6D6D6),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const Spacer(),
              FilledButton(
                onPressed: onPressed,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF81A684),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(76, 40),
                ),
                child: Text(buttonLabel),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  const _SpotlightPainter(this.target);

  final Rect target;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Colors.black.withValues(alpha: 0.56),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(target, const Radius.circular(18)),
      Paint()..blendMode = BlendMode.clear,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SpotlightPainter oldDelegate) =>
      oldDelegate.target != target;
}

class _TutorialStep {
  const _TutorialStep({
    required this.title,
    required this.description,
    required this.targetKeys,
    required this.fallbackTarget,
    required this.calloutTop,
    this.targetPadding = 0,
    this.targetBottomInset = 0,
    this.minTargetSize,
    this.boundsKey,
  });

  final String title;
  final String description;
  final List<GlobalKey> targetKeys;
  final Rect Function(Size size, double safeTop) fallbackTarget;
  final double Function(Size size, double safeTop, Rect target) calloutTop;
  final double targetPadding;
  final double targetBottomInset;

  /// 강조 영역의 최소 크기. 측정값이 이보다 작으면 중심을 유지한 채 확장한다.
  final Size? minTargetSize;

  /// 강조 영역(패딩 포함)을 이 위젯의 사각형 안으로 제한한다. 없으면 제한하지 않는다.
  final GlobalKey? boundsKey;
}

/// 홈 카드의 하트·공유 버튼 강조 영역 공통 크기.
/// 두 버튼의 위젯 크기(23×23, 18×20)가 달라도 같은 크기로 강조되도록 고정한다.
const Size _homeActionTargetSize = Size(44, 44);

List<_TutorialStep> _stepsFor(TutorialSection section) {
  switch (section) {
    case TutorialSection.home:
      return <_TutorialStep>[
        _TutorialStep(
          title: '당신의 하루에 머무는 한마디',
          description: '다양한 주제의 명언을 편안하게 만나보세요.',
          targetKeys: <GlobalKey>[TutorialTargets.homeCard],
          fallbackTarget: (size, safeTop) =>
              Rect.fromLTWH(24, safeTop + 50, size.width - 48, 220),
          targetBottomInset: 16,
          calloutTop: (size, safeTop, target) =>
              _fitCalloutTop(target.bottom + 16, size, safeTop),
        ),
        _TutorialStep(
          title: '마음에 남는 명언을 보관해요.',
          description: '하트를 누르면 언제든 다시 꺼내 볼 수 있어요.',
          targetKeys: <GlobalKey>[TutorialTargets.homeLike],
          fallbackTarget: (size, safeTop) => Rect.fromLTWH(
            size.width - 152,
            safeTop + 218,
            _homeActionTargetSize.width,
            _homeActionTargetSize.height,
          ),
          targetPadding: 6,
          minTargetSize: _homeActionTargetSize,
          calloutTop: (size, safeTop, target) =>
              _fitCalloutTop(target.bottom + 20, size, safeTop),
        ),
        _TutorialStep(
          title: '좋은 명언을 함께 나눠요.',
          description: '공유 버튼을 눌러 소중한 사람에게 문장을 전해보세요.',
          targetKeys: <GlobalKey>[TutorialTargets.homeShare],
          fallbackTarget: (size, safeTop) => Rect.fromLTWH(
            size.width - 88,
            safeTop + 218,
            _homeActionTargetSize.width,
            _homeActionTargetSize.height,
          ),
          targetPadding: 6,
          minTargetSize: _homeActionTargetSize,
          calloutTop: (size, safeTop, target) =>
              _fitCalloutTop(target.bottom + 20, size, safeTop),
        ),
      ];
    case TutorialSection.search:
      // 검색 화면 레이아웃(search_page.dart): SafeArea 최소 상단 61 → 헤더 43
      // → 간격 29 → 입력 바 63(좌우 25) → 간격 29 → 탭 50.
      double searchBarTop(double safeTop) =>
          (safeTop > 61 ? safeTop : 61) + 43 + 29;
      return <_TutorialStep>[
        _TutorialStep(
          title: '원하는 명언을 찾아보세요.',
          description: '저자 이름, 명언 내용, 주제 중 원하는 기준으로 검색할 수 있어요.',
          targetKeys: <GlobalKey>[TutorialTargets.searchTabs],
          fallbackTarget: (size, safeTop) =>
              Rect.fromLTWH(0, searchBarTop(safeTop) + 63 + 29, size.width, 50),
          calloutTop: (size, safeTop, target) =>
              _fitCalloutTop(target.bottom + 20, size, safeTop),
        ),
        _TutorialStep(
          title: '원하는 기준으로 검색해 보세요.',
          description: '저자·본문·주제를 선택하고 찾고 싶은 내용을 입력해 주세요.',
          // 입력 바(아이콘 포함 흰 박스) 전체를 강조한다.
          targetKeys: <GlobalKey>[TutorialTargets.searchField],
          fallbackTarget: (size, safeTop) =>
              Rect.fromLTWH(25, searchBarTop(safeTop), size.width - 50, 63),
          targetPadding: 4,
          calloutTop: (size, safeTop, target) =>
              _fitCalloutTop(target.bottom + 20, size, safeTop),
        ),
      ];
    case TutorialSection.bookmarks:
      return <_TutorialStep>[
        _TutorialStep(
          title: '보관한 명언을 다시 만나보세요.',
          description: '마음에 담아둔 명언을 보관함에서 언제든 다시 볼 수 있어요.',
          targetKeys: <GlobalKey>[TutorialTargets.bookmarkTab],
          fallbackTarget: (size, safeTop) =>
              Rect.fromLTWH(size.width * 0.625 - 32, size.height - 70, 64, 62),
          targetPadding: 8,
          // 패딩이 하단 바 위쪽 본문 영역으로 침범하지 않도록 바 안으로 제한한다.
          boundsKey: TutorialTargets.bottomNavBar,
          calloutTop: (size, safeTop, target) =>
              _fitCalloutTop(target.top - 190, size, safeTop),
        ),
        _TutorialStep(
          title: '원할 때 보관을 해제할 수 있어요.',
          description: '하트를 다시 누르면 해당 명언이 보관함에서 제외돼요.',
          targetKeys: <GlobalKey>[TutorialTargets.bookmarkLike],
          fallbackTarget: (size, safeTop) =>
              Rect.fromLTWH(size.width - 152, safeTop + 225, 58, 58),
          targetPadding: 6,
          calloutTop: (size, safeTop, target) =>
              _fitCalloutTop(target.bottom + 20, size, safeTop),
        ),
      ];
    case TutorialSection.profile:
      return <_TutorialStep>[
        _TutorialStep(
          title: '개인 프로필을 설정해보세요.',
          description: '프로필 사진, 이름, 언어를 나에게 맞게 설정할 수 있어요.',
          targetKeys: <GlobalKey>[
            TutorialTargets.profileTitle,
            TutorialTargets.profileImage,
            TutorialTargets.profileName,
          ],
          fallbackTarget: (size, safeTop) =>
              Rect.fromLTWH(20, safeTop + 48, size.width - 40, 285),
          targetPadding: 4,
          calloutTop: (size, safeTop, target) =>
              _fitCalloutTop(target.bottom + 16, size, safeTop),
        ),
        _TutorialStep(
          title: '나의 공유 활동을 확인해요.',
          description: '공유 횟수에 따라 등급이 올라가고 진행 상황을 확인할 수 있어요.',
          targetKeys: <GlobalKey>[
            TutorialTargets.profileShareLevel,
            TutorialTargets.profileAchievement,
          ],
          fallbackTarget: (size, safeTop) =>
              Rect.fromLTWH(20, safeTop + 345, size.width - 40, 155),
          targetPadding: 4,
          calloutTop: (size, safeTop, target) =>
              _fitCalloutTop(target.bottom + 16, size, safeTop),
        ),
      ];
  }
}

double _fitCalloutTop(double desired, Size size, double safeTop) {
  final minimum = safeTop + 70;
  final maximum = size.height - 210;
  if (maximum <= minimum) return safeTop + 4;
  return desired.clamp(minimum, maximum);
}
