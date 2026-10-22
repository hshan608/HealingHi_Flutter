# Supabase 중지 대비 운영 절차

## 보호 범위와 현재 적용 상태

코드가 준비된 것과 실제 운영 중인 것은 다릅니다. 기본 브랜치 반영, 프로젝트 복구,
외부 감시 연결 및 예비 서버 설치를 끝내야 아래 구성이 모두 작동합니다.
이 변경만으로 유료 전환, 외부 계정 생성, 서버 설치 또는 DB 복구가 실행되지는 않습니다.

| 수단 | 동작 | 활성화 조건 |
|---|---|---|
| 정기 DB 점검 | 6시간마다 `quotes` 한 행 이하 조회 및 JSON 검증 | 기본 브랜치 반영, 프로젝트 활성 상태, URL/키 Secrets |
| 일시 장애 재시도 | 네트워크·429·5xx 최대 4회, 10초 간격 | 점검 스크립트에 포함 |
| GitHub 예약 유지 | 최근 커밋이 30일 이상 전이면 heartbeat 커밋 | Actions 쓰기 권한과 브랜치 정책 허용 |
| 외부 실행 감시 | DB/저장소 유지 실패 및 성공 신호 누락 감지 | Healthchecks 체크와 알림 수신자 설정 |
| 독립적인 예비 점검 | 다른 Linux 서버에서 6시간마다 같은 DB 조회 | `ops/run-supabase-check.sh` 설치와 별도 cron |
| 데이터 복구 대비 | DB와 Storage 파일 별도 외부 백업 | 아래 백업 계획 별도 수행 |

