import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

// Supabase 클라이언트 전역 변수
final supabase = Supabase.instance.client;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // .env 파일 로드
  await dotenv.load(fileName: '.env');

  // Supabase 초기화
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

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
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: ''),
          BottomNavigationBarItem(icon: Icon(Icons.search), label: ''),
          BottomNavigationBarItem(icon: Icon(Icons.bookmark), label: ''),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: ''),
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

  @override
  void initState() {
    super.initState();
    _loadQuotes();
  }

  // Supabase에서 명언 데이터 가져오기
  Future<void> _loadQuotes() async {
    try {
      final response = await supabase
          .from('quotes')
          .select()
          .order('created_at', ascending: false);

      setState(() {
        _quotes = List<Map<String, dynamic>>.from(response);
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
                            return _buildContentBox(
                              '${quote['resoner']}',
                              quote['text'],
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

  Widget _buildContentBox(String title, String content) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16.0),
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.0),
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
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            content,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[700],
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          // 버튼 영역
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: () {
                  // TODO: 하트 기능 구현
                },
                icon: const Icon(Icons.favorite_border),
                iconSize: 20,
                color: Colors.grey[600],
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
  bool _isLoading = true;
  String _searchType = 'author'; // 'author' 또는 'content'
  bool _hasSearched = false;

  @override
  void initState() {
    super.initState();
    _loadQuotes();
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

  // 검색 함수
  void _performSearch(String query) {
    if (query.isEmpty) {
      setState(() {
        _filteredQuotes = _allQuotes; // 빈 검색어일 때 모든 명언 표시
        _hasSearched = false;
      });
      return;
    }

    setState(() {
      _hasSearched = true;
      if (_searchType == 'author') {
        _filteredQuotes = _allQuotes.where((quote) {
          return quote['resoner'].toString().toLowerCase().contains(
            query.toLowerCase(),
          );
        }).toList();
      } else {
        _filteredQuotes = _allQuotes.where((quote) {
          return quote['text'].toString().toLowerCase().contains(
            query.toLowerCase(),
          );
        }).toList();
      }
    });
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
              const SizedBox(height: 20),

              // 검색바 섹션
              Container(
                margin: const EdgeInsets.only(bottom: 20.0),
                height: 56.0, // 고정 높이 설정
                child: Row(
                  children: [
                    // 검색 타입 선택 드롭다운
                    Container(
                      width: 120,
                      height: 56.0, // TextField와 동일한 높이
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(12.0),
                          bottomLeft: Radius.circular(12.0),
                        ),
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
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _searchType,
                          onChanged: (String? newValue) {
                            setState(() {
                              _searchType = newValue!;
                            });
                            _performSearch(_searchController.text);
                          },
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          borderRadius: BorderRadius.circular(12.0),
                          isExpanded: true, // 전체 너비 사용
                          icon: const Icon(
                            Icons.arrow_drop_down,
                            color: Colors.grey,
                            size: 20,
                          ),
                          style: const TextStyle(
                            color: Colors.black87,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'author',
                              child: Text('저자'),
                            ),
                            DropdownMenuItem(
                              value: 'content',
                              child: Text('명언 내용'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // 검색 입력창
                    Expanded(
                      child: Container(
                        height: 56.0, // 드롭다운과 동일한 높이
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: const BorderRadius.only(
                            topRight: Radius.circular(12.0),
                            bottomRight: Radius.circular(12.0),
                          ),
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
                            hintText: _searchType == 'author'
                                ? '저자명을 입력하세요'
                                : '명언 내용을 입력하세요',
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
                    ),
                  ],
                ),
              ),
              // 검색 결과 또는 안내 메시지
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _filteredQuotes.isEmpty
                    ? _hasSearched
                          ? const Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.search_off,
                                    size: 80,
                                    color: Colors.grey,
                                  ),
                                  SizedBox(height: 20),
                                  Text(
                                    '검색 결과가 없습니다',
                                    style: TextStyle(
                                      fontSize: 18,
                                      color: Colors.grey,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    '다른 검색어를 시도해보세요',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : const Center(
                              child: Text(
                                '명언이 없습니다.\n데이터베이스를 확인해주세요.',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 16),
                              ),
                            )
                    : RefreshIndicator(
                        onRefresh: _loadQuotes,
                        child: ListView.builder(
                          itemCount: _filteredQuotes.length,
                          itemBuilder: (context, index) {
                            final quote = _filteredQuotes[index];
                            return _buildContentBox(
                              '${quote['resoner']}',
                              quote['text'],
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

  Widget _buildContentBox(String title, String content) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16.0),
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.0),
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
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            content,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[700],
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          // 버튼 영역
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: () {
                  // TODO: 하트 기능 구현
                },
                icon: const Icon(Icons.favorite_border),
                iconSize: 20,
                color: Colors.grey[600],
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

// 보관함 화면
class BookmarkScreen extends StatelessWidget {
  const BookmarkScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bookmark, size: 80, color: Colors.orange),
            SizedBox(height: 20),
            Text(
              '보관함 화면',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
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
                        // 월계관 장식
                        Positioned(
                          top: -10,
                          left: -10,
                          right: -10,
                          child: Container(
                            height: 40,
                            decoration: const BoxDecoration(
                              image: DecorationImage(
                                image: AssetImage(
                                  'assets/laurel_crown.png',
                                ), // 월계관 이미지
                                fit: BoxFit.contain,
                              ),
                            ),
                            child: const Icon(
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
