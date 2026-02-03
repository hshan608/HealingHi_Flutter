import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:home_widget/home_widget.dart';
import 'dart:io';
import 'dart:convert';

// Supabase 클라이언트 전역 변수
final supabase = Supabase.instance.client;

// 위젯 데이터 관리 클래스
class WidgetDataManager {
  // 위젯 초기화
  static Future<void> initializeWidgetData() async {
    try {
      await updateWidgetQuotes();
    } catch (e) {
      print('위젯 초기화 오류: $e');
    }
  }

  // Supabase에서 명언을 가져와서 위젯에 전달
  static Future<void> updateWidgetQuotes() async {
    try {
      // Supabase에서 30개의 명언 가져오기
      final response = await supabase
          .from('quotes')
          .select('id, text_kr, resoner_kr')
          .order('created_at', ascending: false)
          .limit(30);

      if (response.isEmpty) {
        print('명언 데이터가 없습니다.');
        return;
      }

      // JSON 배열로 변환
      final quotes = response.map((quote) {
        return {
          'id': quote['id']?.toString() ?? '',
          'text_kr': quote['text_kr'] ?? '',
          'resoner_kr': quote['resoner_kr'] ?? '알 수 없음',
        };
      }).toList();

      // SharedPreferences에 저장
      await HomeWidget.saveWidgetData<String>(
        'quote_data',
        jsonEncode(quotes),
      );

      // 위젯 업데이트 요청
      await HomeWidget.updateWidget(
        androidName: 'QuoteWidgetProvider',
      );

      print('위젯 데이터 업데이트 완료: ${quotes.length}개 명언');
      print('저장된 데이터 샘플: ${quotes.first}');
    } catch (e) {
      print('위젯 데이터 업데이트 오류: $e');
    }
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // .env 파일 로드
    print('✅ .env 파일 로드 시작...');
    await dotenv.load(fileName: '.env');
    print('✅ .env 파일 로드 완료');

    final supabaseUrl = dotenv.env['SUPABASE_URL'];
    final supabaseKey = dotenv.env['SUPABASE_ANON_KEY'];

    print('✅ Supabase URL: $supabaseUrl');
    print('✅ Supabase Key 존재 여부: ${supabaseKey != null && supabaseKey.isNotEmpty}');

    if (supabaseUrl == null || supabaseUrl.isEmpty) {
      throw Exception('❌ SUPABASE_URL이 .env 파일에 없습니다');
    }
    if (supabaseKey == null || supabaseKey.isEmpty) {
      throw Exception('❌ SUPABASE_ANON_KEY가 .env 파일에 없습니다');
    }

    // Supabase 초기화
    print('✅ Supabase 초기화 시작...');
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseKey,
    );
    print('✅ Supabase 초기화 완료');

