import 'dart:io';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// AdMob 광고 유닛 ID 관리
///
/// 환경별 ID는 .env.development / .env.production 파일에서 관리됩니다.
/// 실행 시 --dart-define=FLUTTER_ENV=development|production 으로 환경을 선택하세요.
///
/// 예시:
///   개발: flutter run --dart-define=FLUTTER_ENV=development
///   배포: flutter build apk --dart-define=FLUTTER_ENV=production
class AdHelper {
  static String get bannerAdUnitId {
    if (Platform.isAndroid) {
      return dotenv.env['ADMOB_ANDROID_BANNER_ID'] ?? '';
    } else if (Platform.isIOS) {
      return dotenv.env['ADMOB_IOS_BANNER_ID'] ?? '';
    }
    throw UnsupportedError('지원하지 않는 플랫폼입니다.');
  }

  static String get interstitialAdUnitId {
    if (Platform.isAndroid) {
      return dotenv.env['ADMOB_ANDROID_INTERSTITIAL_ID'] ?? '';
    } else if (Platform.isIOS) {
      return dotenv.env['ADMOB_IOS_INTERSTITIAL_ID'] ?? '';
    }
    throw UnsupportedError('지원하지 않는 플랫폼입니다.');
  }
}
