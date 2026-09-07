import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:like_button/like_button.dart';
import 'installation_identity.dart';
import 'resoner_image_helper.dart';
import 'tutorial.dart';

// Supabase 클라이언트 전역 변수
final supabase = Supabase.instance.client;

// ---- Figma 검색 화면 공통 색상 ----
const Color _appGreen = Color(0xFF81A684); // 선택 탭·확인하기·공유 아이콘
const Color _headerBackground = Color(0xFFDDE7DE); // 헤더 배경
const Color _listItemBackground = Color(0xFFFAFAFA); // 저자·주제 카드, 팝업 시트 배경
const Color _listItemBorder = Color(0xFFEEEEEE); // 저자·주제 카드 테두리, 아이콘 원 배경
// 본문 카드·팝업 카드 테두리. Figma 스크린샷 픽셀 측정값(디자인 토큰 미확인).
const Color _quoteCardBorder = Color(0xFFA7C1A9);
const Color _chipBackground = Color(0xFFF5F5F5); // 태그 칩 배경
const Color _chipText = Color(0xFF9E9E9E); // 태그 칩 글자
const Color _mutedGrey = Color(0xFF757575); // 안내 문구, 핸들, 하트 기본색
const Color _likeActive = Color(0xFFFF8788); // Figma Like Toggle 활성 색
const Color _quoteText = Color(0xFF595959); // 본문 카드 명언 글자
const Color _quoteHighlight = Color(0xFF414141); // 본문 카드 검색어 강조
const Color _popupQuoteText = Color(0xFF333333); // 팝업 카드 명언 글자

// ---- Figma 검색 화면 공통 치수 ----
const double _listTopPadding = 29; // 헤더 하단 → 첫 카드
const double _listItemGap = 25; // 저자·주제 카드 간격
const double _quoteCardGap = 27; // 본문 카드 간격
const EdgeInsets _listItemListPadding = EdgeInsets.fromLTRB(
  25,
  _listTopPadding,
  25,
  _listTopPadding,
);
const EdgeInsets _quoteCardListPadding = EdgeInsets.fromLTRB(
  28,
  _listTopPadding,
  28,
  _listTopPadding,
);

