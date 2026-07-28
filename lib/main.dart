import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:home_widget/home_widget.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'dart:convert';
import 'home_page.dart';
import 'ad_helper.dart';
import 'search_page.dart';
import 'like_page.dart';
import 'setting_page.dart';
import 'tutorial.dart';
import 'installation_identity.dart';

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
      await HomeWidget.saveWidgetData<String>('quote_data', jsonEncode(quotes));

      // 위젯 업데이트 요청
      await HomeWidget.updateWidget(androidName: 'QuoteWidgetProvider');

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
    // 환경에 따른 .env 파일 로드
    // 개발: flutter run --dart-define=FLUTTER_ENV=development (기본값)
    // 배포: flutter build apk --dart-define=FLUTTER_ENV=production
    const environment = String.fromEnvironment(
      'FLUTTER_ENV',
      defaultValue: 'development',
    );
    print('✅ .env.$environment 파일 로드 시작...');
    await dotenv.load(fileName: '.env.$environment');
    print('✅ .env.$environment 파일 로드 완료');

    final supabaseUrl = dotenv.env['SUPABASE_URL'];
    final supabaseKey = dotenv.env['SUPABASE_ANON_KEY'];

    print('✅ Supabase URL: $supabaseUrl');
    print(
      '✅ Supabase Key 존재 여부: ${supabaseKey != null && supabaseKey.isNotEmpty}',
    );

    if (supabaseUrl == null || supabaseUrl.isEmpty) {
      throw Exception('❌ SUPABASE_URL이 .env.$environment 파일에 없습니다');
    }
    if (supabaseKey == null || supabaseKey.isEmpty) {
      throw Exception('❌ SUPABASE_ANON_KEY가 .env.$environment 파일에 없습니다');
    }

    await InstallationIdentity.initialize();

    // Supabase 초기화
    print('✅ Supabase 초기화 시작...');
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseKey,
      headers: {'x-installation-id': InstallationIdentity.id},
    );
    print('✅ Supabase 초기화 완료');

    final legacyDeviceId = InstallationIdentity.legacyId;
    if (legacyDeviceId != null && legacyDeviceId.isNotEmpty) {
      try {
        await Supabase.instance.client.rpc(
          'claim_legacy_installation',
          params: {'p_legacy_device_id': legacyDeviceId},
        );
      } catch (error) {
        print('기존 사용자 데이터 이전을 건너뜁니다: $error');
      }
    }

    // AdMob 초기화
    print('✅ AdMob 초기화 시작...');
    await MobileAds.instance.initialize();
    print('✅ AdMob 초기화 완료');

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
        fontFamily: 'Pretendard',
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
  int _navSwitchCount = 0; // 탭 전환 횟수
  InterstitialAd? _interstitialAd;
  late final TutorialProgressStore _tutorialStore;
  Map<String, bool> _tutorialProgress = <String, bool>{};
  bool _tutorialStateLoaded = false;
  int _tutorialStepIndex = 0;

  final List<Widget> _screens = [
    const HomeScreen(),
    const SearchScreen(),
    const BookmarkScreen(),
    const MyPageScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _tutorialStore = TutorialProgressStore(supabase);
    _loadTutorialProgress();
    _loadInterstitialAd();
  }

  @override
  void dispose() {
    _interstitialAd?.dispose();
    super.dispose();
  }

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
          if (mounted) setState(() => _interstitialAd = ad);
        },
        onAdFailedToLoad: (_) => _interstitialAd = null,
      ),
    );
  }

  void _onNavTap(int index) {
    if (index == _currentIndex) return; // 같은 탭 재탭은 카운트 제외
    _navSwitchCount++;
    setState(() {
      _currentIndex = index;
      _tutorialStepIndex = 0;
    });

    if (_navSwitchCount % 5 == 0 && _interstitialAd != null) {
      _interstitialAd!.show();
      _interstitialAd = null;
    }
  }

  Future<void> _loadTutorialProgress() async {
    final progress = await _tutorialStore.load();
    if (!mounted) return;
    setState(() {
      _tutorialProgress = progress;
      _tutorialStateLoaded = true;
    });
  }

  TutorialSection get _currentTutorialSection =>
      TutorialSection.values[_currentIndex];

  bool get _shouldShowTutorial =>
      _tutorialStateLoaded &&
      _tutorialProgress[_currentTutorialSection.storageKey] != true;

  int _tutorialStepCount(TutorialSection section) {
    switch (section) {
      case TutorialSection.home:
      case TutorialSection.search:
        return 3;
      case TutorialSection.bookmarks:
      case TutorialSection.profile:
        return 2;
    }
  }

  void _advanceTutorial() {
    final section = _currentTutorialSection;
    if (_tutorialStepIndex + 1 < _tutorialStepCount(section)) {
      setState(() => _tutorialStepIndex++);
      return;
    }
    _completeTutorial(section);
  }

  Future<void> _completeTutorial(TutorialSection section) async {
    final updatedProgress = <String, bool>{
      ..._tutorialProgress,
      section.storageKey: true,
    };
    setState(() {
      _tutorialProgress = updatedProgress;
      _tutorialStepIndex = 0;
    });

    try {
      await _tutorialStore.save(updatedProgress);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('튜토리얼 완료 상태를 저장하지 못했습니다. 잠시 후 다시 시도해주세요.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const activeGreen = Color(0xFF81A684); // 활성화 시 진한 녹색
    const inactiveGrey = Color(0xFFBDBDBD); // 비활성화 시 회색
    const bookmarkPink = Color(0xFFFF8787); // 보관함 하트 색상

    return Stack(
      children: [
        Scaffold(
          body: _screens[_currentIndex],
          bottomNavigationBar: BottomNavigationBar(
            type: BottomNavigationBarType.fixed,
            currentIndex: _currentIndex,
            onTap: _onNavTap,
            selectedItemColor: Colors.transparent, // 개별 색상 사용
            unselectedItemColor: Colors.transparent, // 개별 색상 사용
            iconSize: 24,
            items: [
              BottomNavigationBarItem(
                icon: Icon(
                  CupertinoIcons.quote_bubble,
                  color: _currentIndex == 0 ? activeGreen : inactiveGrey,
                ),
                label: '',
              ),
              BottomNavigationBarItem(
                icon: Icon(
                  Icons.search,
                  color: _currentIndex == 1 ? activeGreen : inactiveGrey,
                ),
                label: '',
              ),
              BottomNavigationBarItem(
                icon: Icon(
                  Icons.favorite_border,
                  color: _currentIndex == 2 ? bookmarkPink : inactiveGrey,
                ),
                activeIcon: const Icon(Icons.favorite, color: bookmarkPink),
                label: '',
              ),
              BottomNavigationBarItem(
                icon: Icon(
                  Icons.person,
                  color: _currentIndex == 3 ? activeGreen : inactiveGrey,
                ),
                label: '',
              ),
            ],
          ),
        ),
        if (_shouldShowTutorial)
          TutorialOverlay(
            section: _currentTutorialSection,
            stepIndex: _tutorialStepIndex,
            onNext: _advanceTutorial,
            onSkip: () => _completeTutorial(_currentTutorialSection),
          ),
      ],
    );
  }
}