    // 위젯 데이터 초기화
    print('✅ 위젯 데이터 초기화 시작...');
    await WidgetDataManager.initializeWidgetData();
    print('✅ 위젯 데이터 초기화 완료');

  } catch (e, stackTrace) {
    print('❌❌❌ 초기화 오류 발생 ❌❌❌');
    print('오류 메시지: $e');
    print('스택 트레이스: $stackTrace');
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '힐링하이',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const HomeScreen(),
    const SearchScreen(),
    const BookmarkScreen(),
    const MyPageScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        selectedItemColor: Colors.blue,
        unselectedItemColor: Colors.grey,
        iconSize: 24,
        items: [
          BottomNavigationBarItem(
            icon: SizedBox(
              width: 24,
              height: 24,
              child: Image.asset('assets/quotes1.png', fit: BoxFit.contain),
            ),
            label: '',
          ),
          const BottomNavigationBarItem(icon: Icon(Icons.search), label: ''),
          BottomNavigationBarItem(
            icon: SizedBox(
              width: 24,
              height: 24,
              child: Image.asset('assets/heart1-1.png', fit: BoxFit.contain),
            ),
            label: '',
          ),
          const BottomNavigationBarItem(icon: Icon(Icons.person), label: ''),
        ],
      ),
    );
  }
}

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

  @override
  void initState() {
    super.initState();
    _loadResonerImages();
    _loadQuotes();
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

  // Supabase 연결 테스트
  Future<void> _testSupabaseConnection() async {
    try {
      print('🔍 Supabase 연결 테스트 시작...');

      // 간단한 쿼리로 연결 테스트
      final response = await supabase
          .from('quotes')
          .select('count')
          .limit(1);

      print('✅ Supabase 연결 성공!');
      print('✅ 응답 데이터: $response');
    } catch (error, stackTrace) {
      print('❌ Supabase 연결 실패!');
      print('❌ 에러: $error');
      print('❌ 스택 트레이스: $stackTrace');
    }
  }

  // Supabase에서 명언 데이터 가져오기
  Future<void> _loadQuotes() async {
    try {
      print('📖 명언 데이터 로드 시작...');

      // 연결 테스트
      await _testSupabaseConnection();

      final response = await supabase
          .from('quotes')
          .select()
          .order('created_at', ascending: false);

      print('✅ 명언 데이터 로드 성공: ${response.length}개');

      setState(() {
        _quotes = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });
    } catch (error, stackTrace) {
      print('❌ 명언 데이터 로드 실패');
      print('❌ 에러: $error');
      print('❌ 스택 트레이스: $stackTrace');

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

  // 공유하기 함수
  void _shareContent(String title, String content) async {
    try {
      await Share.share(
        '$title\n\n$content\n\n공유됨 - Healing Hi 앱',
        subject: title,
      );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFCCFFCC),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
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
                        child: ListView.builder(
                          padding: const EdgeInsets.only(top: 20.0),
                          itemCount: _quotes.length,
                          itemBuilder: (context, index) {
                            final quote = _quotes[index];
                            final quoteId = _extractQuoteId(quote);
                            return _buildContentBox(
                              '${quote['resoner_kr']}',
                              quote['text_kr'],
                              quoteId,
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

  Widget _buildContentBox(String title, String content, String? quoteId) {
    return Container(
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
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 원형 프로필 이미지
          ClipOval(
            child: Container(
              width: 70,
              height: 70,
              color: Colors.grey[200],
              child: _getResonerImagePath(quoteId) != null
                  ? Image.asset(
                      _getResonerImagePath(quoteId)!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Icon(Icons.person, size: 40, color: Colors.grey[400]);
                      },
                    )
                  : Icon(Icons.person, size: 40, color: Colors.grey[400]),
            ),
          ),
          const SizedBox(height: 20),
          // 명언 텍스트 (중앙 정렬, 이탤릭)
          Text(
            content,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontStyle: FontStyle.italic,
              color: Colors.grey[800],
              height: 1.6,
            ),
          ),
          const SizedBox(height: 16),
          // 저자명 (대문자 스타일)
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey[500],
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          // 버튼 영역
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: () {
                  _toggleUserQuote(quoteId);
                },
                icon: Image.asset(
                  quoteId != null && _savedQuoteIds.contains(quoteId)
                      ? 'assets/heart2.png'
                      : 'assets/heart1.png',
                  width: 24,
                  height: 24,
                ),
                tooltip: '좋아요',
              ),
              IconButton(
                onPressed: () {
                  _shareContent(title, content);
                },
                icon: const Icon(Icons.share),
                iconSize: 20,
                color: Colors.grey[600],
                tooltip: '공유하기',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// 서치 화면
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _allQuotes = [];
  List<Map<String, dynamic>> _filteredQuotes = [];
  List<String> _uniqueAuthors = []; // 저자 검색용 고유 저자 목록
  bool _isLoading = true;
  String _searchType = 'author'; // 'author', 'content', 또는 'subject'
  bool _hasSearched = false;
  String? _deviceId;
  int? _userIdx;
  bool _isSavingLike = false;
  Set<String> _savedQuoteIds = {};

  @override
  void initState() {
    super.initState();
    _loadQuotes();
    _initUserIdentity();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Supabase에서 명언 데이터 가져오기
  Future<void> _loadQuotes() async {
    try {
      final response = await supabase
          .from('quotes')
          .select()
          .order('created_at', ascending: false);

      setState(() {
        _allQuotes = List<Map<String, dynamic>>.from(response);
        _filteredQuotes = _allQuotes; // 초기에는 모든 명언 표시
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
        _filteredQuotes = [];
      } else if (_searchType == 'content') {
        // 본문 검색: text_kr만 검색
        _filteredQuotes = _allQuotes.where((quote) {
          return quote['text_kr'].toString().toLowerCase().contains(
            query.toLowerCase(),
          );
        }).toList();
        _uniqueAuthors = [];
      } else {
        // subject
        _filteredQuotes = _allQuotes.where((quote) {
          return (quote['tag_kr']?.toString() ?? '').toLowerCase().contains(
            query.toLowerCase(),
          );
        }).toList();
        _uniqueAuthors = [];
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

  // 공유하기 함수
  void _shareContent(String title, String content) async {
    try {
      await Share.share(
        '$title\n\n$content\n\n공유됨 - Healing Hi 앱',
        subject: title,
      );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFCCFFCC),
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
                      onChanged: _performSearch,
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

    // 본문/주제 검색인 경우
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

  // 저자 아이템 위젯
  Widget _buildAuthorItem(String author) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8.0),
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: Colors.grey[300],
            child: Icon(Icons.person, color: Colors.grey[600], size: 24),
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
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            content,
            style: TextStyle(
              fontSize: 13,
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

      setState(() {
        _savedQuotes
          ..clear()
          ..addAll(List<Map<String, dynamic>>.from(quotes));
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

  Future<void> _removeFromBookmark(String? quoteId) async {
    if (quoteId == null) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('명언 ID를 찾을 수 없습니다.')));
      }
      return;
    }

    try {
      final userIdx = _userIdx;
      if (userIdx == null) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('사용자 정보를 찾을 수 없습니다.')));
        }
        return;
      }

      await supabase
          .from('users_quotes')
          .delete()
          .eq('user_idx', userIdx)
          .eq('quotes_id', quoteId);

      // 리스트에서 제거
      setState(() {
        _savedQuotes.removeWhere((quote) => quote['id']?.toString() == quoteId);
      });

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('보관함에서 삭제되었습니다.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('삭제 중 오류가 발생했습니다: $e')));
      }
    }
  }

  void _shareContent(String title, String content) async {
    try {
      await Share.share(
        '$title\n\n$content\n\n공유됨 - Healing Hi 앱',
        subject: title,
      );
    } catch (e) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8E3DF),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
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
                            return _buildBookmarkCard(
                              '${quote['resoner_kr']}',
                              quote['text_kr'],
                              quoteId,
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

  Widget _buildBookmarkCard(String title, String content, String? quoteId) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16.0),
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: const Color(0xFFFDF0EE),
        borderRadius: BorderRadius.circular(16.0),
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
                  color: Colors.grey[300],
                  child: _getResonerImagePath(quoteId) != null
                      ? Image.asset(
                          _getResonerImagePath(quoteId)!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Icon(Icons.person, size: 20, color: Colors.grey[600]);
                          },
                        )
                      : Icon(Icons.person, size: 20, color: Colors.grey[600]),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // 명언 텍스트 (왼쪽 정렬)
          Text(
            content,
            textAlign: TextAlign.left,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[800],
              height: 1.6,
            ),
          ),
          const SizedBox(height: 12),
          // 버튼 영역 (중앙)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: () {
                  _removeFromBookmark(quoteId);
                },
                icon: Image.asset('assets/heart2.png', width: 24, height: 24),
                tooltip: '보관함에서 삭제',
              ),
              IconButton(
                onPressed: () {
                  _shareContent(title, content);
                },
                icon: const Icon(Icons.share),
                iconSize: 20,
                color: Colors.grey[600],
                tooltip: '공유하기',
              ),
            ],
          ),
        ],
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

