import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';
import 'dart:convert';

// Supabase 클라이언트 전역 변수
final supabase = Supabase.instance.client;

// 보관함 화면
class BookmarkScreen extends StatefulWidget {
  const BookmarkScreen({super.key});

  @override
  State<BookmarkScreen> createState() => _BookmarkScreenState();
}

class _BookmarkScreenState extends State<BookmarkScreen> {
  final List<Map<String, dynamic>> _savedQuotes = [];
  bool _isLoading = true;
  String? _deviceId;
  int? _userIdx;
  Map<String, String> _resonerImages = {}; // quoteId -> imagePath 매핑
  Map<String, String> _requestQuoteImages = {}; // 'req_42' -> image_url

  @override
  void initState() {
    super.initState();
    _loadResonerImages();
    _initUserIdentity();
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

      if (deviceId == null) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      final user = await supabase
          .from('users')
          .select('idx')
          .eq('device_id', deviceId)
          .maybeSingle();

      if (user != null) {
        _userIdx = _toInt(user['idx']);
      }

      await _loadSavedQuotes();
    } catch (e) {
      print('보관함 사용자 식별자 로드 실패: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadSavedQuotes() async {
    final userIdx = _userIdx;
    if (userIdx == null) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('사용자 정보를 불러올 수 없습니다. 프로필을 먼저 저장해주세요.')),
        );
      }
      return;
    }

    try {
      final userQuotes = await supabase
          .from('users_quotes')
          .select('quotes_id')
          .eq('user_idx', userIdx);

      final quoteIds = userQuotes
          .map<String?>((row) => row['quotes_id']?.toString())
          .where((id) => id != null && id!.isNotEmpty)
          .cast<String>()
          .toList();

      if (quoteIds.isEmpty) {
        setState(() {
          _savedQuotes.clear();
          _isLoading = false;
        });
        return;
      }

      final quotes = await supabase
          .from('quotes')
          .select()
          .inFilter('id', quoteIds);

      final quoteList = List<Map<String, dynamic>>.from(quotes);

      // req_ 접두어 명언의 이미지 일괄 조회
      final reqIds = quoteList
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
        _savedQuotes
          ..clear()
          ..addAll(quoteList);
        _isLoading = false;
      });
    } catch (e) {
      print('보관함 로드 실패: $e');
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('보관함을 불러오지 못했습니다: $e')));
      }
    }
  }

  // Supabase에서 북마크 삭제 (애니메이션과 분리)
  Future<void> _deleteFromSupabase(String? quoteId) async {
    if (quoteId == null || _userIdx == null) return;
    try {
      await supabase
          .from('users_quotes')
          .delete()
          .eq('user_idx', _userIdx!)
          .eq('quotes_id', quoteId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('삭제 중 오류가 발생했습니다: $e')));
      }
    }
  }

  // 애니메이션 완료 후 리스트에서 제거
  void _removeFromList(String? quoteId) {
    if (!mounted) return;
    setState(() {
      _savedQuotes.removeWhere((quote) => quote['id']?.toString() == quoteId);
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('보관함에서 삭제되었습니다.')));
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

  void _shareContent(String title, String content) async {
    try {
      await Share.share(
        '$title\n\n$content\n\n공유됨 - Healing Hi 앱',
        subject: title,
      );
      await _incrementShareCount();
    } catch (e) {
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
      backgroundColor: const Color(0xFFF8E3DF),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24.0, 24.0, 24.0, 32.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Text(
                    '보관함',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _savedQuotes.isEmpty
                    ? const Center(
                        child: Text(
                          '보관한 명언이 없습니다.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 16),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadSavedQuotes,
                        child: ListView.builder(
                          padding: const EdgeInsets.only(top: 10.0),
                          itemCount: _savedQuotes.length,
                          itemBuilder: (context, index) {
                            final quote = _savedQuotes[index];
                            final quoteId = quote['id']?.toString();
                            return _AnimatedBookmarkCard(
                              key: ValueKey(quoteId),
                              title: '${quote['resoner_kr']}',
                              content: quote['text_kr'],
                              quoteId: quoteId,
                              tag: quote['tag_kr']?.toString(),
                              resonerImagePath: _getResonerImagePath(quoteId),
                              requestImageUrl: _requestQuoteImages[quoteId],
                              onRemoveFromDB: _deleteFromSupabase,
                              onRemoveFromList: _removeFromList,
                              onShare: _shareContent,
                            );
                          },
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return null;
  }
}

// 애니메이션이 있는 북마크 카드 위젯
class _AnimatedBookmarkCard extends StatefulWidget {
  final String title;
  final String content;
  final String? quoteId;
  final String? tag;
  final String? resonerImagePath;
  final String? requestImageUrl;
  final Future<void> Function(String?) onRemoveFromDB;
  final void Function(String?) onRemoveFromList;
  final void Function(String, String) onShare;

  const _AnimatedBookmarkCard({
    super.key,
    required this.title,
    required this.content,
    this.quoteId,
    this.tag,
    this.resonerImagePath,
    this.requestImageUrl,
    required this.onRemoveFromDB,
    required this.onRemoveFromList,
    required this.onShare,
  });

  @override
  State<_AnimatedBookmarkCard> createState() => _AnimatedBookmarkCardState();
}

class _AnimatedBookmarkCardState extends State<_AnimatedBookmarkCard>
    with TickerProviderStateMixin {
  late final AnimationController _heartController;
  late final AnimationController _slideController;
  late final Animation<double> _heartScale;
  late final Animation<Offset> _slideAnimation;
  late final Animation<double> _fadeAnimation;
  bool _isRemoving = false;

  @override
  void initState() {
    super.initState();

    // 하트 애니메이션: 살짝 커졌다가 0으로 줄어듦
    _heartController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _heartScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.35), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1.35, end: 0.0), weight: 80),
    ]).animate(CurvedAnimation(parent: _heartController, curve: Curves.easeIn));

    // 카드 슬라이드 + 페이드 애니메이션
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _slideAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(1.5, 0),
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeIn));
    _fadeAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.easeIn),
    );
  }

  @override
  void dispose() {
    _heartController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  Future<void> _handleUnlike() async {
    if (_isRemoving) return;
    _isRemoving = true;

    // Supabase 삭제를 백그라운드에서 시작 (애니메이션과 병렬)
    widget.onRemoveFromDB(widget.quoteId);

    // 하트 축소 애니메이션
    await _heartController.forward();

    // 카드 오른쪽 슬라이드 애니메이션
    await _slideController.forward();

    // 리스트에서 제거
    widget.onRemoveFromList(widget.quoteId);
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
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
                      child: widget.requestImageUrl != null
                          ? Image.network(
                              widget.requestImageUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  Icon(Icons.person, size: 20, color: Colors.grey[400]),
                            )
                          : widget.resonerImagePath != null
                              ? Image.asset(
                                  widget.resonerImagePath!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) =>
                                      Icon(Icons.person, size: 20, color: Colors.grey[400]),
                                )
                              : Icon(Icons.person, size: 20, color: Colors.grey[400]),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    widget.title,
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
                widget.content,
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
                  if (widget.tag != null && widget.tag!.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '# ${widget.tag}',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  const Spacer(),
                  // 하트 버튼 (커스텀 애니메이션)
                  GestureDetector(
                    onTap: _isRemoving ? null : _handleUnlike,
                    child: AnimatedBuilder(
                      animation: _heartScale,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: _heartScale.value,
                          child: child,
                        );
                      },
                      child: Image.asset(
                        'assets/heart2.png',
                        width: 32,
                        height: 32,
                      ),
                    ),
                  ),
                  // 공유 버튼
                  IconButton(
                    onPressed: () => widget.onShare(widget.title, widget.content),
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
}
