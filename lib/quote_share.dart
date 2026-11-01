import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'resoner_image_helper.dart';

/// 명언 카드 이미지 공유 공용 로직.
///
/// 홈 화면과 보관함 화면이 같은 카드 디자인·공유 절차를 쓰도록 한 곳에 모았다.
/// 공유 카운트 증가는 실제 공유 성공(`ShareResultStatus.success`)일 때만
/// `onShared` 콜백으로 호출자에게 위임한다. 클립보드 폴백 경로에서는 호출하지 않는다.
class QuoteShare {
  QuoteShare._();

  /// 신청 명언 이미지 URL이 있으면 네트워크 이미지, 없으면 저자 자산 이미지를 고른다.
  static ImageProvider<Object>? resolveAuthorImage({
    String? requestImageUrl,
    String? imageFile,
    String? resonerEng,
  }) {
    if (requestImageUrl != null) return NetworkImage(requestImageUrl);
    final resolvedImagePath = ResonerImageHelper.resolve(imageFile, resonerEng);
    return resolvedImagePath != null ? AssetImage(resolvedImagePath) : null;
  }

  /// 이미지 생성 중 화면 가운데에 띄우는 안내 문구.
  static const generatingNotice = '문장에 작은 온기를 더하고 있어요.';

  /// 명언 카드를 이미지로 캡처해 공유한다.
  ///
  /// 이미지를 만드는 동안 화면 가운데에 로딩 표시와 [generatingNotice]를 띄우고,
  /// 공유 시트를 열기 직전에 닫는다. 떠 있는 동안에는 뒤 화면 터치를 막아
  /// 공유 버튼이 중복으로 눌리지 않게 한다.
  /// 이미지 생성이나 공유에 실패하면 텍스트를 클립보드에 복사하고 스낵바로 알린다.
  static Future<void> shareAsImage({
    required BuildContext context,
    required String author,
    required String content,
    ImageProvider<Object>? authorImage,
    Future<void> Function()? onShared,
  }) async {
    if (!context.mounted) return;

    // 중간에 빠져나가는 경로(화면 이탈 등)에서도 안내가 남지 않도록 finally에서 닫는다.
    final hideGeneratingNotice = _showGeneratingNotice(context);
    try {
      if (authorImage != null) {
        try {
          await precacheImage(
            authorImage,
            context,
          ).timeout(const Duration(seconds: 3));
        } catch (_) {
          // 이미지 로드 실패 시 기본 프로필 아이콘을 사용한다.
        }
      }

      if (!context.mounted) return;

      final key = GlobalKey();
      late OverlayEntry entry;

      entry = OverlayEntry(
        builder: (_) => Positioned(
          left: -10000,
          top: 0,
          child: Material(
            type: MaterialType.transparency,
            child: RepaintBoundary(
              key: key,
              child: QuoteShareCard(
                author: author,
                content: content,
                authorImage: authorImage,
              ),
            ),
          ),
        ),
      );

      Overlay.of(context).insert(entry);

      try {
        // 위젯이 렌더링될 때까지 대기
        await Future.delayed(const Duration(milliseconds: 300));

        if (!context.mounted) {
          entry.remove();
          return;
        }

        final boundary =
            key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
        if (boundary == null) throw Exception('카드 렌더링 실패');

        final image = await boundary.toImage(pixelRatio: 3.0);
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        if (byteData == null) throw Exception('이미지 변환 실패');

        final pngBytes = byteData.buffer.asUint8List();
        final tempDir = await getTemporaryDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final file = File('${tempDir.path}/healinghi_quote_$timestamp.png');
        await file.writeAsBytes(pngBytes);

        entry.remove();
        hideGeneratingNotice();

        final shareResult = await Share.shareXFiles([
          XFile(file.path, mimeType: 'image/png'),
        ], subject: '명언 - $author');
        if (shareResult.status == ShareResultStatus.success) {
          await onShared?.call();
        }
      } catch (e) {
        if (entry.mounted) entry.remove();
        hideGeneratingNotice();
        if (!context.mounted) return;
        // 실패 시 텍스트 클립보드 복사로 폴백
        await Clipboard.setData(
          ClipboardData(text: '$author\n\n$content\n\nHealing Hi'),
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('이미지 생성 실패 - 텍스트가 클립보드에 복사되었습니다.')),
          );
        }
      }
    } finally {
      hideGeneratingNotice();
    }
  }

  /// [generatingNotice] 로딩 안내를 화면 가운데에 띄우고, 그것을 닫는 함수를 돌려준다.
  ///
  /// 하단 탭까지 덮도록 루트 Overlay에 넣는다.
  /// 반환된 함수는 여러 번 호출해도 안전하며, 이미 닫혔으면 아무것도 하지 않는다.
  static VoidCallback _showGeneratingNotice(BuildContext context) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return () {};

    final entry = OverlayEntry(
      builder: (_) => const _GeneratingNoticeOverlay(),
    );
    overlay.insert(entry);

    var closed = false;
    return () {
      if (closed) return;
      closed = true;
      if (entry.mounted) entry.remove();
      entry.dispose();
    };
  }
}

