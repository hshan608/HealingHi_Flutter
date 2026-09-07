# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 프로젝트 개요

힐링하이(HealingHi)는 명언을 탐색·보관·공유하는 Flutter 앱이다. 백엔드는 Supabase이며 **로그인 절차가 없다**. 대신 설치 단위로 생성한 UUID 하나가 사용자 식별자·인증 수단·RLS 판정 기준을 모두 겸한다. 이 구조가 코드 전반의 제약을 결정하므로 아래 "설치 식별" 절을 먼저 읽어야 한다.

## 개발 명령

### 최초 설정

```bash
flutter pub get

# .env 파일은 gitignore 대상이며, 없으면 앱이 초기화 단계에서 실패한다.
cp .env.development.example .env.development
cp .env.production.example .env.production
# SUPABASE_URL, SUPABASE_ANON_KEY, APP_STORE_ID를 실제 값으로 채운다.
# AdMob ID는 development는 Google 테스트 ID가 기본값으로 들어 있다.

dart run flutter_launcher_icons   # 아이콘 재생성(선택)
```

### 실행 / 빌드

`FLUTTER_ENV` dart-define으로 `.env.<환경>` 파일을 선택한다. 생략하면 `development`다.

```bash
flutter run                                              # = development
flutter run --dart-define=FLUTTER_ENV=production
flutter build appbundle --dart-define=FLUTTER_ENV=production
flutter build apk --release --dart-define=FLUTTER_ENV=production
```

### 테스트 / 코드 품질

```bash
flutter test
flutter test test/widget_test.dart
flutter test test/widget_test.dart --plain-name '홈 튜토리얼이 단계 정보와 이동 버튼을 표시한다'
flutter analyze
dart format lib/            # `flutter format`은 제거된 명령이다
```

## 아키텍처

### 파일 구성

`lib/`는 화면 단위로 분리되어 있다(과거의 단일 파일 구조가 아니다).

| 파일 | 역할 |
|------|------|
| `main.dart` | 부트스트랩, `MainScreen`(하단 탭 4개), 전면 광고 소유, `WidgetDataManager` |
| `home_page.dart` | `HomeScreen` — 명언 피드, 카드 이미지 공유 |
| `search_page.dart` | `SearchScreen` — 저자/본문/주제 탭 검색 |
| `like_page.dart` | `BookmarkScreen` — 보관함 |
| `setting_page.dart` | `MyPageScreen` — 프로필, 언어, 알림, 공유 등급, 랭킹, 명언 신청 |
| `admin_page.dart` | `AdminPage` — 명언 신청 승인/거절 |
| `tutorial.dart` | 튜토리얼 오버레이·진행 상태 저장 |
| `notification_service.dart` | 매일 명언 로컬 알림 |
| `installation_identity.dart` | 설치 UUID 발급·보관 |
| `resoner_image_helper.dart` | 저자 이미지 자산 해석 |
| `quote_share.dart` | 명언 카드 이미지 캡처·공유 공용 로직(`QuoteShare`, `QuoteShareCard`). 홈·보관함이 함께 사용 |
| `app_popup.dart` | Figma 400×241 공용 안내 팝업(`AppNoticePopup`, `showAppNoticePopup`). 신청 완료·리뷰 확인·신청 승인 알림에 사용 |
| `ad_helper.dart`, `nickname_generator.dart` | AdMob 유닛 ID, 결정적 닉네임 생성 |

상태 관리는 `StatefulWidget` + `setState()`뿐이며 외부 라이브러리를 쓰지 않는다.

### 설치 식별 — 모든 데이터 접근의 전제

1. `InstallationIdentity.initialize()`가 `flutter_secure_storage`에서 UUID v4를 읽거나 새로 발급한다.
2. `Supabase.initialize(headers: {'x-installation-id': InstallationIdentity.id})`로 모든 요청에 헤더를 붙인다.
3. DB의 `public.request_installation_id()`가 이 헤더를 읽고, **거의 모든 RLS 정책과 SECURITY DEFINER 함수가 이 값을 기준으로 판정한다.**

파생되는 규칙:

