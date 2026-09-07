import 'package:flutter/material.dart';

// Figma 공용 안내 팝업(PopUP) 규격
// - 팝업 400×241, 화면 좌우 인셋 20, 내부 패딩 20
// - 헤더 140: 아이콘 30 중앙 → 15 → 제목 20px(24h) → 20 → 안내 2줄(46h)
// - 푸터 41(패딩 10): 텍스트 버튼. 단일이면 폭 340, 2개면 165 + 10 + 165
// 색상·폰트는 알림 시간 설정 팝업(setting_page.dart)과 같은 톤을 쓴다.
const _popupBackground = Color(0xFFF6F4F1);
const _popupAccent = Color(0xFF81A684);
const _popupBarrier = Color(0x9F000000);

/// 팝업에서 사용자가 누른 버튼
enum AppNoticeAction { primary, secondary }

class AppNoticePopup extends StatelessWidget {
  const AppNoticePopup({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.primaryLabel = '확인',
    this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
  });

  /// 제목 위 아이콘(30×30 영역에 중앙 배치)
  final Widget icon;
  final String title;

  /// 최대 2줄 안내 문구
  final String message;

  /// 좌측(또는 단일) 버튼 문구. 누르면 팝업을 닫은 뒤 [onPrimary]를 호출한다.
  final String primaryLabel;
  final VoidCallback? onPrimary;

  /// 우측 버튼 문구. null이면 단일 버튼 레이아웃.
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20),
      elevation: 0,
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Container(
          height: 241,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _popupBackground,
            borderRadius: BorderRadius.circular(25),
          ),
          child: Column(
            children: [
              // Header (Figma 140h, Head Title 좌우 4)
              SizedBox(
                height: 140,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    children: [
                      const SizedBox(height: 4),
                      SizedBox(
                        width: 30,
                        height: 30,
                        child: Center(child: icon),
                      ),
                      const SizedBox(height: 15),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 15,
                          fontWeight: FontWeight.w300,
                          height: 23 / 15,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // Footer (Figma 41h, 패딩 10)
              SizedBox(
                height: 41,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: secondaryLabel == null
                      ? _buildAction(
                          context,
                          label: primaryLabel,
                          color: _popupAccent,
                          action: AppNoticeAction.primary,
                          callback: onPrimary,
                        )
                      : Row(
                          children: [
                            Expanded(
                              child: _buildAction(
                                context,
                                label: primaryLabel,
                                color: _popupAccent,
                                action: AppNoticeAction.primary,
                                callback: onPrimary,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _buildAction(
                                context,
                                label: secondaryLabel!,
                                color: Colors.black,
                                action: AppNoticeAction.secondary,
                                callback: onSecondary,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 텍스트형 버튼: 팝업을 닫고 결과를 돌려준 뒤 콜백을 실행한다.
  Widget _buildAction(
    BuildContext context, {
    required String label,
    required Color color,
    required AppNoticeAction action,
    VoidCallback? callback,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Navigator.of(context).pop(action);
        callback?.call();
      },
      child: Center(
        child: Text(
          label,
          maxLines: 1,
          style: TextStyle(
            color: color,
            fontSize: 18,
            fontWeight: FontWeight.w500,
            height: 1.15,
          ),
        ),
      ),
    );
  }
}

/// [AppNoticePopup]을 다이얼로그로 띄운다. 눌린 버튼을 반환하며,
/// 스크림 탭이나 뒤로 가기로 닫히면 null을 반환한다.
Future<AppNoticeAction?> showAppNoticePopup(
  BuildContext context, {
  required Widget icon,
  required String title,
  required String message,
  String primaryLabel = '확인',
  VoidCallback? onPrimary,
  String? secondaryLabel,
  VoidCallback? onSecondary,
  bool barrierDismissible = true,
}) {
  return showDialog<AppNoticeAction>(
    context: context,
    barrierColor: _popupBarrier,
    barrierDismissible: barrierDismissible,
    builder: (_) => AppNoticePopup(
      icon: icon,
      title: title,
      message: message,
      primaryLabel: primaryLabel,
      onPrimary: onPrimary,
      secondaryLabel: secondaryLabel,
      onSecondary: onSecondary,
    ),
  );
}