/// 공유 이미지 생성 중 화면 가운데에 띄우는 로딩 안내.
///
/// 배경색·모서리·강조색은 공용 안내 팝업(`app_popup.dart`)과 같은 톤을 쓴다.
class _GeneratingNoticeOverlay extends StatelessWidget {
  const _GeneratingNoticeOverlay();

  @override
  Widget build(BuildContext context) {
    // 1초 안팎으로 떴다 사라지므로 스크림을 옅게 두고 짧게 페이드 인한다.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 150),
      builder: (context, opacity, child) =>
          Opacity(opacity: opacity, child: child),
      child: Stack(
        children: [
          // 생성 중 뒤 화면 터치(공유 버튼 중복 탭 등)를 막는다.
          const ModalBarrier(dismissible: false, color: Color(0x33000000)),
          Center(
            child: Material(
              type: MaterialType.transparency,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 40),
                padding: const EdgeInsets.fromLTRB(28, 26, 28, 24),
                decoration: BoxDecoration(
                  color: const Color(0xFFF6F4F1),
                  borderRadius: BorderRadius.circular(25),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 30,
                      height: 30,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: Color(0xFF81A684),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Semantics(
                      liveRegion: true,
                      child: const Text(
                        QuoteShare.generatingNotice,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 15,
                          fontWeight: FontWeight.w300,
                          height: 23 / 15,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 공유 이미지로 캡처되는 명언 카드 위젯.
class QuoteShareCard extends StatelessWidget {
  const QuoteShareCard({
    super.key,
    required this.author,
    required this.content,
    this.authorImage,
  });

  final String author;
  final String content;
  final ImageProvider<Object>? authorImage;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 420,
      color: const Color(0xFFE3ECE4),
      padding: const EdgeInsets.fromLTRB(26, 34, 26, 34),
      child: Container(
        constraints: const BoxConstraints(minHeight: 340),
        padding: const EdgeInsets.fromLTRB(38, 36, 36, 26),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Image.asset(
              'assets/share_quote_icon.png',
              width: 42,
              height: 42,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
            ),
            const SizedBox(height: 34),
            Text(
              content,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w300,
                color: Color(0xFF555555),
                height: 1.65,
                fontFamily: 'Pretendard',
              ),
            ),
            const SizedBox(height: 40),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ClipOval(
                  child: Container(
                    width: 28,
                    height: 28,
                    color: const Color(0xFFF0F0F0),
                    child: authorImage == null
                        ? const Icon(
                            Icons.person,
                            size: 17,
                            color: Color(0xFFAAAAAA),
                          )
                        : Image(
                            image: authorImage!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(
                                  Icons.person,
                                  size: 17,
                                  color: Color(0xFFAAAAAA),
                                ),
                          ),
                  ),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    author,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF666666),
                      fontFamily: 'Pretendard',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            const Divider(color: Color(0xFFE8E8E8), thickness: 1, height: 1),
            const SizedBox(height: 28),
            const Center(
              child: Text(
                '당신의 하루에 머무는 한마디',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w300,
                  color: Color(0xFF555555),
                  fontFamily: 'Pretendard',
                ),
              ),
            ),
            const SizedBox(height: 10),
            const Center(
              child: Text(
                '힐링 하이',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w300,
                  color: Color(0xFF555555),
                  fontFamily: 'Pretendard',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