- `users.device_id`, `device_shares.device_id`, `request_quotes.device_id` 컬럼에 들어가는 값은 하드웨어 ID가 아니라 이 **설치 UUID**다. 컬럼명이 `device_id`인 것은 과거 스키마의 잔재다.
- `Supabase.instance.client` 이외의 클라이언트를 새로 만들면 헤더가 빠져 모든 읽기·쓰기가 조용히 빈 결과를 내거나 실패한다.
- `device_info_plus`는 이제 **legacy 이관 용도로만** 남아 있다. 앱 시작 시 `claim_legacy_installation` RPC가 구버전 하드웨어 ID 기반 행을 새 UUID로 옮기며, 이 함수는 **2026-10-01 UTC 이후 항상 false를 반환**한다(마이그레이션 `202607280002` 참조).
- 앱 재설치로 secure storage가 비워지면 새 사용자가 된다. 이전 보관함·공유 카운트는 복구 경로가 없다.

### RLS와 RPC 경계

`supabase/migrations/202607280002_harden_public_access.sql`이 접근 모델의 기준 문서다. 테이블 권한이 좁게 잠겨 있어, **테이블에 직접 쿼리하면 되는 작업과 RPC를 반드시 거쳐야 하는 작업이 나뉜다.**

| 테이블 | anon 권한 |
|--------|-----------|
| `quotes` | select만 (전체 공개) |
| `users` | 자기 행 select/insert/update |
| `users_quotes` | 자기 행 select/insert/update/delete |
| `device_shares` | 자기 행 select만 실질적 사용 (증가는 RPC) |
| `request_quotes` | `select (id)`만. **INSERT 정책이 삭제되어 직접 insert 불가** |
| `request_quote_images` | 자기 신청 또는 이미 게시된 신청의 이미지 |

RPC를 거쳐야 하는 작업:

| RPC | 이유 |
|-----|------|
| `increment_share_count(p_device_id)` | `device_shares` 원자적 증가. 인자가 헤더의 설치 ID와 다르면 예외 |
| `submit_quote_request(text, resoner, tag)` | 30회 공유 조건 검사와 카운터 리셋을 한 트랜잭션에서 수행. **직접 insert는 정책상 차단됨** |
| `get_share_leaderboard()` | RLS 때문에 남의 `users` 행을 읽을 수 없어 랭킹은 함수로만 조회 |
| `is_nickname_available(p_user_id)` | 중복 확인도 남의 행 조회가 필요 |
| `admin_login` / `admin_get_pending_quotes` / `admin_approve_quote` / `admin_reject_quote` / `admin_change_password` | 관리자 기능 전체. 비밀번호 해시는 `private.admin_config`(bcrypt)에 있고 `private` 스키마는 anon에서 접근 불가 |

관리자 인증은 상태를 서버에 두지 않는다. `private.check_admin_password()`가 호출마다 검증하고, 설치 ID 단위로 5회 실패 시 15분 잠금한다. 클라이언트는 비밀번호를 `_AdminPageState._authenticatedPassword`(static, 메모리 전용)에 들고 매 RPC마다 다시 보낸다.

Storage는 `avatars` 버킷 하나를 쓰고 경로 규칙이 정책에 하드코딩되어 있다 — `profiles/{설치ID}.{ext}`, `quote_requests/{설치ID}/{신청ID}.{ext}`. 경로 형식을 바꾸면 RLS가 업로드를 거부한다.

### 마이그레이션 운영

`supabase/migrations/`에 SQL이 있으나 **로컬 `supabase db push` 이력이 없다.** 최신 파일 첫 줄의 주석(`-- Applied to Healing-HI via the Supabase Management API.`)대로, 실제 적용은 Supabase Management API(MCP 서버 `supabase`)를 통해 이뤄지고 파일은 기록용으로 커밋한다. 스키마를 바꿀 때는 마이그레이션 파일 추가와 원격 적용을 모두 해야 하며, 둘 중 하나만 하면 저장소와 실제 DB가 어긋난다.

MCP 서버는 세션마다 인증이 필요하다. 인증 전에는 DB 스키마를 조회할 수 없으므로, 스키마 확인은 `supabase/migrations/`를 읽어서 한다.

파일명 규칙이 두 가지 섞여 있다(`202607280001_` 형식과 `20260804140242_` 형식). 새 파일은 Supabase CLI 표준인 14자리 타임스탬프를 쓴다.

