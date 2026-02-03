import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'home_page.dart';
import 'search_page.dart';
import 'like_page.dart';
import 'setting_page.dart';

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