// 마이페이지 화면
class MyPageScreen extends StatefulWidget {
  const MyPageScreen({super.key});

  @override
  State<MyPageScreen> createState() => _MyPageScreenState();
}

class _MyPageScreenState extends State<MyPageScreen> {
  final TextEditingController _nameController = TextEditingController();

  // 사용자 데이터
  String _profileImageUrl = '';
  String _name = '';
  String _selectedLanguage = 'kor'; // 기본값: 한국어
  String _shareLevel = '실버 / 1개';
  int _shareProgress = 66; // 퍼센트
  int _totalShares = 100;
  int _currentShares = 66;
  String? _deviceId;
  bool _isLoading = true;

  // 언어 옵션
  final Map<String, String> _languageOptions = {'kor': '한국어', 'eng': '영어'};

  @override
  void initState() {
    super.initState();
    _getDeviceId();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  // 디바이스 고유 ID 가져오기
  Future<void> _getDeviceId() async {
    final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    String? deviceId;

    try {
      if (Platform.isAndroid) {
        AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
        deviceId = androidInfo.id; // Android ID
      } else if (Platform.isIOS) {
        IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
        deviceId = iosInfo.identifierForVendor; // iOS Vendor ID
      } else if (Platform.isWindows) {
        WindowsDeviceInfo windowsInfo = await deviceInfo.windowsInfo;
        deviceId = windowsInfo.deviceId;
      } else if (Platform.isLinux) {
        LinuxDeviceInfo linuxInfo = await deviceInfo.linuxInfo;
        deviceId = linuxInfo.machineId;
      } else if (Platform.isMacOS) {
        MacOsDeviceInfo macOsInfo = await deviceInfo.macOsInfo;
        deviceId = macOsInfo.systemGUID;
      }

      setState(() {
        _deviceId = deviceId;
      });

      // 디바이스 ID를 가져온 후 사용자 정보 로드
      if (deviceId != null) {
        await _loadUserData();
      }
    } catch (e) {
      print('디바이스 ID 가져오기 실패: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Supabase에서 사용자 정보 불러오기
  Future<void> _loadUserData() async {
    if (_deviceId == null) return;

    try {
      final response = await supabase
          .from('users')
          .select()
          .eq('device_id', _deviceId!)
          .maybeSingle();

      if (response != null) {
        // 데이터가 있으면 불러오기
        setState(() {
          _name = response['user_id'] ?? '';
          _profileImageUrl = response['profile_image_url'] ?? '';
          _selectedLanguage = response['language'] ?? 'kor';
          _nameController.text = _name;
          _isLoading = false;
        });
      } else {
        // 데이터가 없으면 빈 상태로 유지
        setState(() {
          _nameController.text = '';
          _selectedLanguage = 'kor';
          _isLoading = false;
        });
      }
    } catch (e) {
      print('사용자 정보 로드 실패: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  // 언어 변경 및 저장
  Future<void> _updateLanguage(String languageCode) async {
    if (_deviceId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('디바이스 정보를 가져오는 중입니다. 잠시 후 다시 시도해주세요')),
      );
      return;
    }

    try {
      // Supabase에 언어 업데이트
      await supabase.from('users').upsert({
        'device_id': _deviceId,
        'user_id': _nameController.text.trim().isNotEmpty
            ? _nameController.text.trim()
            : _name,
        'language': languageCode,
        'profile_image_url': _profileImageUrl.isNotEmpty
            ? _profileImageUrl
            : null,
      }, onConflict: 'device_id').select();

      setState(() {
        _selectedLanguage = languageCode;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('언어가 ${_languageOptions[languageCode]}(으)로 변경되었습니다'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('언어 변경 실패: $e')));
      }
      print('언어 업데이트 오류: $e');
    }
  }

  // 이미지 선택 및 업로드
  Future<void> _pickAndUploadImage() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 75,
      );

      if (image == null) return;

      if (_deviceId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('디바이스 정보를 가져오는 중입니다. 잠시 후 다시 시도해주세요')),
          );
        }
        return;
      }

      // 로딩 표시
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('이미지 업로드 중...')));
      }

      // 파일 읽기
      final bytes = await File(image.path).readAsBytes();
      final fileExt = image.path.split('.').last;
      final fileName = '$_deviceId.$fileExt';
      final filePath = 'profiles/$fileName';

      // Supabase Storage에 업로드
      await supabase.storage
          .from('avatars')
          .uploadBinary(
            filePath,
            bytes,
            fileOptions: FileOptions(
              upsert: true,
              contentType: 'image/$fileExt',
            ),
          );

      // Public URL 가져오기
      final imageUrl = supabase.storage.from('avatars').getPublicUrl(filePath);

      // users 테이블 업데이트 (device_id를 기준으로 upsert)
      await supabase.from('users').upsert({
        'device_id': _deviceId,
        'user_id': _nameController.text.trim(),
        'profile_image_url': imageUrl,
        'language': _selectedLanguage,
      }, onConflict: 'device_id').select();

      setState(() {
        _profileImageUrl = imageUrl;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('프로필 사진이 업데이트되었습니다!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('이미지 업로드 실패: $e')));
      }
      print('이미지 업로드 오류: $e');
    }
  }

  // Supabase에 사용자 정보 저장
  Future<void> _saveUserToSupabase() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('이름을 입력해주세요')));
      return;
    }

    if (_deviceId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('디바이스 정보를 가져오는 중입니다. 잠시 후 다시 시도해주세요')),
      );
      return;
    }

    try {
      // Supabase users 테이블에 데이터 저장
      await supabase.from('users').upsert({
        'device_id': _deviceId,
        'user_id': _nameController.text.trim(),
        'profile_image_url': _profileImageUrl.isNotEmpty
            ? _profileImageUrl
            : null,
        'language': _selectedLanguage,
      }, onConflict: 'device_id').select();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('저장되었습니다!'),
            backgroundColor: Colors.green,
          ),
        );
      }

      setState(() {
        _name = _nameController.text.trim();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('저장 실패: $e')));
      }
      print('Supabase 저장 오류: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // 로딩 중일 때
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF5F5F5),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: [
                // 상단 제목
                const Row(
                  children: [
                    Text(
                      '프로필 설정',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 30),

                // 프로필 이미지와 월계관
                GestureDetector(
                  onTap: _pickAndUploadImage,
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.2),
                          spreadRadius: 2,
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Stack(
                      children: [
                        // 프로필 이미지
                        Positioned.fill(
                          child: ClipOval(
                            child: _profileImageUrl.isNotEmpty
                                ? Image.network(
                                    _profileImageUrl,
                                    fit: BoxFit.cover,
                                  )
                                : Container(
                                    color: Colors.grey[300],
                                    child: const Icon(
                                      Icons.person,
                                      size: 60,
                                      color: Colors.grey,
                                    ),
                                  ),
                          ),
                        ),
                        // 카메라 아이콘 (편집 힌트)
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: Colors.blue,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: const Icon(
                              Icons.camera_alt,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ),
                        // 월계관 장식 이미지 사용 대신 아이콘만 표시
                        const Positioned(
                          top: -10,
                          left: -10,
                          right: -10,
                          child: SizedBox(
                            height: 40,
                            child: Icon(
                              Icons.emoji_events,
                              color: Colors.amber,
                              size: 30,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 40),

                // 이름 입력 필드
                _buildInputField(
                  label: '이름',
                  controller: _nameController,
                  hintText: '이름을 입력하세요',
                  hasCheckIcon: true,
                ),
                const SizedBox(height: 20),

                // 언어 선택 필드
                _buildLanguageSelector(),
                const SizedBox(height: 30),

                // 공유 등급/개 섹션
                _buildInfoSection(
                  title: '공유 등급/개',
                  value: _shareLevel,
                  valueColor: Colors.red,
                ),
                const SizedBox(height: 20),

                // 공유 달성도 섹션
                _buildAchievementSection(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLanguageSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '언어',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 56, // 다른 입력 필드와 동일한 높이
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(25),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                spreadRadius: 1,
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: DropdownButtonHideUnderline(
            child: ButtonTheme(
              alignedDropdown: true,
              child: DropdownButton<String>(
                value: _selectedLanguage,
                isExpanded: true,
                borderRadius: BorderRadius.circular(25),
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.black87,
                  fontWeight: FontWeight.w500,
                ),
                icon: const Padding(
                  padding: EdgeInsets.only(right: 12),
                  child: Icon(Icons.arrow_drop_down, color: Colors.grey),
                ),
                items: _languageOptions.entries.map((entry) {
                  return DropdownMenuItem<String>(
                    value: entry.key,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(entry.value),
                    ),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  if (newValue != null && newValue != _selectedLanguage) {
                    _updateLanguage(newValue);
                  }
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInputField({
    required String label,
    required TextEditingController controller,
    required String hintText,
    required bool hasCheckIcon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(25),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                spreadRadius: 1,
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: TextField(
            controller: controller,
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
              suffixIcon: hasCheckIcon
                  ? GestureDetector(
                      onTap: _saveUserToSupabase,
                      child: Container(
                        margin: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 16,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoSection({
    required String title,
    required String value,
    Color? valueColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 16,
              height: 16,
              decoration: const BoxDecoration(
                color: Colors.grey,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.help, color: Colors.white, size: 12),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(25),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                spreadRadius: 1,
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Text(
            value,
            style: TextStyle(
              fontSize: 14,
              color: valueColor ?? Colors.black87,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAchievementSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Text(
              '공유 달성도',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
            ),
            SizedBox(width: 8),
            Icon(Icons.help_outline, color: Colors.grey, size: 16),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(25),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                spreadRadius: 1,
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 진행률 표시
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '$_currentShares/$_totalShares',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
                  ),
                  Text(
                    '$_shareProgress%',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // 진행바
              Container(
                height: 8,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: _shareProgress,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.green,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    Expanded(flex: 100 - _shareProgress, child: Container()),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
