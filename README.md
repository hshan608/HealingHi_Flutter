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

## Supabase 유지 및 Actions 실패 복구

`.github/workflows/supabase-keep-alive.yml`은 6시간마다 한국 시간
00:17 / 06:17 / 12:17 / 18:17에 `quotes` 테이블을 최대 한 행 조회하고,
실제 JSON 응답까지 검증합니다. GitHub 스케줄 실행은 지연되거나 누락될 수 있습니다.
저장소의 **Settings → Secrets and variables → Actions**에 다음 값을 설정합니다.

- `SUPABASE_URL`: 해당 프로젝트의 `https://<project-ref>.supabase.co` 주소
- `SUPABASE_ANON_KEY`: 해당 프로젝트의 anon 또는 publishable 키
  (기존 `SUPABASE_KEY`도 지원하며, 둘 다 있으면 `SUPABASE_ANON_KEY`를 우선 사용)
- `KEEPALIVE_HEARTBEAT_URL`: 외부 Healthchecks.io 감시용 UUID ping URL.
  점검 실패뿐 아니라 예약 실행 자체가 사라진 경우도 감지합니다.
  없으면 DB 점검은 실행되지만 외부 감시는 비활성 상태이며 실행 요약에 경고합니다.

실패 시 Actions의 실행 요약에 표시된 원인을 확인합니다.

- **DNS 오류 / curl exit 6**: Supabase Dashboard에서 프로젝트 상태와 URL을 확인합니다.
  프로젝트가 Paused라면 먼저 **Restore project**로 복구하고 준비가 끝날 때까지 기다립니다.
  중지된 프로젝트는 REST 요청을 반복하는 것만으로 복구되지 않습니다.
- **HTTP 401/403**: 키가 같은 프로젝트의 것인지, `quotes` 조회 권한이 있는지 확인합니다.
- **HTTP 400/404**: 프로젝트 URL과 Data API의 `public.quotes` 노출 여부를 확인합니다.
- **HTTP 429/5xx 또는 연결 오류**: 자동 재시도 후에도 실패하면 프로젝트 및 서비스 상태를 확인합니다.

복구 또는 Secrets 변경 후 **Actions → Supabase Keep Alive → Run workflow**로
DB 조회 성공을 확인합니다. 예약 실행은 기본 브랜치의 워크플로를 사용하므로
수정 사항을 기본 브랜치에 반영해야 적용됩니다.
주기적인 요청이 무료 프로젝트의 일시 중지 방지를 보장하지는 않습니다.
[Supabase 프로젝트 일시 중지 안내](https://supabase.com/docs/guides/platform/free-project-pausing)를 참고하세요.

**[전체 운영·활성화·장애 복구 절차](docs/supabase-operations.md)**에 외부 감시 연결,
GitHub와 독립적인 예비 스케줄러 설치, 백업 계획 및 검증 방법을 정리했습니다.
실패·재시도·알림 동작은 다음 명령으로 실제 서비스 접속 없이 검증합니다.

```bash
python -m unittest discover -s scripts/tests -v
```

## 지원 플랫폼

Android · iOS · Windows · macOS · Linux · Web