무료 플랜은 최근 7일의 DB 활동이 적으면 중지 대상이 될 수 있습니다.
조회 횟수를 늘리는 것은 위험을 줄이는 수단이며 보장이 아닙니다.
**비활동 자동 중지 자체를 제외하려면 Pro 등 유료 플랜을 선택해야 합니다.**
유료 전환 이후에도 서비스 장애 감시와 백업은 필요합니다.
[Supabase 공식 중지 정책](https://supabase.com/docs/guides/platform/free-project-pausing)

## 1. 현재 프로젝트 복구 및 GitHub 활성화

1. Supabase Dashboard에서 Healing-HI 프로젝트 상태를 확인합니다.
   Paused라면 **Resume project / Restore project**로 재개하고 준비 완료까지 기다립니다.
   DNS 실패만으로 중지라고 단정하거나 새 프로젝트를 만들지 않습니다.
2. 프로젝트 URL과 anon/publishable 키가 같은 프로젝트의 것인지 확인합니다.
   GitHub 저장소 **Settings → Secrets and variables → Actions**에 `SUPABASE_URL`,
   `SUPABASE_ANON_KEY`를 등록합니다. 기존 `SUPABASE_KEY`는 대체 이름으로 지원합니다.
   유지 점검에 service-role 키나 DB 관리자 비밀번호는 필요하지 않습니다.
3. 워크플로와 `scripts/supabase_healthcheck.py`를 함께 기본 브랜치에 반영합니다.
4. **Actions → Supabase Keep Alive → Run workflow**에서 기본 브랜치를 선택합니다.
   `ping`의 실제 DB 응답 성공 및 `keep-schedule-enabled` 성공을 확인합니다.
5. 다음 예약 실행까지 발생하는지 확인합니다. 수동 실행 성공만으로 완료 처리하지 않습니다.

공개 저장소는 60일 동안 저장소 활동이 없으면 예약 워크플로가 비활성화될 수 있습니다.
30일 heartbeat 커밋은 이를 대비하지만 브랜치 보호나 권한 때문에 실패할 수 있습니다.
이 경우 `report`는 성공 신호 대신 실패 신호를 보냅니다. 보호 규칙을 무조건 해제하지 말고
허용 가능한 bot 정책을 정하거나 예비 서버를 사용합니다. 이미 비활성화됐다면
GitHub UI에서 **Enable workflow**로 다시 활성화해야 합니다.
[GitHub 예약 실행 제한](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule)

## 2. 실행 자체의 중단을 감지하는 외부 감시

GitHub 안에 감시 워크플로만 추가하면 GitHub 예약 실행이 모두 중단됐을 때 함께 멈춥니다.
외부 서비스가 마지막 성공 신호 시각을 추적해야 이 문제를 감지할 수 있습니다.

1. Healthchecks.io에서 `HealingHi GitHub keep-alive` 체크를 만듭니다.
   **Simple schedule: Period 6 hours, Grace 2 hours**를 지정합니다.
   정상 신호가 끊기면 마지막 성공으로부터 약 8시간 후 감지하는 운영 기준입니다.
2. 수신할 이메일 등 알림 채널을 연결하고 테스트 알림이 실제 도착하는지 확인합니다.
3. `https://hc-ping.com/<UUID>`를 GitHub Secret `KEEPALIVE_HEARTBEAT_URL`로 등록합니다.
   UUID 기본 URL만 사용합니다. `/start`, `/fail`, 쿼리 문자열을 붙이지 않습니다.
4. 기본 브랜치에서 수동 실행 후 체크가 Up으로 전환되는지 확인합니다.
   최초 ping을 보내지 않은 새 체크를 감시가 작동 중인 것으로 간주하지 않습니다.

전체 작업 성공일 때만 성공 신호를 전송합니다. DB 점검이나 저장소 활동 갱신이 실패하면
`/fail`로 알립니다. runner 할당 실패, checkout 실패, 강제 취소 등으로 알림 코드마저 실행되지
못한 경우에는 외부 서비스가 신호 누락으로 감지합니다.
외부 서비스에는 DB 응답, Supabase 키, 사용자 데이터를 보내지 않습니다.
모니터링 서비스가 신호를 수신하지 못하면 해당 보고 작업도 실패 처리합니다.
[Healthchecks 신호 API](https://healthchecks.io/docs/http_api/)

알림 URL이 없는 상태에서는 실행 요약에 **NOT configured** 경고가 나옵니다.
워크플로가 초록색이어도 이 경고가 있다면 외부 실행 중단 감시는 아직 작동하지 않습니다.
GitHub Actions 실패 알림과 Supabase 프로젝트 소유자에게 오는 중지 예고 메일도 수신하도록
계정 알림 설정 및 스팸함을 확인합니다.

## 3. GitHub와 독립적인 예비 스케줄러

별도의 항상 켜진 Linux 서버에서 실행합니다. 개발 PC는 종료/절전될 수 있어 예비 서버로
계산하지 않습니다. 같은 GitHub 저장소에 cron 워크플로를 하나 더 만드는 것으로 대체하지 않습니다.

1. Python 3.10+, Bash, GNU `timeout`, cron이 있는 서버에 점검 파일을 배치합니다.
   예시 경로는 `/opt/healinghi/scripts/supabase_healthcheck.py`,
   `/opt/healinghi/ops/run-supabase-check.sh`입니다.
2. `.env.keepalive.example`을 `/etc/healinghi/keepalive.env`로 복사하고 실제 값을 채웁니다.
   실행 계정만 읽고 쓸 수 있게 소유자를 지정하고 `chmod 600`을 적용합니다.
   환경 파일은 신뢰하는 운영자가 작성한 Bash 변수 할당만 포함해야 합니다.
3. 예비 서버용 **별도 Healthchecks 체크**를 생성합니다. Period 6 hours, Grace 2 hours로
   설정하고 그 URL을 이 환경 파일에 넣습니다. GitHub와 같은 체크를 공유하면 한쪽 고장이
   다른 쪽의 성공 신호에 가려지므로 반드시 분리합니다.
4. 아래 명령으로 수동 실행하고 예비 체크가 Up으로 바뀌는지 확인합니다.

```bash
/usr/bin/timeout 360 /bin/bash /opt/healinghi/ops/run-supabase-check.sh
```

5. 실행 계정의 `crontab -e`에 등록합니다. 서버 시간대가 UTC인 예시입니다.
   GitHub 예정 시각과 겹치지 않는 시간에 실행합니다.

```cron
47 0,6,12,18 * * * /usr/bin/timeout 360 /bin/bash /opt/healinghi/ops/run-supabase-check.sh
```

6. 서버 재시작 후 cron 서비스 및 다음 예약 실행을 확인합니다.
   이후 스크립트 수정 시 예비 서버 파일도 갱신합니다.

외부 요청의 socket timeout은 30초이며, 재시도는 최대 4회입니다.
Actions 작업에는 5분 제한, 예비 실행에는 `timeout` 6분 제한이 있습니다.
전체 실행이 시간 초과로 종료되면 성공 신호가 없으므로 외부 감시가 탐지합니다.

## 4. 알림 발생 시 복구 순서

| 증상 | 우선 조치 |
|---|---|
| GitHub 체크만 Down, 예비 체크 Up | Actions 비활성화·대기열·권한·heartbeat 커밋 오류 확인 |
| 예비 체크만 Down | 서버 전원·cron·환경 파일·배포된 점검 코드 확인 |
| 두 체크 모두 Down | Supabase 프로젝트 상태, DNS, URL/키 및 외부 모니터 장애 확인 |
| DNS 실패 | 프로젝트 주소와 상태 확인; Paused라면 Dashboard에서 재개 |
| 401/403 | 같은 프로젝트의 키인지, anon의 `quotes` 조회 권한이 있는지 확인 |
| 400/404 | Data API 노출 설정 및 `public.quotes` 존재 확인 |
| 429/5xx/timeout | Supabase 상태 페이지와 프로젝트 리소스 상태 확인 |
| HTTP 200인데 JSON 오류 | 실제 Data API 응답인지 확인; 잘못된 응답을 정상 처리하지 않음 |

정상 복구 판정은 Dashboard 활성 상태, 두 점검의 실제 성공, 앱의 홈/검색 조회,
다음 정기 실행 성공까지 확인한 후 내립니다. 점검은 읽기 전용이며 앱의 쓰기 기능 전체를
검증하지는 않습니다. 빈 배열은 빈 테이블 또는 RLS 필터 결과일 수 있으므로 데이터 존재를
보장하는 신호로 쓰지 않습니다.

## 5. 데이터 손실 대비 별도 백업

이 점검은 백업을 만들지 않습니다. 무료 플랜은 정기적인 외부 DB export를 권장하며,
DB 백업에는 Storage의 실제 파일이 포함되지 않습니다.
[Supabase 백업 문서](https://supabase.com/docs/guides/platform/backups)

운영 기준으로 매일 DB 스키마·역할·데이터를 외부 저장소에 암호화 보관하고,
`avatars` 등의 Storage 파일도 별도로 백업합니다. 보관 기간은 최소 30일로 잡고,
월 1회 격리된 환경에 복원하여 명언·사용자·보관함 관계 및 프로필 이미지를 점검합니다.
이 기준은 제안이며 백업 저장소와 작업을 구성하기 전까지 백업이 존재한다고 간주하지 않습니다.
DB 비밀번호나 백업을 공개 저장소/Actions 로그에 올리지 않습니다.
실제 export·복원 명령은
[Supabase CLI 백업·복원 절차](https://supabase.com/docs/guides/platform/migrating-within-supabase/backup-restore)를 따릅니다.

## 6. 적용 완료 판정

- [ ] 기본 브랜치에 워크플로·Python 스크립트 반영
- [ ] 프로젝트 활성 상태 및 수동 DB 점검 성공
- [ ] 외부 모니터 두 개의 수신자와 테스트 알림 확인
- [ ] GitHub와 예비 서버 모두 첫 성공 신호 수신
- [ ] 두 환경 모두 다음 예약 실행 성공
- [ ] 별도 테스트 체크에서 의도적인 실패 및 신호 중단 알림 확인
- [ ] 저장소 쓰기 제한에 따른 heartbeat 실패 대응 확인
- [ ] 외부 DB/Storage 백업 및 복원 점검 완료

테스트 명령: `python -m unittest discover -s scripts/tests -v`.
`Supabase Safety Tests`는 해당 코드 변경 시 실제 서비스 연결 없이 회귀 테스트를 실행합니다.
