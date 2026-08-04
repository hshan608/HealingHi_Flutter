import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:like_button/like_button.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'ad_helper.dart';
import 'installation_identity.dart';
import 'resoner_image_helper.dart';
import 'tutorial.dart';

// Supabase 클라이언트 전역 변수
final supabase = Supabase.instance.client;

// 메인 화면
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.onInterstitialRequested});

  final VoidCallback onInterstitialRequested;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ScrollController _quoteScrollController = ScrollController();
  List<Map<String, dynamic>> _quotes = [];
  bool _isLoading = true;
  String? _deviceId;
  int? _userIdx;
  bool _isSavingLike = false;
  Set<String> _savedQuoteIds = {};
  Map<String, String> _requestQuoteImages = {}; // 'req_42' -> image_url
  Set<String> _ownRequestQuoteIds = {};

  final Set<String> _shownInterstitialKeys = {}; // quote 인덱스와 스크롤 방향별 광고 이력

  @override
  void initState() {
    super.initState();
    ResonerImageHelper.load();
    _loadQuotes();
    _initUserIdentity();
  }

  @override
  void dispose() {
    _quoteScrollController.dispose();
    super.dispose();
  }

  String _interstitialKey(int quoteIndex, ScrollDirection direction) {
    return '$quoteIndex:${direction.name}';
  }

  // 전면 광고 표시 (quoteIndex와 스크롤 방향 기준 중복 방지)
  void _showInterstitialAd(int quoteIndex, ScrollDirection direction) {
    final interstitialKey = _interstitialKey(quoteIndex, direction);
    if (_shownInterstitialKeys.contains(interstitialKey)) return;

    _shownInterstitialKeys.add(interstitialKey);

    // 광고가 표시되는 시점에 진행 중인 빠른 관성 스크롤을 즉시 멈춘다.
    if (_quoteScrollController.hasClients) {
      _quoteScrollController.jumpTo(_quoteScrollController.offset);
    }

    widget.onInterstitialRequested();
  }

  // Supabase에서 명언 데이터 가져오기 (랜덤 순서)
  Future<void> _loadQuotes() async {
    await ResonerImageHelper.load();
    try {
      final response = await supabase.from('quotes').select();

      final list = List<Map<String, dynamic>>.from(response);
      list.shuffle(Random());

      // request_quotes는 RLS로 현재 설치 사용자의 신청만 조회된다.
      // 승인된 신청 명언은 quotes 테이블에 req_<id> 형식으로 저장된다.
      final ownRequestQuoteIds = <String>{};
      try {
        final ownRequests = await supabase.from('request_quotes').select('id');
        for (final request in ownRequests as List) {
          final requestId = request['id']?.toString();
          if (requestId != null && requestId.isNotEmpty) {
            ownRequestQuoteIds.add('req_$requestId');
          }
        }
      } catch (error) {
        debugPrint('내가 신청한 명언 ID 로드 실패: $error');
      }

      // req_ 접두어 명언의 이미지 일괄 조회
      final reqIds = list
          .map((q) => q['id']?.toString())
          .where((id) => id != null && id!.startsWith('req_'))
          .cast<String>()
          .toList();
      if (reqIds.isNotEmpty) {
        final numericIds = reqIds
            .map((id) => int.tryParse(id.replaceFirst('req_', '')))
            .whereType<int>()
            .toList();
        if (numericIds.isNotEmpty) {
          final images = await supabase
              .from('request_quote_images')
              .select('request_quote_idx, image_url')
              .inFilter('request_quote_idx', numericIds);
          final Map<String, String> reqImgMap = {};
          for (final img in images as List) {
            final idx = img['request_quote_idx']?.toString();
            final url = img['image_url']?.toString();
            if (idx != null && url != null) {
              reqImgMap['req_$idx'] = url;
            }
          }
          _requestQuoteImages = reqImgMap;
        }
      }

      if (!mounted) return;
      setState(() {
        _quotes = list;
        _ownRequestQuoteIds = ownRequestQuoteIds;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('데이터를 불러오는데 실패했습니다: $error')));
    }
  }

  // 디바이스 ID와 사용자 idx 로드
  Future<void> _initUserIdentity() async {
    try {
      final deviceId = InstallationIdentity.id;
      _deviceId = deviceId;

      final user = await supabase
          .from('users')
          .select('idx')
          .eq('device_id', deviceId)
          .maybeSingle();

      if (user != null && mounted) {
        setState(() {
          _userIdx = _toInt(user['idx']);
        });
        await _loadSavedQuoteIds();
      }
    } catch (e) {
      // 디바이스 정보를 가져오지 못해도 앱 동작에는 영향 없음
      print('사용자 식별자 로드 실패: $e');
    }
  }

  Future<void> _loadSavedQuoteIds() async {
    if (_userIdx == null) return;
    try {
      final userQuotes = await supabase
          .from('users_quotes')
          .select('quotes_id')
          .eq('user_idx', _userIdx!);

      final ids = userQuotes
          .map<String?>((row) => row['quotes_id']?.toString())
          .where((id) => id != null && id.isNotEmpty)
          .cast<String>()
          .toSet();

      if (mounted) {
        setState(() {
          _savedQuoteIds = ids;
        });
      }
    } catch (e) {
      print('저장된 명언 ID 로드 실패: $e');
    }
  }

  Future<void> _toggleUserQuote(String? quoteId) async {
    if (quoteId == null) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('명언 ID를 찾을 수 없습니다.')));
      }
      return;
    }

    if (_isSavingLike) return;
    setState(() {
      _isSavingLike = true;
    });

    try {
      // 사용자 idx가 없으면 다시 시도
      if (_userIdx == null) {
        await _initUserIdentity();
      }

      if (_userIdx == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('사용자 정보를 불러오지 못했습니다. 프로필 저장 후 다시 시도해주세요.'),
            ),
          );
        }
        return;
      }

      final isSaved = _savedQuoteIds.contains(quoteId);

      if (isSaved) {
        // 이미 저장됨 → 삭제
        await supabase
            .from('users_quotes')
            .delete()
            .eq('user_idx', _userIdx!)
            .eq('quotes_id', quoteId);

        if (mounted) {
          setState(() {
            _savedQuoteIds.remove(quoteId);
          });
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('보관함에서 삭제되었습니다.')));
        }
      } else {
        // 저장 안됨 → 추가
        await supabase.from('users_quotes').upsert({
          'user_idx': _userIdx,
          'quotes_id': quoteId,
        }, onConflict: 'user_idx,quotes_id');

        if (mounted) {
          setState(() {
            _savedQuoteIds.add(quoteId);
          });
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('보관함에 저장되었습니다.')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('저장 중 오류가 발생했습니다: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSavingLike = false;
        });
      }
    }
  }

  String? _extractQuoteId(Map<String, dynamic> quote) {
    final value = quote['id'] ?? quote['idx'];
    if (value == null) return null;
    return value.toString();
  }

  int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return null;
  }

  // 공유 카운트 증가
  Future<void> _incrementShareCount() async {
    if (_deviceId == null) return;
    try {
      await supabase.rpc(
        'increment_share_count',
        params: {'p_device_id': _deviceId},
      );
    } catch (e) {
      print('공유 카운트 업데이트 실패: $e');
    }
  }

  // 공유 카드 위젯 (이미지 캡처용)
  Widget _buildShareCardContent({
    required String author,
    required String content,
    ImageProvider<Object>? authorImage,
  }) {
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
                            image: authorImage,
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

  // 명언 카드를 이미지로 캡처해서 공유
  Future<void> _captureAndShareQuoteImage({
    required String author,
    required String content,
    required String? quoteId,
    required String? imageFile,
    required String? resonerEng,
  }) async {
    if (!mounted) return;

    final requestImageUrl = quoteId == null
        ? null
        : _requestQuoteImages[quoteId];
    final resolvedImagePath = requestImageUrl == null
        ? ResonerImageHelper.resolve(imageFile, resonerEng)
        : null;
    final ImageProvider<Object>? authorImage = requestImageUrl != null
        ? NetworkImage(requestImageUrl)
        : resolvedImagePath != null
        ? AssetImage(resolvedImagePath)
        : null;

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

    if (!mounted) return;

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
            child: _buildShareCardContent(
              author: author,
              content: content,
              authorImage: authorImage,
            ),
          ),
        ),
      ),
    );

    if (!mounted) return;
    Overlay.of(context).insert(entry);

    try {
      // 위젯이 렌더링될 때까지 대기
      await Future.delayed(const Duration(milliseconds: 300));

      if (!mounted) {
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
        await _incrementShareCount();
      }
    } catch (e) {
      if (entry.mounted) entry.remove();
      if (mounted) {
        // 실패 시 텍스트 클립보드 복사로 폴백
        await Clipboard.setData(
          ClipboardData(text: '$author\n\n$content\n\nHealing Hi'),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('이미지 생성 실패 - 텍스트가 클립보드에 복사되었습니다.')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFDDE7DE),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 8),
            const SizedBox(
              height: 43,
              width: double.infinity,
              child: Center(
                child: Text(
                  '오늘의 마음에 머무는 한마디를 만나보세요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF595959),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _quotes.isEmpty
                    ? const Center(
                        child: Text(
                          '명언이 없습니다.\n데이터베이스를 확인해주세요.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 16),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadQuotes,
                        child: _buildQuoteListWithAds(),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAuthorImage({
    required String? quoteId,
    required String? resolvedImagePath,
  }) {
    const fallback = Icon(Icons.person, size: 26, color: Color(0xFFBDBDBD));

    final requestImageUrl = quoteId == null
        ? null
        : _requestQuoteImages[quoteId];

    return ClipOval(
      child: Container(
        width: 50,
        height: 50,
        color: const Color(0xFFF0F0F0),
        child: requestImageUrl != null
            ? Image.network(
                requestImageUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => fallback,
              )
            : resolvedImagePath != null
            ? Image.asset(
                resolvedImagePath,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => fallback,
              )
            : fallback,
      ),
    );
  }

  Widget _buildContentBox(
    String title,
    String content,
    String? quoteId,
    String? tag,
    String? imageFile,
    String? resonerEng,
    bool isTutorialTarget,
  ) {
    final resolvedImagePath =
        quoteId != null && _requestQuoteImages.containsKey(quoteId)
        ? null
        : ResonerImageHelper.resolve(imageFile, resonerEng);
    final isOwnRequest =
        quoteId != null && _ownRequestQuoteIds.contains(quoteId);
    return _AnimatedCardItem(
      child: GestureDetector(
        onDoubleTap: () async {
          await Clipboard.setData(
            ClipboardData(
              text:
                  '"$content" ─ $title\n'
                  '당신의 하루에 머무는 한마디, 힐링하이\n'
                  '(앱 링크)',
            ),
          );
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('클립보드에 복사되었습니다!')));
          }
        },
        child: Container(
          key: isTutorialTarget ? TutorialTargets.homeCard : null,
          margin: const EdgeInsets.only(bottom: 18),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 23),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(25),
            border: isOwnRequest
                ? Border.all(color: const Color(0xFF538CD2), width: 2)
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 상단: 프로필 이미지 + 저자명
              Row(
                children: [
                  _buildAuthorImage(
                    quoteId: quoteId,
                    resolvedImagePath: resolvedImagePath,
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  if (isOwnRequest) ...[
                    const SizedBox(width: 10),
                    const Icon(
                      Icons.bookmark,
                      size: 15,
                      color: Color(0xFF538CD2),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      '내가 신청한 명언',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w300,
                        color: Color(0xFF538CD2),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 18),
              // 명언 텍스트
              Text(
                content,
                textAlign: TextAlign.left,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w300,
                  color: Color(0xFF414141),
                  height: 25 / 18,
                  letterSpacing: -0.36,
                ),
              ),
              const SizedBox(height: 18),
              // 하단: 태그 + 좋아요/공유 버튼
              Row(
                children: [
                  // 태그
                  if (tag != null && tag.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9),
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F5F5),
                        borderRadius: BorderRadius.circular(18.5),
                      ),
                      child: Text(
                        '# $tag',
                        style: const TextStyle(
                          fontSize: 16,
                          color: Color(0xFF9E9E9E),
                          fontWeight: FontWeight.w300,
                        ),
                      ),
                    ),
                  const Spacer(),
                  SizedBox(
                    width: 130,
                    height: 32,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        LikeButton(
                          key: isTutorialTarget
                              ? TutorialTargets.homeLike
                              : null,
                          size: 24,
                          isLiked:
                              quoteId != null &&
                              _savedQuoteIds.contains(quoteId),
                          circleColor: const CircleColor(
                            start: Color(0xFFFF5252),
                            end: Color(0xFFFF1744),
                          ),
                          bubblesColor: const BubblesColor(
                            dotPrimaryColor: Color(0xFFFF5252),
                            dotSecondaryColor: Color(0xFFFF8A80),
                          ),
                          likeBuilder: (bool isLiked) {
                            return Image.asset(
                              isLiked
                                  ? 'assets/heart2.png'
                                  : 'assets/heart1.png',
                              width: 23,
                              height: 19,
                            );
                          },
                          onTap: (bool isLiked) async {
                            await _toggleUserQuote(quoteId);
                            return !isLiked;
                          },
                        ),
                        IconButton(
                          key: isTutorialTarget
                              ? TutorialTargets.homeShare
                              : null,
                          onPressed: () {
                            _captureAndShareQuoteImage(
                              author: title,
                              content: content,
                              quoteId: quoteId,
                              imageFile: imageFile,
                              resonerEng: resonerEng,
                            );
                          },
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                            width: 24,
                            height: 24,
                          ),
                          icon: const Icon(
                            Icons.share,
                            color: Color(0xFF81A684),
                          ),
                          iconSize: 22,
                          tooltip: '이미지로 공유하기',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 5개 카드마다 배너 광고, 30번째 명언마다 전면 광고를 삽입한 리스트
  Widget _buildQuoteListWithAds() {
    const int bannerFrequency = 5; // 명언 5개당 배너 광고 1회
    const int interstitialFrequency = 30; // 명언 30개마다 전면 광고 1회
    final int adCount = _quotes.length ~/ bannerFrequency;
    final int totalItems = _quotes.length + adCount;

    return ListView.builder(
      controller: _quoteScrollController,
      padding: EdgeInsets.zero,
      itemCount: totalItems,
      itemBuilder: (context, listIndex) {
        // 배너 광고 슬롯 여부
        final bool isBannerAd = (listIndex + 1) % (bannerFrequency + 1) == 0;
        if (isBannerAd) {
          return const _BannerAdWidget();
        }

        final int quoteIndex = listIndex - (listIndex ~/ (bannerFrequency + 1));
        if (quoteIndex >= _quotes.length) return const SizedBox.shrink();

        // 30번째 명언마다 전면 광고 트리거 (29, 59, 89 ... 번째 인덱스)
        final scrollDirection = _quoteScrollController.hasClients
            ? _quoteScrollController.position.userScrollDirection
            : ScrollDirection.idle;
        final interstitialKey = _interstitialKey(quoteIndex, scrollDirection);
        if (quoteIndex > 0 &&
            (quoteIndex + 1) % interstitialFrequency == 0 &&
            scrollDirection != ScrollDirection.idle &&
            !_shownInterstitialKeys.contains(interstitialKey)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showInterstitialAd(quoteIndex, scrollDirection);
          });
        }

        final quote = _quotes[quoteIndex];
        final quoteId = _extractQuoteId(quote);
        return _buildContentBox(
          '${quote['resoner_kr']}',
          quote['text_kr'],
          quoteId,
          quote['tag_kr']?.toString(),
          quote['imagefile']?.toString(),
          quote['resoner_eng']?.toString(),
          quoteIndex == 0,
        );
      },
    );
  }
}

class _AnimatedCardItem extends StatefulWidget {
  final Widget child;
  const _AnimatedCardItem({required this.child});

  @override
  State<_AnimatedCardItem> createState() => _AnimatedCardItemState();
}

class _AnimatedCardItemState extends State<_AnimatedCardItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(opacity: _fadeAnimation, child: widget.child),
    );
  }
}

// 배너 광고 위젯
class _BannerAdWidget extends StatefulWidget {
  const _BannerAdWidget();

  @override
  State<_BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends State<_BannerAdWidget> {
  BannerAd? _bannerAd;
  bool _isLoaded = false;

  @override
  void initState() {
    super.initState();
    BannerAd(
      adUnitId: AdHelper.bannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (mounted) {
            setState(() {
              _bannerAd = ad as BannerAd;
              _isLoaded = true;
            });
          }
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
        },
      ),
    ).load();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoaded || _bannerAd == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 16.0),
      alignment: Alignment.center,
      width: _bannerAd!.size.width.toDouble(),
      height: _bannerAd!.size.height.toDouble(),
      child: AdWidget(ad: _bannerAd!),
    );
  }
}
