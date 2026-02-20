import 'dart:io';

/// AdMob 광고 유닛 ID 관리
///
/// [중요] 실제 출시 전에 아래 TODO 주석 부분을 실제 광고 유닛 ID로 교체해야 합니다.
/// AdMob 콘솔(https://admob.google.com)에서 앱 등록 후 발급받은 ID를 사용하세요.
///
/// 현재는 Google 공식 테스트 ID가 설정되어 있습니다.
/// 테스트 ID로는 실제 수익이 발생하지 않으며, 출시 전 반드시 실제 ID로 교체하세요.
class AdHelper {
  // 출시 전 실제 ID로 교체할 때 아래 주석을 해제하고 테스트 ID 라인을 주석 처리하세요.
  // 실제 Android 배너 Ad Unit ID: ca-app-pub-7521798484796470/9013949305
  // 실제 Android 전면 Ad Unit ID: AdMob 콘솔에서 전면 광고 유닛 생성 후 교체

  static String get bannerAdUnitId {
    if (Platform.isAndroid) {
      return 'ca-app-pub-3940256099942544/6300978111'; // Google 공식 테스트 ID
      // return 'ca-app-pub-7521798484796470/9013949305'; // 실제 Ad Unit ID (출시 시 사용)
    } else if (Platform.isIOS) {
      return 'ca-app-pub-3940256099942544/2934735716'; // Google 공식 테스트 ID
    }
    throw UnsupportedError('지원하지 않는 플랫폼입니다.');
  }

  static String get interstitialAdUnitId {
    if (Platform.isAndroid) {
      return 'ca-app-pub-3940256099942544/1033173712'; // Google 공식 테스트 ID
      // return 'ca-app-pub-7521798484796470/1135024515'; // 실제 Ad Unit ID (출시 시 사용)
    } else if (Platform.isIOS) {
      return 'ca-app-pub-3940256099942544/4411468910'; // Google 공식 테스트 ID
    }
    throw UnsupportedError('지원하지 않는 플랫폼입니다.');
  }
}
