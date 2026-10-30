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

  /// 명언 카드를 이미지로 캡처해 공유한다.
  ///
  /// 이미지 생성이나 공유에 실패하면 텍스트를 클립보드에 복사하고 스낵바로 알린다.
  static Future<void> shareAsImage({
    required BuildContext context,
    required String author,
    required String content,
    ImageProvider<Object>? authorImage,
    Future<void> Function()? onShared,
  }) async {
    if (!context.mounted) return;

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

      final shareResult = await Share.shareXFiles([
        XFile(file.path, mimeType: 'image/png'),
      ], subject: '명언 - $author');
      if (shareResult.status == ShareResultStatus.success) {
        await onShared?.call();
      }
    } catch (e) {
      if (entry.mounted) entry.remove();
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
