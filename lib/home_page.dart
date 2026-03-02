import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:like_button/like_button.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;
import 'ad_helper.dart';

// Supabase 클라이언트 전역 변수
final supabase = Supabase.instance.client;

// 메인 화면
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Map<String, dynamic>> _quotes = [];
  bool _isLoading = true;
  String? _deviceId;
  int? _userIdx;
  bool _isSavingLike = false;
  Set<String> _savedQuoteIds = {};
  Map<String, String> _resonerImages = {}; // quoteId -> imagePath 매핑
  Map<String, String> _requestQuoteImages = {}; // 'req_42' -> image_url

  // 전면 광고
  InterstitialAd? _interstitialAd;
  final Set<int> _shownInterstitialAtIndex = {}; // 이미 광고를 보인 quote 인덱스

  @override
  void initState() {
    super.initState();
    _loadResonerImages();
    _loadQuotes();
    _initUserIdentity();
    _loadInterstitialAd();
  }

  @override
  void dispose() {
    _interstitialAd?.dispose();
    super.dispose();
  }

  // 전면 광고 로드
  void _loadInterstitialAd() {
    InterstitialAd.load(
      adUnitId: AdHelper.interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              _interstitialAd = null;
              _loadInterstitialAd(); // 다음 광고 미리 로드
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              ad.dispose();
              _interstitialAd = null;
              _loadInterstitialAd();
            },
          );
          if (mounted) {
            setState(() => _interstitialAd = ad);
          }
        },
        onAdFailedToLoad: (error) {
          _interstitialAd = null;
        },
      ),
    );
  }

  // 전면 광고 표시 (quoteIndex 기준 중복 방지)
  void _showInterstitialAd(int quoteIndex) {
    if (_shownInterstitialAtIndex.contains(quoteIndex)) return;
    if (_interstitialAd == null) return;
    _shownInterstitialAtIndex.add(quoteIndex);
    _interstitialAd!.show();
  }

  // assets/resoner/ 폴더의 이미지 목록 로드
  Future<void> _loadResonerImages() async {
    try {
      final manifestContent = await rootBundle.loadString('AssetManifest.json');
      final Map<String, dynamic> manifestMap = json.decode(manifestContent);

      final resonerFiles = manifestMap.keys
          .where((path) => path.startsWith('assets/resoner/'))
          .toList();

      final Map<String, String> imageMap = {};
      for (final path in resonerFiles) {
        // 파일명에서 id 추출 (예: assets/resoner/1_name.png -> 1)
        final fileName = path.split('/').last;
        final idMatch = RegExp(r'^(\d+)_').firstMatch(fileName);
        if (idMatch != null) {
          final id = idMatch.group(1)!;
          imageMap[id] = path;
        }
      }

      if (mounted) {
        setState(() {
          _resonerImages = imageMap;
        });
      }
    } catch (e) {
      print('Resoner 이미지 로드 실패: $e');
    }
  }

  // quoteId로 이미지 경로 가져오기
  String? _getResonerImagePath(String? quoteId) {
    if (quoteId == null) return null;
    return _resonerImages[quoteId];
  }

  // Supabase에서 명언 데이터 가져오기 (랜덤 순서)
  Future<void> _loadQuotes() async {
    try {
      final response = await supabase.from('quotes').select();

      final list = List<Map<String, dynamic>>.from(response);
      list.shuffle(Random());

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

      setState(() {
        _quotes = list;
        _isLoading = false;
      });
    } catch (error) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('데이터를 불러오는데 실패했습니다: $error')));
      }
    }
  }

  // 디바이스 ID와 사용자 idx 로드
  Future<void> _initUserIdentity() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      String? deviceId;

      if (Platform.isAndroid) {
        final info = await deviceInfo.androidInfo;
        deviceId = info.id;
      } else if (Platform.isIOS) {
        final info = await deviceInfo.iosInfo;
        deviceId = info.identifierForVendor;
      } else if (Platform.isWindows) {
        final info = await deviceInfo.windowsInfo;
        deviceId = info.deviceId;
      } else if (Platform.isLinux) {
        final info = await deviceInfo.linuxInfo;
        deviceId = info.machineId;
      } else if (Platform.isMacOS) {
        final info = await deviceInfo.macOsInfo;
        deviceId = info.systemGUID;
      }

      _deviceId = deviceId;

      if (deviceId == null) return;

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

  // 공유 카드 위젯 (이미지로 캡처용 - 깔끔한 디자인)
  Widget _buildShareCardContent(String author, String content, String? tag) {
    return Container(
      width: 375,
      color: const Color(0xFFDDE7DE),
      padding: const EdgeInsets.all(24),
      child: Container(
        padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 따옴표 장식
            const Text(
              '"',
              style: TextStyle(
                fontSize: 56,
                color: Color(0xFF9DC3A0),
                height: 0.8,
                fontWeight: FontWeight.bold,
                fontFamily: 'Pretendard',
              ),
            ),
            const SizedBox(height: 16),
            // 명언 텍스트
            Text(
              content,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w300,
                color: Color(0xFF333333),
                height: 1.7,
                fontFamily: 'Pretendard',
              ),
            ),
            const SizedBox(height: 24),
            // 저자
            Text(
              '— $author',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: Colors.grey[600],
                fontFamily: 'Pretendard',
              ),
            ),
            if (tag != null && tag.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFDDE7DE),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '# $tag',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF5D8A62),
                    fontFamily: 'Pretendard',
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            const Divider(color: Color(0xFFEEEEEE), thickness: 1),
            const SizedBox(height: 12),
            // 앱 브랜딩
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Color(0xFF7AAE80),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'Healing Hi',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF7AAE80),
                      letterSpacing: 0.5,
                      fontFamily: 'Pretendard',
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Color(0xFF7AAE80),
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
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
    required String? tag,
    required String? quoteId,
  }) async {
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
            child: _buildShareCardContent(author, content, tag),
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

      final boundary = key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw Exception('카드 렌더링 실패');

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception('이미지 변환 실패');

      final pngBytes = byteData.buffer.asUint8List();
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/healinghi_quote.png');
      await file.writeAsBytes(pngBytes);

      entry.remove();

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png')],
        subject: '명언 - $author',
      );
      await _incrementShareCount();
    } catch (e) {
      entry.remove();
      if (mounted) {
        // 실패 시 텍스트 클립보드 복사로 폴백
        await Clipboard.setData(
          ClipboardData(text: '$author\n\n$content\n\nHealing Hi'),
        );
        await _incrementShareCount();
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
        child: Padding(
          padding: const EdgeInsets.only(left: 24.0, right: 24.0, top: 32.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 박스 리스트
              Expanded(
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContentBox(String title, String content, String? quoteId, String? tag) {
    return _AnimatedCardItem(
      child: GestureDetector(
      onDoubleTap: () async {
        await Clipboard.setData(
          ClipboardData(text: '$title\n\n$content\n\n공유됨 - Healing Hi 앱'),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('클립보드에 복사되었습니다!')),
          );
        }
      },
      child: Container(
      margin: const EdgeInsets.only(bottom: 16.0),
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 28.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.0),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 상단: 프로필 이미지 + 저자명
          Row(
            children: [
              ClipOval(
                child: Container(
                  width: 36,
                  height: 36,
                  color: Colors.grey[200],
                  child: quoteId != null && _requestQuoteImages.containsKey(quoteId)
                      ? Image.network(
                          _requestQuoteImages[quoteId]!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              Icon(Icons.person, size: 20, color: Colors.grey[400]),
                        )
                      : _getResonerImagePath(quoteId) != null
                          ? Image.asset(
                              _getResonerImagePath(quoteId)!,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Icon(Icons.person, size: 20, color: Colors.grey[400]);
                              },
                            )
                          : Icon(Icons.person, size: 20, color: Colors.grey[400]),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // 명언 텍스트
          Text(
            content,
            textAlign: TextAlign.left,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w300,
              color: Colors.grey[800],
              height: 1.6,
            ),
          ),
          const SizedBox(height: 16),
          // 하단: 태그 + 좋아요/공유 버튼
          Row(
            children: [
              // 태그
              if (tag != null && tag.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '# $tag',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              const Spacer(),
              // 좋아요 버튼
              LikeButton(
                size: 32,
                isLiked: quoteId != null && _savedQuoteIds.contains(quoteId),
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
                    isLiked ? 'assets/heart2.png' : 'assets/heart1.png',
                    width: 32,
                    height: 32,
                  );
                },
                onTap: (bool isLiked) async {
                  await _toggleUserQuote(quoteId);
                  return !isLiked;
                },
              ),
              // 공유 버튼 (이미지 카드로 공유)
              IconButton(
                onPressed: () {
                  _captureAndShareQuoteImage(
                    author: title,
                    content: content,
                    tag: tag,
                    quoteId: quoteId,
                  );
                },
                icon: Icon(Icons.share, color: Colors.grey[600]),
                iconSize: 24,
                tooltip: '이미지로 공유하기',
              ),
            ],
          ),
        ],
      ),
      ),
    ),
    );
  }

  // 5개 카드마다 배너 광고, 10번째 명언마다 전면 광고를 삽입한 리스트
  Widget _buildQuoteListWithAds() {
    const int bannerFrequency = 5;  // 명언 5개당 배너 광고 1회
    const int interstitialFrequency = 10; // 명언 10개마다 전면 광고 1회
    final int adCount = _quotes.length ~/ bannerFrequency;
    final int totalItems = _quotes.length + adCount;

    return ListView.builder(
      padding: const EdgeInsets.only(top: 20.0),
      itemCount: totalItems,
      itemBuilder: (context, listIndex) {
        // 배너 광고 슬롯 여부
        final bool isBannerAd = (listIndex + 1) % (bannerFrequency + 1) == 0;
        if (isBannerAd) {
          return const _BannerAdWidget();
        }

        final int quoteIndex = listIndex - (listIndex ~/ (bannerFrequency + 1));
        if (quoteIndex >= _quotes.length) return const SizedBox.shrink();

        // 10번째 명언마다 전면 광고 트리거 (9, 19, 29 ... 번째 인덱스)
        if (quoteIndex > 0 &&
            (quoteIndex + 1) % interstitialFrequency == 0 &&
            !_shownInterstitialAtIndex.contains(quoteIndex)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showInterstitialAd(quoteIndex);
          });
        }

        final quote = _quotes[quoteIndex];
        final quoteId = _extractQuoteId(quote);
        return _buildContentBox(
          '${quote['resoner_kr']}',
          quote['text_kr'],
          quoteId,
          quote['tag_kr']?.toString(),
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
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));
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
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: widget.child,
      ),
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