// 서치 화면
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  List<Map<String, dynamic>> _allQuotes = [];
  List<Map<String, dynamic>> _filteredQuotes = [];
  List<String> _uniqueAuthors = []; // 저자 검색용 고유 저자 목록
  List<String> _uniqueSubjects = []; // 주제 검색용 고유 주제 목록
  bool _isLoading = true;
  String _searchType = 'author'; // 'author', 'content', 또는 'subject'
  bool _hasSearched = false;
  String? _deviceId;
  int? _userIdx;
  bool _isSavingLike = false;
  Set<String> _savedQuoteIds = {};
  Map<String, String> _authorImageFileMap = {}; // resoner_kr -> imagefile
  Map<String, String> _authorEngMap = {}; // resoner_kr -> resoner_eng
  Map<String, String> _requestQuoteImages = {}; // 'req_42' -> image_url

  @override
  void initState() {
    super.initState();
    ResonerImageHelper.load();
    _loadQuotes();
    _initUserIdentity();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  // resoner_kr로 저자 이미지 경로 가져오기
  String? _getAuthorImagePath(String authorKr) {
    final imageFile = _authorImageFileMap[authorKr];
    final engName = _authorEngMap[authorKr];
    return ResonerImageHelper.resolve(imageFile, engName);
  }

  // Supabase에서 명언 데이터 가져오기
  Future<void> _loadQuotes() async {
    await ResonerImageHelper.load();
    try {
      final response = await supabase
          .from('quotes')
          .select()
          .order('created_at', ascending: false);

      final quotes = List<Map<String, dynamic>>.from(response);

      // resoner_kr -> imagefile / resoner_eng 매핑 생성
      final Map<String, String> imageFileMap = {};
      final Map<String, String> engMap = {};
      for (final quote in quotes) {
        final kr = quote['resoner_kr']?.toString();
        final imageFile = quote['imagefile']?.toString();
        final eng = quote['resoner_eng']?.toString();
        if (kr != null) {
          if (imageFile != null && imageFile.isNotEmpty) {
            imageFileMap[kr] = imageFile;
          }
          if (eng != null && eng.isNotEmpty) engMap[kr] = eng;
        }
      }

      // req_ 접두어 명언의 이미지 일괄 조회
      final reqIds = quotes
          .map((q) => q['id']?.toString())
          .where((id) => id != null && id.startsWith('req_'))
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
        _allQuotes = quotes;
        _filteredQuotes = _allQuotes; // 초기에는 모든 명언 표시
        _authorImageFileMap = imageFileMap;
        _authorEngMap = engMap;
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
      debugPrint('사용자 식별자 로드 실패: $e');
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
      debugPrint('저장된 명언 ID 로드 실패: $e');
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

  // 검색 함수
  void _performSearch(String query) {
    if (query.isEmpty) {
      setState(() {
        _filteredQuotes = [];
        _uniqueAuthors = [];
        _uniqueSubjects = [];
        _hasSearched = false;
      });
      return;
    }

    setState(() {
      _hasSearched = true;
      if (_searchType == 'author') {
        // 저자 검색: resoner_kr만 검색하고 중복 제거 (group by)
        final matchingAuthors = _allQuotes
            .where(
              (quote) => quote['resoner_kr'].toString().toLowerCase().contains(
                query.toLowerCase(),
              ),
            )
            .map((quote) => quote['resoner_kr'].toString())
            .toSet()
            .toList();
        _uniqueAuthors = matchingAuthors;
        _uniqueSubjects = [];
        _filteredQuotes = [];
      } else if (_searchType == 'content') {
        // 본문 검색: text_kr만 검색
        _filteredQuotes = _allQuotes.where((quote) {
          return quote['text_kr'].toString().toLowerCase().contains(
            query.toLowerCase(),
          );
        }).toList();
        _uniqueAuthors = [];
        _uniqueSubjects = [];
      } else {
        // 주제 검색: tag_kr을 검색하고 중복 제거 (group by)
        final matchingSubjects = _allQuotes
            .where(
              (quote) => (quote['tag_kr']?.toString() ?? '')
                  .toLowerCase()
                  .contains(query.toLowerCase()),
            )
            .map((quote) => quote['tag_kr']?.toString() ?? '')
            .where((tag) => tag.isNotEmpty)
            .toSet()
            .toList();
        _uniqueSubjects = matchingSubjects;
        _uniqueAuthors = [];
        _filteredQuotes = [];
      }
    });
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
      debugPrint('공유 카운트 업데이트 실패: $e');
    }
  }

  // 공유하기 함수
  void _shareContent(String title, String content) async {
    try {
      final shareResult = await Share.share(
        '$title\n\n$content\n\n공유됨 - Healing Hi 앱',
        subject: title,
      );
      if (shareResult.status == ShareResultStatus.success) {
        await _incrementShareCount();
      }
    } catch (e) {
      // 공유 기능이 실패하면 클립보드에 복사
      await Clipboard.setData(
        ClipboardData(text: '$title\n\n$content\n\n공유됨 - Healing Hi 앱'),
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('내용이 클립보드에 복사되었습니다!')));
      }
    }
  }

  void _selectSearchType(String type) {
    if (_searchType == type) return;
    setState(() => _searchType = type);
    _performSearch(_searchController.text);
  }

  /// 현재 검색 유형에 결과가 하나 이상 있는지
  bool get _hasResults {
    switch (_searchType) {
      case 'author':
        return _uniqueAuthors.isNotEmpty;
      case 'subject':
        return _uniqueSubjects.isNotEmpty;
      default:
        return _filteredQuotes.isNotEmpty;
    }
  }

  /// 검색 상태에 따라 바뀌는 상단 안내문(Figma Top Text 5종)
  String get _headerTitle {
    if (!_hasSearched) return '지금 필요한 문장을 찾아보세요.';
    if (!_hasResults) return '일치하는 결과를 찾지 못했어요.';
    switch (_searchType) {
      case 'author':
        return '찾으시는 저자를 선택해 주세요.';
      case 'content':
        return '검색된 문장을 확인해 보세요.';
      default:
        return '찾으시는 주제를 선택해 주세요.';
    }
  }

  Widget _buildSearchTabLabel({required String type, required String label}) {
    final isSelected = _searchType == type;

    return Expanded(
      child: Semantics(
        selected: isSelected,
        button: true,
        label: '$label 검색',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _selectSearchType(type),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                color: isSelected ? _appGreen : const Color(0xFF9BA09C),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchTabs() {
    const tabGap = SizedBox(width: 25);
    const selectedColor = _appGreen;
    const unselectedColor = Color(0xFFE5E5E5);

    return SizedBox(
      height: 50,
      child: Column(
        children: [
          Expanded(
            child: Row(
              key: TutorialTargets.searchTabs,
              children: [
                _buildSearchTabLabel(type: 'author', label: '저자'),
                tabGap,
                _buildSearchTabLabel(type: 'content', label: '본문'),
                tabGap,
                _buildSearchTabLabel(type: 'subject', label: '주제'),
              ],
            ),
          ),
          SizedBox(
            height: 4,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ColoredBox(
                    color: _searchType == 'author'
                        ? selectedColor
                        : unselectedColor,
                  ),
                ),
                tabGap,
                Expanded(
                  child: ColoredBox(
                    color: _searchType == 'content'
                        ? selectedColor
                        : unselectedColor,
                  ),
                ),
                tabGap,
                Expanded(
                  child: ColoredBox(
                    color: _searchType == 'subject'
                        ? selectedColor
                        : unselectedColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: _headerBackground,
        body: SafeArea(
          bottom: false,
          minimum: const EdgeInsets.only(top: 61),
          child: Column(
            children: [
              SizedBox(
                height: 43,
                width: double.infinity,
                child: Center(
                  child: Text(
                    _headerTitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF595959),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 29),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 25),
                child: Container(
                  height: 63,
                  padding: const EdgeInsets.symmetric(horizontal: 30),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: const Color(0xFFEFEFEF)),
                  ),
                  child: Row(
                    children: [
                      SvgPicture.asset(
                        'assets/icon/figma_search.svg',
                        width: 33,
                        height: 33,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(width: 25),
                      Expanded(
                        child: TextField(
                          key: TutorialTargets.searchField,
                          controller: _searchController,
                          focusNode: _searchFocusNode,
                          onChanged: _performSearch,
                          keyboardType: TextInputType.text,
                          textInputAction: TextInputAction.search,
                          enableInteractiveSelection: true,
                          onSubmitted: _performSearch,
                          onTap: () {
                            SystemChannels.textInput.invokeMethod(
                              'TextInput.show',
                            );
                          },
                          // Figma: 입력값도 힌트와 같이 좌측 정렬
                          textAlign: TextAlign.left,
                          textAlignVertical: TextAlignVertical.center,
                          cursorColor: _appGreen,
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF414141),
                          ),
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: '검색어를 입력해 주세요.',
                            hintStyle: const TextStyle(
                              color: Color(0xFF9E9E9E),
                              fontSize: 19,
                              fontWeight: FontWeight.w400,
                            ),
                            suffixIcon: _searchController.text.isNotEmpty
                                ? IconButton(
                                    onPressed: () {
                                      _searchController.clear();
                                      _performSearch('');
                                    },
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    icon: const Icon(
                                      Icons.close,
                                      color: Color(0xFF9E9E9E),
                                      size: 20,
                                    ),
                                  )
                                : null,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 29),
              _buildSearchTabs(),
              Expanded(
                child: Container(
                  width: double.infinity,
                  color: Colors.white,
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _buildSearchResults(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 검색 결과 위젯 빌드
  Widget _buildSearchResults() {
    // 검색하지 않은 상태
    if (!_hasSearched) {
      return _buildGuideMessage(
        icon: SvgPicture.asset(
          'assets/icon/figma_search_guide.svg',
          width: 62,
          height: 122,
        ),
        title: '검색하고 싶은 항목을 우선 선택해주세요.',
        subtitle: '저자, 본문, 주제, 어느 것을 찾고 싶으세요?',
      );
    }

    if (!_hasResults) {
      return _buildNoResultsWidget();
    }

    // 저자 검색인 경우
    if (_searchType == 'author') {
      return RefreshIndicator(
        onRefresh: _loadQuotes,
        child: ListView.separated(
          padding: _listItemListPadding,
          itemCount: _uniqueAuthors.length,
          separatorBuilder: (_, _) => const SizedBox(height: _listItemGap),
          itemBuilder: (context, index) =>
              _buildAuthorItem(_uniqueAuthors[index]),
        ),
      );
    }

    // 주제 검색인 경우
    if (_searchType == 'subject') {
      return RefreshIndicator(
        onRefresh: _loadQuotes,
        child: ListView.separated(
          padding: _listItemListPadding,
          itemCount: _uniqueSubjects.length,
          separatorBuilder: (_, _) => const SizedBox(height: _listItemGap),
          itemBuilder: (context, index) =>
              _buildSubjectItem(_uniqueSubjects[index]),
        ),
      );
    }

    // 본문 검색인 경우
    return RefreshIndicator(
      onRefresh: _loadQuotes,
      child: ListView.separated(
        padding: _quoteCardListPadding,
        itemCount: _filteredQuotes.length,
        separatorBuilder: (_, _) => const SizedBox(height: _quoteCardGap),
        itemBuilder: (context, index) {
          final quote = _filteredQuotes[index];
          final quoteId = _extractQuoteId(quote);
          return _buildContentBox(
            '${quote['resoner_kr']}',
            quote['text_kr'],
            quoteId,
            quote['tag_kr']?.toString(),
            quote['imagefile']?.toString(),
            quote['resoner_eng']?.toString(),
          );
        },
      ),
    );
  }

  /// 안내 화면 공통 레이아웃(Figma Guide: 아이콘 62×122 영역 → 7 → 제목 → 7 → 설명)
  Widget _buildGuideMessage({
    required Widget icon,
    required String title,
    required String subtitle,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(height: 122, child: Center(child: icon)),
                const SizedBox(height: 7),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: _mutedGrey,
                    height: 23 / 19,
                  ),
                ),
                const SizedBox(height: 7),
                // Figma는 1줄. 440px보다 좁은 기기에서 한 글자만 넘치지 않도록 축소한다.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    softWrap: false,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w300,
                      color: Colors.black,
                      height: 19 / 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 검색 결과 없음 위젯
  Widget _buildNoResultsWidget() {
    return _buildGuideMessage(
      // Figma는 62×62 슬픈 얼굴 벡터. 동일 SVG 자산이 없어 Material 아이콘으로 대체.
      icon: const Icon(
        Icons.sentiment_dissatisfied_outlined,
        size: 62,
        color: _mutedGrey,
      ),
      title: '아직 추가되지 않은 내용이에요.',
      subtitle: '공유 달성도를 달성하면 자유롭게 추가 요청을 할 수 있어요.',
    );
  }

  // 저자의 명언 목록 팝업
  void _showAuthorQuotesDialog(String author) {
    final authorQuotes = _allQuotes
        .where((q) => q['resoner_kr']?.toString() == author)
        .toList();

    _showQuotesBottomSheet(
      title: author,
      leading: _buildAuthorAvatar(author, size: 73),
      quotes: authorQuotes,
      authorOf: (_) => author,
    );
  }

  // 주제의 명언 목록 팝업
  void _showSubjectQuotesDialog(String subject) {
    final subjectQuotes = _allQuotes
        .where((q) => q['tag_kr']?.toString() == subject)
        .toList();

    _showQuotesBottomSheet(
      title: subject,
      leading: _buildSubjectIcon(size: 73, iconSize: 40),
      quotes: subjectQuotes,
      authorOf: (quote) => quote['resoner_kr']?.toString() ?? '',
    );
  }

  /// 저자·주제 공통 결과 팝업(Figma Pop up 49:3726 / 49:3842)
  void _showQuotesBottomSheet({
    required String title,
    required Widget leading,
    required List<Map<String, dynamic>> quotes,
    required String Function(Map<String, dynamic> quote) authorOf,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.62),
      builder: (context) {
        final bottomInset = MediaQuery.paddingOf(context).bottom;
        return DraggableScrollableSheet(
          // Figma: 안내 라벨 23 + 간격 20 + 시트 739 = 782 / 956
          initialChildSize: 0.82,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return Column(
              children: [
                // 스크림 위 스와이프 안내 라벨
                const SizedBox(
                  height: 23,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '위로 올려 더 보기 / 아래로 내려 돌아가기',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFFCBCBCB),
                          fontSize: 17,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      color: _listItemBackground,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(14),
                      ),
                    ),
                    child: Column(
                      children: [
                        const SizedBox(height: 19),
                        // 핸들 바
                        Container(
                          width: 48,
                          height: 4,
                          decoration: BoxDecoration(
                            color: _mutedGrey,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(height: 19),
                        // Info 행: 아바타 · 이름 · 명언 개수
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 35),
                          child: SizedBox(
                            height: 79,
                            child: Row(
                              children: [
                                leading,
                                const SizedBox(width: 30),
                                Expanded(
                                  child: Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.black,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '${quotes.length}개',
                                  style: const TextStyle(
                                    fontSize: 19,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.black,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 19),
                        // 명언 카드 리스트
                        Expanded(
                          child: ListView.separated(
                            controller: scrollController,
                            padding: EdgeInsets.fromLTRB(
                              15,
                              0,
                              15,
                              19 + bottomInset,
                            ),
                            itemCount: quotes.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 19),
                            itemBuilder: (context, index) {
                              final quote = quotes[index];
                              return _buildPopupQuoteCard(
                                content: quote['text_kr']?.toString() ?? '',
                                quoteId: _extractQuoteId(quote),
                                tag: quote['tag_kr']?.toString(),
                                author: authorOf(quote),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// 팝업 내 명언 카드(Figma Card: 1px 녹색 테두리, 반지름 24, 패딩 25/26/25/19)
  Widget _buildPopupQuoteCard({
    required String content,
    required String? quoteId,
    required String? tag,
    required String author,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(25, 26, 25, 19),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _quoteCardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            content,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w300,
              color: _popupQuoteText,
              height: 25 / 18,
            ),
          ),
          // Figma: 본문 하단 → Footer 상단 35
          const SizedBox(height: 35),
          _buildCardFooter(
            tag: tag,
            quoteId: quoteId,
            author: author,
            content: content,
          ),
        ],
      ),
    );
  }

  // 저자 아이템 위젯
  Widget _buildAuthorItem(String author) {
    return _buildListItem(
      onTap: () => _showAuthorQuotesDialog(author),
      leading: _buildAuthorAvatar(author, size: 59),
      title: author,
    );
  }

  // 주제 아이템 위젯
  Widget _buildSubjectItem(String subject) {
    return _buildListItem(
      onTap: () => _showSubjectQuotesDialog(subject),
      // Figma "Frame 9" 60×59: 이름 시작 위치(x=87)를 맞추기 위해 60 폭 안에 59 원을 둔다
      leading: SizedBox(
        width: 60,
        height: 59,
        child: Center(child: _buildSubjectIcon(size: 59, iconSize: 32)),
      ),
      title: subject,
    );
  }

  /// 저자·주제 공통 리스트 카드(Figma Author Card / Topic Card: 390×80)
  Widget _buildListItem({
    required VoidCallback onTap,
    required Widget leading,
    required String title,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 80,
        padding: const EdgeInsets.symmetric(horizontal: 15),
        decoration: BoxDecoration(
          color: _listItemBackground,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _listItemBorder),
        ),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: Colors.black,
                ),
              ),
            ),
            const SizedBox(width: 12),
            _buildViewAction(),
          ],
        ),
      ),
    );
  }

  /// 카드 우측 "확인하기 ▶"(Figma View Action)
  Widget _buildViewAction() {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '확인하기',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: _appGreen,
          ),
        ),
        SizedBox(width: 8),
        CustomPaint(
          size: Size(8, 12),
          painter: _RightTrianglePainter(_appGreen),
        ),
      ],
    );
  }

  /// 저자 이미지 원형 아바타
  Widget _buildAuthorAvatar(String author, {required double size}) {
    return _buildCircleImage(
      size: size,
      imagePath: _getAuthorImagePath(author),
    );
  }

  /// 원형 이미지(네트워크 → 자산 → 사람 아이콘 순으로 폴백)
  Widget _buildCircleImage({
    required double size,
    String? imagePath,
    String? networkUrl,
  }) {
    final fallback = Icon(
      Icons.person,
      size: size * 0.55,
      color: Colors.grey[500],
    );
    final Widget image;
    if (networkUrl != null) {
      image = Image.network(
        networkUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      );
    } else if (imagePath != null) {
      image = Image.asset(
        imagePath,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      );
    } else {
      image = fallback;
    }
    return ClipOval(
      child: Container(
        width: size,
        height: size,
        color: _listItemBorder,
        child: image,
      ),
    );
  }

  /// 주제 아이콘. Figma는 녹색 태그 벡터이나 동일 SVG 자산이 없어 Material 아이콘으로 대체.
  Widget _buildSubjectIcon({required double size, required double iconSize}) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: _listItemBorder,
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.local_offer_rounded, size: iconSize, color: _appGreen),
    );
  }

  /// 검색어 부분만 굵게 강조한 본문 텍스트
  Widget _buildHighlightedContent(String content) {
    final query = _searchController.text;
    final matches = query.isEmpty
        ? const <RegExpMatch>[]
        : RegExp(
            RegExp.escape(query),
            caseSensitive: false,
          ).allMatches(content).toList();
    const textStyle = TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w300,
      color: _quoteText,
      height: 25 / 18,
    );
    const highlightStyle = TextStyle(
      fontWeight: FontWeight.w700,
      color: _quoteHighlight,
    );

    if (matches.isEmpty) {
      return Text(content, style: textStyle);
    }

    final spans = <TextSpan>[];
    var currentIndex = 0;
    for (final match in matches) {
      if (match.start > currentIndex) {
        spans.add(TextSpan(text: content.substring(currentIndex, match.start)));
      }
      spans.add(
        TextSpan(
          text: content.substring(match.start, match.end),
          style: highlightStyle,
        ),
      );
      currentIndex = match.end;
    }
    if (currentIndex < content.length) {
      spans.add(TextSpan(text: content.substring(currentIndex)));
    }

    return Text.rich(
      TextSpan(children: spans),
      style: textStyle,
      semanticsLabel: content,
    );
  }

  /// 태그 칩(Figma Tag BG: 높이 32, 배경 #F5F5F5, 글자 16px #9E9E9E)
  Widget _buildTagChip(String tag) {
    return Container(
      height: 32,
      padding: const EdgeInsets.only(left: 9, right: 11),
      decoration: BoxDecoration(
        color: _chipBackground,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        widthFactor: 1,
        child: Text(
          '# $tag',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w400,
            color: _chipText,
          ),
        ),
      ),
    );
  }

  /// 카드 하단: 태그 칩 + 하트·공유 액션 그룹(Figma Footer 높이 32, Action Group 폭 130)
  Widget _buildCardFooter({
    required String? tag,
    required String? quoteId,
    required String author,
    required String content,
  }) {
    final isSaved = quoteId != null && _savedQuoteIds.contains(quoteId);
    return Row(
      children: [
        Expanded(
          child: tag != null && tag.isNotEmpty
              ? Align(
                  alignment: Alignment.centerLeft,
                  child: _buildTagChip(tag),
                )
              : const SizedBox.shrink(),
        ),
        SizedBox(
          width: 130,
          height: 32,
          child: Row(
            children: [
              LikeButton(
                size: 23,
                padding: EdgeInsets.zero,
                likeCountPadding: EdgeInsets.zero,
                isLiked: isSaved,
                circleColor: const CircleColor(
                  start: _likeActive,
                  end: Color(0xFFFF6B6C),
                ),
                bubblesColor: const BubblesColor(
                  dotPrimaryColor: _likeActive,
                  dotSecondaryColor: Color(0xFFFFB3B3),
                ),
                likeBuilder: (bool isLiked) {
                  return Center(
                    child: SvgPicture.asset(
                      'assets/icon/figma_card_heart.svg',
                      width: 23,
                      height: 19,
                      colorFilter: isLiked
                          ? const ColorFilter.mode(_likeActive, BlendMode.srcIn)
                          : null,
                    ),
                  );
                },
                onTap: (bool isLiked) async {
                  await _toggleUserQuote(quoteId);
                  // 저장 실패 시 하트가 뒤집히지 않도록 실제 보관 상태를 반환
                  return quoteId != null && _savedQuoteIds.contains(quoteId);
                },
              ),
              const SizedBox(width: 70),
              IconButton(
                onPressed: () => _shareContent(author, content),
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
            ],
          ),
        ),
      ],
    );
  }

  /// 본문 검색 결과 카드(Figma Cards 49:4050: 384×214, 1px 녹색 테두리, 반지름 24)
  Widget _buildContentBox(
    String title,
    String content,
    String? quoteId,
    String? tag,
    String? imageFile,
    String? resonerEng,
  ) {
    final imagePath = ResonerImageHelper.resolve(imageFile, resonerEng);
    final networkUrl = quoteId != null ? _requestQuoteImages[quoteId] : null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 23),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _quoteCardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 상단: 프로필 이미지 + 저자명
          Row(
            children: [
              _buildCircleImage(
                size: 50,
                imagePath: imagePath,
                networkUrl: networkUrl,
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
          // 명언 텍스트(검색어 강조)
          _buildHighlightedContent(content),
          const SizedBox(height: 18),
          // 하단: 태그 + 좋아요/공유 버튼
          _buildCardFooter(
            tag: tag,
            quoteId: quoteId,
            author: title,
            content: content,
          ),
        ],
      ),
    );
  }
}

/// 저자·주제 카드 우측의 8×12 우향 삼각형(Figma "Button" 폴리곤). 전용 SVG가 없어 직접 그린다.
class _RightTrianglePainter extends CustomPainter {
  const _RightTrianglePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, size.height / 2)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _RightTrianglePainter oldDelegate) =>
      oldDelegate.color != color;
}
