import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:like_button/like_button.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:math';
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

  // 공유하기 함수
  void _shareContent(String title, String content) async {
    try {
      await Share.share(
        '$title\n\n$content\n\n공유됨 - Healing Hi 앱',
        subject: title,
      );
      await _incrementShareCount();
    } catch (e) {
      // 공유 기능이 실패하면 클립보드에 복사
      await Clipboard.setData(
        ClipboardData(text: '$title\n\n$content\n\n공유됨 - Healing Hi 앱'),
      );
      await _incrementShareCount();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('내용이 클립보드에 복사되었습니다!')));
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
                  child: _getResonerImagePath(quoteId) != null
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
              // 공유 버튼
              IconButton(
                onPressed: () {
                  _shareContent(title, content);
                },
                icon: Icon(Icons.share, color: Colors.grey[600]),
                iconSize: 24,
                tooltip: '공유하기',
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
