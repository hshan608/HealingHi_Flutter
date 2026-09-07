import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'installation_identity.dart';
import 'quote_share.dart';
import 'resoner_image_helper.dart';
import 'tutorial.dart';

// Supabase 클라이언트 전역 변수
final supabase = Supabase.instance.client;

// 튜토리얼에서 예시로 보여줄 명언 ID (실제 보관 여부와 무관하게 고정)
const _tutorialSampleQuoteId = '10001';

// 보관함 화면
class BookmarkScreen extends StatefulWidget {
  const BookmarkScreen({super.key, this.isTutorialActive = false});

  // 보관함 튜토리얼이 표시되는 동안에만 예시 카드를 노출한다.
  final bool isTutorialActive;

  @override
  State<BookmarkScreen> createState() => _BookmarkScreenState();
}

class _BookmarkScreenState extends State<BookmarkScreen> {
  final List<Map<String, dynamic>> _savedQuotes = [];
  bool _isLoading = true;
  String? _deviceId;
  int? _userIdx;
  Map<String, String> _requestQuoteImages = {}; // 'req_42' -> image_url
  Map<String, dynamic>? _tutorialSampleQuote;

  @override
  void initState() {
    super.initState();
    ResonerImageHelper.load();
    _initUserIdentity();
    if (widget.isTutorialActive) {
      _loadTutorialSampleQuote();
    }
  }

