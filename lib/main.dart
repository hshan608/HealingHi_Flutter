import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:home_widget/home_widget.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'dart:convert';
import 'dart:math' as math;
import 'home_page.dart';
import 'ad_helper.dart';
import 'search_page.dart';
import 'like_page.dart';
import 'setting_page.dart';
import 'tutorial.dart';
import 'installation_identity.dart';
import 'typographic_quotes.dart';
import 'notification_service.dart';
import 'responsive.dart';

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
          'text_kr': toTypographicQuotes(quote['text_kr']?.toString() ?? ''),
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
    await NotificationService.instance.initialize();
  } catch (error) {
    debugPrint('알림 초기화 실패: $error');
  }

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

    try {
      await NotificationService.instance.refreshIfEnabled(
        Supabase.instance.client,
      );
    } catch (error) {
      debugPrint('명언 알림 갱신 실패: $error');
    }
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
      // Pixel 9 에뮬레이터(411.4dp) 기준 레이아웃을 기기 폭에 비례해 확대·축소한다(responsive.dart).
      builder: (context, child) => AppScale(child: child!),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  static const int _navSwitchFrequency = 10;

  // 하단 바: 아이콘+라벨 영역 52(Figma 46에서 여유를 두어 6 확대), 시스템 인셋 최소 34
  // → 기준 기기에서 총 86
  static const double _navContentHeight = 52;
  static const double _navMinBottomInset = 34;

  int _currentIndex = 0;
  int _navSwitchCount = 0; // 탭 전환 횟수
  InterstitialAd? _interstitialAd;
  bool _isInterstitialLoading = false;
  bool _isInterstitialShowing = false;
  bool _hasPendingInterstitialRequest = false;
  bool _didEnterBackground = false;
  late final TutorialProgressStore _tutorialStore;
  Map<String, bool> _tutorialProgress = <String, bool>{};
  bool _tutorialStateLoaded = false;
  int _tutorialStepIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tutorialStore = TutorialProgressStore(supabase);
    _loadTutorialProgress();
    _loadInterstitialAd();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _interstitialAd?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // 다른 앱으로 이동해 실제로 백그라운드에 들어간 경우만 기록한다.
    // 전면 광고 자체가 만드는 생명주기 변경은 복귀 광고로 계산하지 않는다.
    if ((state == AppLifecycleState.paused ||
            state == AppLifecycleState.hidden) &&
        !_isInterstitialShowing) {
      _didEnterBackground = true;
      return;
    }

    if (state == AppLifecycleState.resumed && _didEnterBackground) {
      _didEnterBackground = false;
      _requestInterstitial();
    }
  }

  void _loadInterstitialAd() {
    if (_isInterstitialLoading || _interstitialAd != null) return;
    _isInterstitialLoading = true;

    InterstitialAd.load(
      adUnitId: AdHelper.interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _isInterstitialLoading = false;
          if (!mounted) {
            ad.dispose();
            return;
          }
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              _isInterstitialShowing = false;
              _interstitialAd = null;
              _loadInterstitialAd(); // 다음 광고 미리 로드
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              ad.dispose();
              _isInterstitialShowing = false;
              _interstitialAd = null;
              _loadInterstitialAd();
            },
          );
          _interstitialAd = ad;
          _tryShowRequestedInterstitial();
        },
        onAdFailedToLoad: (_) {
          _isInterstitialLoading = false;
          _interstitialAd = null;
          Future<void>.delayed(const Duration(seconds: 10), () {
            if (mounted) _loadInterstitialAd();
          });
        },
      ),
    );
  }

  void _requestInterstitial() {
    if (!mounted) return;
    _hasPendingInterstitialRequest = true;
    _tryShowRequestedInterstitial();
  }

  void _tryShowRequestedInterstitial() {
    if (!_hasPendingInterstitialRequest || _isInterstitialShowing) return;

    final ad = _interstitialAd;
    if (ad == null) {
      _loadInterstitialAd();
      return;
    }

    _hasPendingInterstitialRequest = false;
    _isInterstitialShowing = true;
    _interstitialAd = null;
    ad.show();
  }

  void _onNavTap(int index) {
    if (index == _currentIndex) return; // 같은 탭 재탭은 카운트 제외
    _navSwitchCount++;
    setState(() {
      _currentIndex = index;
      _tutorialStepIndex = 0;
    });

    if (_navSwitchCount % _navSwitchFrequency == 0) {
      _requestInterstitial();
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
        return 3;
      case TutorialSection.search:
      case TutorialSection.bookmarks:
        return 2;
      case TutorialSection.profile:
        return 3;
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
    // 실제 시스템 하단 인셋. 총 높이 계산에는 최소 34를 보장하지만, 아이콘 아래
    // 패딩은 실제 인셋만큼만 준다. 인셋이 34보다 작은 기기(3버튼 바가 앱 창 밖에
    // 있어 인셋 0인 경우 등)에서 남는 공간이 아이콘 위아래로 균등 분배되어
    // 아이콘·라벨이 보이는 영역의 세로 가운데에 놓인다.
    final systemBottomInset = MediaQuery.paddingOf(context).bottom;
    final navBottomInset = math.max(_navMinBottomInset, systemBottomInset);

    return Stack(
      children: [
        Scaffold(
          body: _buildCurrentScreen(),
          // Figma Bottom Navigation(h 80)은 iPhone 홈 인디케이터 34를 포함한 높이다.
          // 총 높이는 _navContentHeight(52, Figma 46보다 6 여유) + 하단 인셋(최소 34).
          // 아래쪽은 실제 시스템 인셋만큼만 비우고, 남은 영역 전체에서 아이콘·라벨을
          // 세로 가운데 정렬한다(Column의 mainAxisAlignment.center).
          // Scaffold는 bottomNavigationBar에 하단 인셋을 넣어주지 않으므로 직접 처리한다.
          bottomNavigationBar: Container(
            key: TutorialTargets.bottomNavBar,
            height: _navContentHeight + navBottomInset,
            color: const Color(0xFFF8F9FE),
            padding: EdgeInsets.fromLTRB(11, 0, 11, systemBottomInset),
            child: Row(
              children: [
                _buildNavigationItem(
                  index: 0,
                  label: '명언',
                  iconAsset: 'assets/icon/figma_quote.svg',
                  iconGap: 6,
                  activeColor: activeGreen,
                  inactiveColor: inactiveGrey,
                ),
                _buildNavigationItem(
                  index: 1,
                  label: '검색',
                  iconAsset: 'assets/icon/figma_nav_search.svg',
                  activeColor: activeGreen,
                  inactiveColor: inactiveGrey,
                ),
                _buildNavigationItem(
                  index: 2,
                  label: '보관함',
                  iconAsset: _currentIndex == 2
                      ? 'assets/icon/figma_nav_saved.svg'
                      : 'assets/icon/figma_nav_heart.svg',
                  activeColor: const Color(0xFFFF8788),
                  inactiveColor: inactiveGrey,
                  iconGap: 4, // Figma 실측 약 3.9
                  key: TutorialTargets.bookmarkTab,
                ),
                _buildNavigationItem(
                  index: 3,
                  label: '설정',
                  iconAsset: 'assets/icon/figma_nav_settings.svg',
                  activeColor: activeGreen,
                  inactiveColor: inactiveGrey,
                ),
              ],
            ),
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

  // 보관함 튜토리얼 여부를 화면에 내려주기 위해 빌드 시점에 구성한다.
  Widget _buildCurrentScreen() {
    switch (_currentIndex) {
      case 0:
        return HomeScreen(onInterstitialRequested: _requestInterstitial);
      case 1:
        return const SearchScreen();
      case 2:
        return BookmarkScreen(
          isTutorialActive:
              _shouldShowTutorial &&
              _currentTutorialSection == TutorialSection.bookmarks,
        );
      default:
        return MyPageScreen(onInterstitialRequested: _requestInterstitial);
    }
  }

  Widget _buildNavigationItem({
    required int index,
    required String label,
    IconData? icon,
    String? iconAsset,
    double iconGap = 5,
    required Color activeColor,
    required Color inactiveColor,
    Key? key,
  }) {
    assert(icon != null || iconAsset != null);
    final isSelected = _currentIndex == index;
    final color = isSelected ? activeColor : inactiveColor;

    return Expanded(
      key: key,
      child: Semantics(
        selected: isSelected,
        button: true,
        label: label,
        child: InkWell(
          onTap: () => _onNavTap(index),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (iconAsset != null)
                SvgPicture.asset(
                  iconAsset,
                  width: index == 2
                      ? 29.2
                      : (index == 3 ? 27 : (index == 1 ? 24 : 25)),
                  height: index == 2
                      ? 25.2
                      : (index == 3 ? 27 : (index == 1 ? 24 : 25)),
                  colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
                  fit: BoxFit.contain,
                )
              else
                Icon(icon, size: index == 3 ? 25 : 24, color: color),
              SizedBox(height: iconGap),
              Text(
                label,
                // 기본 줄 높이(약 17px)로는 아이콘(최대 27) + 간격과 함께
                // _navContentHeight(46)를 1~3px 넘친다. 줄 높이를 폰트 크기에
                // 맞춰 46 안에 들어오게 한다.
                style: TextStyle(
                  fontSize: 12,
                  height: 1.0,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
