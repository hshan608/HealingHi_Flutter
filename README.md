# 힐링하이 (HealingHi)

명언을 검색하고, 저장하고, 공유할 수 있는 Flutter 모바일 앱입니다.

## 주요 기능

- **홈 피드** — Supabase에서 가져온 명언을 카드 형태로 탐색
- **검색** — 저자, 본문, 주제별 필터 검색
- **보관함** — 마음에 드는 명언을 저장하고 관리
- **마이페이지** — 프로필 이미지, 언어 설정, 공유 달성도 확인
- **홈 위젯** — 기기 홈 화면에서 명언 확인

## 기술 스택

| 항목 | 사용 기술 |
|------|-----------|
| 프레임워크 | Flutter |
| 백엔드 | Supabase |
| 사용자 식별 | device_info_plus (디바이스 기반) |
| 공유 | share_plus |
| 폰트 | Pretendard |

## 시작하기

### 1. 의존성 설치

```bash
flutter pub get
```

### 2. 환경 변수 설정

프로젝트 루트에 `.env` 파일을 생성합니다:

```
SUPABASE_URL=your_supabase_project_url
SUPABASE_ANON_KEY=your_supabase_anon_key
```

### 3. 앱 실행

```bash
flutter run
```

## 지원 플랫폼

Android · iOS · Windows · macOS · Linux · Web
