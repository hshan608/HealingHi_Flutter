import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:like_button/like_button.dart';
import 'dart:io';
import 'dart:convert';

// Supabase 클라이언트 전역 변수
final supabase = Supabase.instance.client;

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
  Map<String, String> _resonerImages = {}; // 영어이름(소문자) -> 이미지경로
  Map<String, String> _authorEngMap = {}; // resoner_kr -> resoner_eng

  @override
  void initState() {
    super.initState();
    _loadResonerImages();
    _loadQuotes();
    _initUserIdentity();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  // assets/resoner/ 폴더의 이미지를 영어 이름으로 매핑
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
        // 파일명에서 ID 부분 제거하고 영어 이름 추출
        // 예: "10001_Maya Angelou.png" -> "Maya Angelou"
        // 예: "10003_10021_Abraham Lincoln.png" -> "Abraham Lincoln"
        final nameWithExt = fileName.replaceAll(RegExp(r'^(\d+_)+'), '');
        final name = nameWithExt.replaceAll('.png', '');
        if (name.isNotEmpty && name != 'None') {
          imageMap[name.toLowerCase()] = path;
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

  // resoner_kr로 저자 이미지 경로 가져오기
  String? _getAuthorImagePath(String authorKr) {
    final engName = _authorEngMap[authorKr];
    if (engName == null) return null;
    return _resonerImages[engName.toLowerCase()];
  }

  // Supabase에서 명언 데이터 가져오기
  Future<void> _loadQuotes() async {
    try {
      final response = await supabase
          .from('quotes')
          .select()
          .order('created_at', ascending: false);

      final quotes = List<Map<String, dynamic>>.from(response);

      // resoner_kr -> resoner_eng 매핑 생성
      final Map<String, String> engMap = {};
      for (final quote in quotes) {
        final kr = quote['resoner_kr']?.toString();
        final eng = quote['resoner_eng']?.toString();
        if (kr != null && eng != null && eng.isNotEmpty) {
          engMap[kr] = eng;
        }
      }

      setState(() {
        _allQuotes = quotes;
        _filteredQuotes = _allQuotes; // 초기에는 모든 명언 표시
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
            .where((quote) => quote['resoner_kr']
                .toString()
                .toLowerCase()
                .contains(query.toLowerCase()))
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
            .where((quote) => (quote['tag_kr']?.toString() ?? '')
                .toLowerCase()
                .contains(query.toLowerCase()))
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
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: const Color(0xFFDDE7DE),
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 상단 영역 (패딩 있음)
              Padding(
                padding: const EdgeInsets.fromLTRB(24.0, 16.0, 24.0, 12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                  // 상단 제목
                  const Row(
                    children: [
                      Text(
                        '검색',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // 검색바 섹션
                  Container(
                    margin: const EdgeInsets.only(bottom: 8.0),
                    height: 56.0,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12.0),
                      border: Border.all(
                        color: Colors.grey.withOpacity(0.2),
                        width: 1.0,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.1),
                          spreadRadius: 1,
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      onChanged: _performSearch,
                      keyboardType: TextInputType.text,
                      textInputAction: TextInputAction.search,
                      enableInteractiveSelection: true,
                      onSubmitted: _performSearch,
                      onTap: () {
                        SystemChannels.textInput.invokeMethod('TextInput.show');
                      },
                      decoration: InputDecoration(
                        hintText: '입력',
                        hintStyle: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 14,
                        ),
                        prefixIcon: const Icon(
                          Icons.search,
                          color: Colors.grey,
                          size: 20,
                        ),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                onPressed: () {
                                  _searchController.clear();
                                  _performSearch('');
                                },
                                icon: const Icon(
                                  Icons.clear,
                                  color: Colors.grey,
                                  size: 20,
                                ),
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16.0,
                          vertical: 16.0,
                        ),
                      ),
                    ),
                  ),

                  // 검색 타입 선택 탭
                  Container(
                    margin: const EdgeInsets.only(bottom: 8.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _searchType = 'author';
                              });
                              _performSearch(_searchController.text);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                vertical: 12.0,
                              ),
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(
                                    color: _searchType == 'author'
                                        ? Colors.black87
                                        : Colors.transparent,
                                    width: 2.0,
                                  ),
                                ),
                              ),
                              child: Text(
                                '저자',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: _searchType == 'author'
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: _searchType == 'author'
                                      ? Colors.black87
                                      : Colors.grey,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _searchType = 'content';
                              });
                              _performSearch(_searchController.text);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                vertical: 12.0,
                              ),
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(
                                    color: _searchType == 'content'
                                        ? Colors.black87
                                        : Colors.transparent,
                                    width: 2.0,
                                  ),
                                ),
                              ),
                              child: Text(
                                '본문',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: _searchType == 'content'
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: _searchType == 'content'
                                      ? Colors.black87
                                      : Colors.grey,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _searchType = 'subject';
                              });
                              _performSearch(_searchController.text);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                vertical: 12.0,
                              ),
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(
                                    color: _searchType == 'subject'
                                        ? Colors.black87
                                        : Colors.transparent,
                                    width: 2.0,
                                  ),
                                ),
                              ),
                              child: Text(
                                '주제',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: _searchType == 'subject'
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: _searchType == 'subject'
                                      ? Colors.black87
                                      : Colors.grey,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // 검색 결과 또는 안내 메시지 (패딩 없음, 전체 너비)
            Expanded(
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 16.0,
                ),
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
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.manage_search,
              size: 80,
              color: Colors.grey[300],
            ),
            const SizedBox(height: 20),
            const Text(
              '검색하고 싶은 항목을 우선 선택해주세요.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '저자, 본문, 주제, 어느 것을 찾고 싶으세요?',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      );
    }

    // 저자 검색인 경우
    if (_searchType == 'author') {
      if (_uniqueAuthors.isEmpty) {
        return _buildNoResultsWidget();
      }
      return RefreshIndicator(
        onRefresh: _loadQuotes,
        child: ListView.builder(
          itemCount: _uniqueAuthors.length,
          itemBuilder: (context, index) {
            final author = _uniqueAuthors[index];
            return _buildAuthorItem(author);
          },
        ),
      );
    }

    // 주제 검색인 경우
    if (_searchType == 'subject') {
      if (_uniqueSubjects.isEmpty) {
        return _buildNoResultsWidget();
      }
      return RefreshIndicator(
        onRefresh: _loadQuotes,
        child: ListView.builder(
          itemCount: _uniqueSubjects.length,
          itemBuilder: (context, index) {
            final subject = _uniqueSubjects[index];
            return _buildSubjectItem(subject);
          },
        ),
      );
    }

    // 본문 검색인 경우
    if (_filteredQuotes.isEmpty) {
      return _buildNoResultsWidget();
    }
    return RefreshIndicator(
      onRefresh: _loadQuotes,
      child: ListView.builder(
        itemCount: _filteredQuotes.length,
        itemBuilder: (context, index) {
          final quote = _filteredQuotes[index];
          final quoteId = _extractQuoteId(quote);
          return _buildContentBox(
            '${quote['resoner_kr']}',
            quote['text_kr'],
            quoteId,
          );
        },
      ),
    );
  }

  // 검색 결과 없음 위젯
  Widget _buildNoResultsWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset(
            'assets/sorry.png',
            width: 160,
            height: 160,
          ),
          const SizedBox(height: 20),
          const Text(
            '아직 추가되지 않은 내용이에요.',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '공유 달성도를 충족하시면\n자유롭게 추가 요청을 하실 수 있어요!',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // 저자의 명언 목록 팝업
  void _showAuthorQuotesDialog(String author) {
    final authorQuotes = _allQuotes
        .where((q) => q['resoner_kr']?.toString() == author)
        .toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.75,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Color(0xFFDDE7DE),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  // 핸들 바
                  Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[400],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // 저자 헤더
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    child: Row(
                      children: [
                        ClipOval(
                          child: Container(
                            width: 48,
                            height: 48,
                            color: Colors.grey[300],
                            child: _getAuthorImagePath(author) != null
                                ? Image.asset(
                                    _getAuthorImagePath(author)!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Icon(Icons.person, color: Colors.grey[600], size: 28);
                                    },
                                  )
                                : Icon(Icons.person, color: Colors.grey[600], size: 28),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                author,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '명언 ${authorQuotes.length}개',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  // 명언 리스트
                  Expanded(
                    child: ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: authorQuotes.length,
                      itemBuilder: (context, index) {
                        final quote = authorQuotes[index];
                        final quoteId = _extractQuoteId(quote);
                        final tag = quote['tag_kr']?.toString();
                        return _buildAuthorQuoteCard(
                          quote['text_kr']?.toString() ?? '',
                          quoteId,
                          tag,
                          author,
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // 주제의 명언 목록 팝업
  void _showSubjectQuotesDialog(String subject) {
    final subjectQuotes = _allQuotes
        .where((q) => q['tag_kr']?.toString() == subject)
        .toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.75,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Color(0xFFDDE7DE),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  // 핸들 바
                  Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[400],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // 주제 헤더
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.tag, color: Colors.grey[600], size: 28),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                subject,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '명언 ${subjectQuotes.length}개',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  // 명언 리스트
                  Expanded(
                    child: ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: subjectQuotes.length,
                      itemBuilder: (context, index) {
                        final quote = subjectQuotes[index];
                        final quoteId = _extractQuoteId(quote);
                        final author = quote['resoner_kr']?.toString() ?? '';
                        return _buildAuthorQuoteCard(
                          quote['text_kr']?.toString() ?? '',
                          quoteId,
                          null, // 주제 팝업에서는 태그 대신 저자를 보여주므로 tag는 null
                          author,
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // 주제 아이템 위젯
  Widget _buildSubjectItem(String subject) {
    final quoteCount = _allQuotes
        .where((q) => q['tag_kr']?.toString() == subject)
        .length;

    return GestureDetector(
      onTap: () => _showSubjectQuotesDialog(subject),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8.0),
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(8.0),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.tag, color: Colors.grey[600], size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    subject,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
                  ),
                  Text(
                    '명언 ${quoteCount}개',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  // 저자 팝업 내 명언 카드
  Widget _buildAuthorQuoteCard(String content, String? quoteId, String? tag, String author) {
    return StatefulBuilder(
      builder: (context, setCardState) {
        final isSaved = quoteId != null && _savedQuoteIds.contains(quoteId);
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
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
              Text(
                content,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w300,
                  color: Colors.grey[800],
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
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
                  LikeButton(
                    size: 28,
                    isLiked: isSaved,
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
                        width: 28,
                        height: 28,
                      );
                    },
                    onTap: (bool isLiked) async {
                      await _toggleUserQuote(quoteId);
                      setCardState(() {});
                      if (mounted) setState(() {});
                      return !isLiked;
                    },
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => _shareContent(author, content),
                    child: Icon(Icons.share, color: Colors.grey[600], size: 22),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // 저자 아이템 위젯
  Widget _buildAuthorItem(String author) {
    return GestureDetector(
      onTap: () => _showAuthorQuotesDialog(author),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8.0),
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(8.0),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Row(
          children: [
            ClipOval(
              child: Container(
                width: 40,
                height: 40,
                color: Colors.grey[300],
                child: _getAuthorImagePath(author) != null
                    ? Image.asset(
                        _getAuthorImagePath(author)!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Icon(Icons.person, color: Colors.grey[600], size: 24);
                        },
                      )
                    : Icon(Icons.person, color: Colors.grey[600], size: 24),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                author,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.black87,
                ),
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  Widget _buildContentBox(String title, String content, String? quoteId) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8.0),
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            content,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w300,
              color: Colors.grey[600],
              height: 1.4,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