  @override
  void didUpdateWidget(covariant BookmarkScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isTutorialActive && !oldWidget.isTutorialActive) {
      _loadTutorialSampleQuote();
    }
  }

  // 튜토리얼용 예시 명언은 보관함이 비어 있어도 항상 같은 카드를 보여준다.
  Future<void> _loadTutorialSampleQuote() async {
    if (_tutorialSampleQuote != null) return;
    try {
      await ResonerImageHelper.load();
      final quote = await supabase
          .from('quotes')
          .select()
          .eq('id', _tutorialSampleQuoteId)
          .maybeSingle();
      if (!mounted || quote == null) return;
      setState(() {
        _tutorialSampleQuote = Map<String, dynamic>.from(quote);
      });
    } catch (e) {
      print('튜토리얼 예시 명언 로드 실패: $e');
    }
  }

  Future<void> _initUserIdentity() async {
    try {
      final deviceId = InstallationIdentity.id;
      _deviceId = deviceId;

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
    await ResonerImageHelper.load();
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

  // 명언 카드를 이미지로 캡처해서 공유 (홈 화면과 동일한 공용 로직)
  Future<void> _shareContent(
    String title,
    String content,
    ImageProvider<Object>? authorImage,
  ) async {
    if (!mounted) return;
    await QuoteShare.shareAsImage(
      context: context,
      author: title,
      content: content,
      authorImage: authorImage,
      onShared: _incrementShareCount,
    );
  }

  @override
  Widget build(BuildContext context) {
    // 튜토리얼 중에는 예시 카드를 맨 위에 두어 강조 대상이 항상 존재하게 한다.
    final sampleQuote = widget.isTutorialActive ? _tutorialSampleQuote : null;
    final displayQuotes = <Map<String, dynamic>>[
      if (sampleQuote != null) sampleQuote,
      ..._savedQuotes.where(
        (quote) =>
            sampleQuote == null ||
            quote['id']?.toString() != _tutorialSampleQuoteId,
      ),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF8E3DE),
      body: SafeArea(
        bottom: false,
        minimum: const EdgeInsets.only(top: 61),
        child: Padding(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(
                height: 43,
                width: double.infinity,
                child: Center(
                  child: Text(
                    '오래 간직하고 싶은 문장을 모아보세요.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF595959),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : displayQuotes.isEmpty
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
                          padding: const EdgeInsets.fromLTRB(27, 5, 27, 5),
                          itemCount: displayQuotes.length,
                          itemBuilder: (context, index) {
                            final quote = displayQuotes[index];
                            final quoteId = quote['id']?.toString();
                            final isSample = sampleQuote != null && index == 0;
                            return _AnimatedBookmarkCard(
                              key: ValueKey(
                                isSample ? 'tutorial_sample' : quoteId,
                              ),
                              title: '${quote['resoner_kr']}',
                              content: quote['text_kr'],
                              quoteId: quoteId,
                              tag: quote['tag_kr']?.toString(),
                              resonerImagePath: ResonerImageHelper.resolve(
                                quote['imagefile']?.toString(),
                                quote['resoner_eng']?.toString(),
                              ),
                              requestImageUrl: _requestQuoteImages[quoteId],
                              isTutorialTarget: index == 0,
                              isSample: isSample,
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
  final bool isTutorialTarget;
  final bool isSample;
  final Future<void> Function(String?) onRemoveFromDB;
  final void Function(String?) onRemoveFromList;
  final Future<void> Function(String, String, ImageProvider<Object>?) onShare;

  const _AnimatedBookmarkCard({
    super.key,
    required this.title,
    required this.content,
    this.quoteId,
    this.tag,
    this.resonerImagePath,
    this.requestImageUrl,
    required this.isTutorialTarget,
    this.isSample = false,
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
    _fadeAnimation = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeIn));
  }

  @override
  void dispose() {
    _heartController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  Future<void> _handleUnlike() async {
    // 예시 카드는 실제 보관 항목이 아니므로 삭제하지 않는다.
    if (widget.isSample || _isRemoving) return;
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
          margin: const EdgeInsets.only(bottom: 18),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 23),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(25),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 상단: 프로필 이미지 + 저자명
              Row(
                children: [
                  ClipOval(
                    child: Container(
                      width: 50,
                      height: 50,
                      color: Colors.grey[200],
                      child: widget.requestImageUrl != null
                          ? Image.network(
                              widget.requestImageUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  Icon(
                                    Icons.person,
                                    size: 20,
                                    color: Colors.grey[400],
                                  ),
                            )
                          : widget.resonerImagePath != null
                          ? Image.asset(
                              widget.resonerImagePath!,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  Icon(
                                    Icons.person,
                                    size: 20,
                                    color: Colors.grey[400],
                                  ),
                            )
                          : Icon(
                              Icons.person,
                              size: 20,
                              color: Colors.grey[400],
                            ),
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              // 명언 텍스트
              Text(
                widget.content,
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
                  if (widget.tag != null && widget.tag!.isNotEmpty)
                    Container(
                      height: 32,
                      alignment: Alignment.center,
                      // Figma Tag BG: 텍스트 좌 9 / 우 11, 높이 32의 완전한 필 형태
                      padding: const EdgeInsets.only(left: 9, right: 11),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F5F5),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        '# ${widget.tag}',
                        style: const TextStyle(
                          fontSize: 16,
                          color: Color(0xFF9E9E9E),
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                  const Spacer(),
                  // 하트 버튼 (커스텀 애니메이션)
                  GestureDetector(
                    key: widget.isTutorialTarget
                        ? TutorialTargets.bookmarkLike
                        : null,
                    onTap: _isRemoving ? null : _handleUnlike,
                    child: AnimatedBuilder(
                      animation: _heartScale,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: _heartScale.value,
                          child: child,
                        );
                      },
                      child: SvgPicture.asset(
                        'assets/icon/figma_saved_heart.svg',
                        width: 23,
                        height: 19,
                      ),
                    ),
                  ),
                  const SizedBox(width: 70),
                  // 공유 버튼
                  IconButton(
                    onPressed: () => widget.onShare(
                      widget.title,
                      widget.content,
                      widget.requestImageUrl != null
                          ? NetworkImage(widget.requestImageUrl!)
                          : widget.resonerImagePath != null
                          ? AssetImage(widget.resonerImagePath!)
                          : null,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 18,
                      height: 20,
                    ),
                    style: IconButton.styleFrom(
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: SvgPicture.asset(
                      'assets/icon/figma_card_share.svg',
                      width: 18,
                      height: 20,
                    ),
                    tooltip: '공유하기',
                  ),
                  const SizedBox(width: 19),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