### 공유 카운트가 기능 게이트

`device_shares`에 카운터가 **두 개** 있고 역할이 다르다.

- `share_count` — 누적. 절대 줄지 않는다. 공유 등급과 랭킹의 근거.
- `quote_request_share_count` — 명언 신청용. 신청이 성공하면 서버에서 0으로 리셋된다.

게이트 조건:

| 기능 | 조건 | 위치 |
|------|------|------|
| 닉네임 변경 | `share_count >= 1` | `setting_page.dart` |
| 프로필 사진 설정 | `share_count >= 10` | `_pickAndUploadImage()` |
| 명언 신청 | `quote_request_share_count >= 30` | `submit_quote_request()`에서 서버 검증 |

등급 구간은 `_shareLevel`에 있다(1 / 51 / 201 / 401 → 입문 / 중급 / 고수 / 챔피언). 설정 탭의 "공유 달성도" 막대는 등급이 아니라 `quote_request_share_count / 30`(명언 신청 조건)을 표시한다.

카운트 증가는 **공유가 실제 성공했을 때만** 한다 — `Share.shareXFiles()`의 `ShareResultStatus.success`를 확인한 뒤 `increment_share_count`를 호출한다. 클립보드 폴백 경로에서는 증가시키지 않는다.

### 신청 명언의 ID 규약

`quotes.id`는 **정수가 아니라 text**다. 관리자가 신청을 승인하면 `admin_approve_quote`가 `quotes`에 `id = 'req_' || request_quotes.id` 형태로 행을 넣는다. 그래서:

- 명언 ID는 코드 전반에서 `String`으로 다룬다. `_extractQuoteId()`가 `id ?? idx`를 문자열로 변환하는 이유다.
- 홈 화면은 `req_` 접두어를 가진 명언을 골라 `request_quote_images`에서 저자 이미지를 별도 조회한다.
- 자신이 신청해 게시된 명언은 카드에 파란 테두리와 "내가 신청한 명언" 배지가 붙는다(`_ownRequestQuoteIds`).

### 광고

전면 광고 인스턴스는 `_MainScreenState`가 **단독으로** 소유하고, 자식 화면에는 `onInterstitialRequested` 콜백만 내려준다. 화면 안에서 `InterstitialAd`를 새로 만들면 중복 표시와 누수가 생긴다.

트리거: 탭 전환 10회마다 · 홈에서 명언 30개 스크롤마다 · 다른 앱에서 복귀 시 · 명언 신청 완료 시. 배너는 홈 리스트 5개 카드마다 삽입된다.

`didChangeAppLifecycleState`는 `_isInterstitialShowing`을 검사해, 전면 광고 자체가 만드는 생명주기 변화를 "복귀"로 오인하지 않는다.

광고 유닛 ID는 `.env`에서 오지만 **Android 앱 ID는 `android/app/src/main/AndroidManifest.xml`에 하드코딩**되어 있다.

### 튜토리얼

- 진행 상태는 `users.tutorial_progress`(jsonb)에 `TutorialSection.storageKey`(`home_v1` 등) 단위로 저장된다. 내용을 개편하면 키 버전을 올려 다시 노출시킨다.
- 강조 영역은 `TutorialTargets`의 `GlobalKey`로 실제 위젯 위치를 측정해 그린다. 대상 위젯을 옮기거나 키를 떼면 하드코딩된 `fallbackTarget` 사각형으로 떨어진다.
- **단계 수가 두 곳에 중복 정의되어 있다** — `main.dart`의 `_tutorialStepCount()`와 `tutorial.dart`의 `_stepsFor()`. 단계를 추가·삭제할 때 둘을 함께 고쳐야 하며, 어긋나면 마지막 단계가 잘리거나 진행이 멈춘다.

### 저자 이미지

`assets/resoner/`에 182개 PNG가 있다. `ResonerImageHelper`가 `AssetManifest.json`을 읽어 파일명 인덱스를 만들고, `resolve(imageFile, resonerEng)`로 경로를 얻는다. 해석 순서는 영문명 정확 일치 → `imagefile` 필드 → 부분 일치이며, **같은 저자가 화면마다 다른 이미지로 보이지 않도록 영문명 기준 대표 이미지를 우선한다**(`test/widget_test.dart`의 Saint-Exupéry / Sun Tzu 케이스가 이 동작을 고정한다).

