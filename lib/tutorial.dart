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

class TutorialOverlay extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final steps = _stepsFor(section);
    final safeStepIndex = stepIndex.clamp(0, steps.length - 1);
    final step = steps[safeStepIndex];
    final isLast = safeStepIndex == steps.length - 1;

    return Positioned.fill(
      child: Material(
        color: Colors.transparent,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = constraints.biggest;
            final safeTop = MediaQuery.paddingOf(context).top;
            final target = step.target(size, safeTop);
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
                  top: safeTop + 10,
                  right: 14,
                  child: TextButton(
                    onPressed: onSkip,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: Colors.black.withValues(alpha: 0.25),
                    ),
                    child: const Text('건너뛰기'),
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
                    onPressed: onNext,
                  ),
                ),
              ],
            );
          },
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
    required this.target,
    required this.calloutTop,
  });

  final String title;
  final String description;
  final Rect Function(Size size, double safeTop) target;
  final double Function(Size size, double safeTop, Rect target) calloutTop;
}

List<_TutorialStep> _stepsFor(TutorialSection section) {
  switch (section) {
    case TutorialSection.home:
      return <_TutorialStep>[
        _TutorialStep(
          title: '힐링 하이의 명언 카드',
          description: '여러 분야의 명언과 출처를 한눈에 확인할 수 있어요.',
          target: (size, safeTop) =>
              Rect.fromLTWH(24, safeTop + 50, size.width - 48, 220),
          calloutTop: (size, safeTop, target) =>
              _fitCalloutTop(target.bottom + 16, size, safeTop),
        ),
        _TutorialStep(
          title: '마음에 드는 문구를 보관해요',
          description: '하트 버튼을 누르면 문구가 보관함에 저장돼요.',
          target: (size, safeTop) =>
              Rect.fromLTWH(size.width - 152, safeTop + 218, 58, 58),
          calloutTop: (size, safeTop, target) =>
              _fitCalloutTop(target.bottom + 20, size, safeTop),
        ),
        _TutorialStep(
          title: '좋은 문구를 함께 나눠요',
          description: '공유 버튼으로 친구에게 보내거나 다른 앱에 공유할 수 있어요.',
          target: (size, safeTop) =>
              Rect.fromLTWH(size.width - 88, safeTop + 218, 58, 58),
          calloutTop: (size, safeTop, target) =>
              _fitCalloutTop(target.bottom + 20, size, safeTop),
        ),
      ];
    case TutorialSection.search:
      return <_TutorialStep>[
        _TutorialStep(
          title: '원하는 명언을 찾아보세요',
          description: '저자, 본문, 주제 중 검색할 항목을 선택할 수 있어요.',
          target: (size, safeTop) =>
              Rect.fromLTWH(24, safeTop + 145, size.width - 48, 54),
          calloutTop: (size, safeTop, target) =>
              _fitCalloutTop(target.bottom + 20, size, safeTop),
        ),
        _TutorialStep(
          title: '검색 항목을 선택해요',
          description: '저자·본문·주제 탭을 눌러 검색 범위를 정해주세요.',
          target: (size, safeTop) =>
              Rect.fromLTWH(24, safeTop + 145, size.width - 48, 54),
          calloutTop: (size, safeTop, target) =>
              _fitCalloutTop(target.bottom + 20, size, safeTop),
        ),
        _TutorialStep(
          title: '검색어를 입력해주세요',
          description: '위 검색창에 찾고 싶은 내용을 입력하면 결과가 바로 표시돼요.',
          target: (size, safeTop) =>
              Rect.fromLTWH(24, safeTop + 58, size.width - 48, 62),
          calloutTop: (size, safeTop, target) =>
              _fitCalloutTop(target.bottom + 88, size, safeTop),
        ),
      ];
    case TutorialSection.bookmarks:
      return <_TutorialStep>[
        _TutorialStep(
          title: '좋아요한 명언을 모아봐요',
          description: '홈에서 하트를 누른 명언이 이 보관함에 모여요.',
          target: (size, safeTop) =>
              Rect.fromLTWH(size.width * 0.625 - 32, size.height - 70, 64, 62),
          calloutTop: (size, safeTop, target) =>
              _fitCalloutTop(target.top - 190, size, safeTop),
        ),
        _TutorialStep(
          title: '언제든 보관함에서 지울 수 있어요',
          description: '보관된 카드의 하트를 다시 누르면 목록에서 삭제돼요.',
          target: (size, safeTop) =>
              Rect.fromLTWH(size.width - 152, safeTop + 225, 58, 58),
          calloutTop: (size, safeTop, target) =>
              _fitCalloutTop(target.bottom + 20, size, safeTop),
        ),
      ];
    case TutorialSection.profile:
      return <_TutorialStep>[
        _TutorialStep(
          title: '개인 프로필을 설정해보세요',
          description: '프로필 사진, 이름, 언어를 나에게 맞게 설정할 수 있어요.',
          target: (size, safeTop) =>
              Rect.fromLTWH(20, safeTop + 48, size.width - 40, 285),
          calloutTop: (size, safeTop, target) =>
              _fitCalloutTop(target.bottom + 16, size, safeTop),
        ),
        _TutorialStep(
          title: '나의 공유 활동을 확인해요',
          description: '공유 횟수에 따라 등급이 올라가고 진행 상황을 확인할 수 있어요.',
          target: (size, safeTop) =>
              Rect.fromLTWH(20, safeTop + 345, size.width - 40, 155),
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