### 알림

`NotificationService`는 싱글톤이다. 반복 알림 대신 **7일치를 `zonedSchedule`로 미리 등록**하고 `DateTimeComponents.dayOfWeekAndTime`로 주 단위 반복시킨다. 활성 상태와 시각은 `SharedPreferences`(로컬 전용, DB에 없음)에 저장하고, 앱 시작 시 `refreshIfEnabled()`가 명언을 새로 뽑아 재등록한다. Android 알림 아이콘은 mipmap이 아닌 drawable에서 찾으므로 `ic_launcher_foreground`를 쓴다.

### 홈 화면 위젯 (Android)

`WidgetDataManager`가 최신 명언 30개를 JSON으로 `HomeWidget.saveWidgetData('quote_data')`에 넣고, Kotlin `QuoteWidgetProvider`가 `HomeWidgetPreferences` SharedPreferences에서 읽어 무작위로 하나를 표시한다. 위젯 탭은 앱 실행이 아니라 새로고침이다(데이터가 없을 때만 앱을 연다). `text_kr` / `resoner_kr` 키 이름이 Dart와 Kotlin 양쪽에 하드코딩되어 있다.

### 관리자 화면 진입

설정 탭의 "프로필 설정" 제목을 **5회 연속 탭**하면 `AdminPage`로 이동한다(`_adminTapCount`). UI에 별도 진입점이 없다.

## 알려진 제약과 주의사항

- `final supabase = Supabase.instance.client;`가 `main.dart`, `home_page.dart`, `search_page.dart`, `like_page.dart`, `setting_page.dart`, `admin_page.dart`에 각각 top-level로 선언되어 있다. 새 화면을 만들 때도 이 패턴을 따르거나, 공용 모듈로 정리하려면 전부 함께 바꿔야 한다.
- `users.language`(`kor`/`eng`)는 저장·표시만 되고 **실제 화면은 항상 `text_kr` / `resoner_kr`을 렌더링한다.** `text_eng` / `tag_eng` 컬럼은 현재 어디서도 표시에 쓰이지 않으며, `resoner_eng`는 저자 이미지 매칭 전용이다. 다국어를 실제로 붙이려면 표시 계층 전체를 손봐야 한다.
- 홈 화면은 `quotes` 전체를 `select()`로 받아 클라이언트에서 `shuffle()`한다. 데이터가 늘어나면 이 경로가 먼저 문제가 된다.
- 로그 출력이 `print()`와 `debugPrint()`로 섞여 있다. `analysis_options.yaml`은 `flutter_lints` 기본값이라 `avoid_print`가 켜져 있지 않다.
- `.env.development`와 `.env.production`은 `pubspec.yaml`의 assets에 등재되어 **앱 번들에 포함된다.** 서버에서만 알아야 하는 비밀은 여기에 두면 안 된다.
- `.github/workflows/supabase-keep-alive.yml`이 주 2회 `quotes`를 조회해 무료 플랜 프로젝트의 휴면을 막는다. `SUPABASE_URL` / `SUPABASE_KEY` 리포지토리 시크릿에 의존한다.
- `AGENTS.md`는 이 문서의 사본이다(현재 낡은 상태). 아키텍처를 바꿀 때 함께 갱신하지 않으면 다른 에이전트가 잘못된 전제로 작업한다.

## 플랫폼 참고

- Android: `minSdkVersion 21`. 알림·부팅 권한과 `UCropActivity`가 매니페스트에 선언되어 있다.
- iOS: 알림 권한을 초기화 시점이 아니라 사용자가 켤 때 요청한다(`requestAlertPermission: false`).
- Windows / Linux / macOS: 빌드는 되지만 AdMob(`AdHelper`가 `UnsupportedError`)과 로컬 알림(`isSupported == false`)이 동작하지 않는다.
- Web: `InstallationIdentity`의 legacy 조회가 `null`을 반환하며 secure storage 동작이 다르다. 실사용 대상이 아니다.
