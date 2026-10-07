# Horse Legacy

말을 육성하고 경주·은퇴·교배를 거쳐 목장의 혈통을 이어가는 시뮬레이션 게임.

현재 버전은 **0.2.0 / P1-02**다. 새 게임과 말 조회, 수동 저장·불러오기·이전 저장 백업 복구를 지원한다. 훈련·경주·시간 진행·교배는 아직 구현하지 않았다. 종료 전에 저장해야 진행 내용이 보존된다.

## 실행

Godot **4.6.3 Standard**가 필요하다. .NET이나 외부 플러그인은 사용하지 않는다. 한국어 표시는 Noto Sans CJK KR, 맑은 고딕, Apple SD Gothic Neo 등 설치된 시스템 글꼴을 사용한다. 현재 클라우드에서는 Noto Sans CJK KR로 검증했다.

Godot 편집기에서 `project.godot`를 열고 **F5(프로젝트 실행)**를 누른다. 또는 그래픽 데스크톱에서 저장소 루트를 작업 디렉터리로 사용한다.

```bash
godot --editor --path .
# 편집기 없이 실행하려면:
godot --path .
```

현재 클라우드에서는 엔진 실행 전 같은 셸에서 다음 경로 설정을 적용한다.

```bash
source /workspace/horse-legacy-environment/activate.sh
cd /workspace/horse-legacy
```

클라우드 기본 셸에는 화면 서버가 없으므로 일반 창 실행과 headless 검증을 구별한다. `--headless` 실행은 사용자용 미리보기 화면을 제공하지 않는다.

## 조작

1. **새 게임 시작**으로 새벽들 목장을 만든다.
2. 왼쪽 마방에서 Black Arrow 또는 Silver Mist를 선택한다.
3. 성별·나이·능력·잠재력·컨디션·전적·부모 기록을 확인한다.
4. **저장**으로 현재 목장을 기록한다. 기존 저장이 있으면 덮어쓰기를 확인하고, 기존의 유효한 저장을 백업으로 남긴다.
5. **불러오기** 또는 시작 화면의 **저장한 목장 이어하기**로 복원한다. 플레이 중 불러오기에는 저장하지 않은 진행을 버릴지 확인한다.
6. **백업 복구**는 한 번 이전에 저장한 상태로 돌아간다. 확인 후 현재 저장 파일을 복구하며, 복구 전 원본은 별도로 보존한다.
7. **새 목장 시작**은 확인 후 메모리의 데이터를 초기화한다. 기존 저장 파일은 다음 저장을 확인하기 전까지 유지한다.

버튼은 마우스 또는 Tab으로 선택하고 Enter/Space로 작동할 수 있다. 작은 창에서는 세로 스크롤을 사용한다.

## 저장 파일

저장 슬롯은 하나이며 `user://saves/ranch.json`을 사용한다. 현재 클라우드의 실제 경로는 `/workspace/horse-legacy-environment/data/horse-legacy/saves/ranch.json`이다. 다른 컴퓨터에서는 Godot 사용자 데이터 폴더 아래에 저장된다.

- `ranch.json`: 마지막으로 완료한 저장.
- `ranch.json.bak`: 한 번 이전의 유효한 저장. 최초 저장에는 아직 백업이 없다.
- `ranch.json.before-recovery`: 가장 최근 백업 복구 직전의 원본. 손상된 파일도 원래 바이트 그대로 보존한다.
- `.tmp`, `.bak.tmp`: 교체 전 임시 파일. 불러오기에서는 무시한다.

불러오기에 실패해도 현재 게임을 바꾸지 않는다. 손상되었거나 지원하지 않는 버전의 기존 저장은 일반 저장으로 덮어쓰지 않는다. 유효한 백업이 있다면 **백업 복구**를 사용한다. 자동 저장·여러 슬롯·클라우드 동기화는 아직 제공하지 않는다.

파일 형식과 호환성 규칙은 [docs/SAVE_FORMAT.md](docs/SAVE_FORMAT.md)에 기록했다.

## 검사

최초 체크아웃에서는 먼저 import하여 전역 스크립트 클래스를 등록한다. `.godot/`는 생성 캐시이며 Git에 포함하지 않는다. `.gd.uid`는 Godot 스크립트 식별 파일이므로 소스와 함께 유지한다.

```bash
godot --headless --path . --editor --import --quit
godot --headless --path . --script res://tests/run_tests.gd
godot --headless --path . --quit-after 3
```

검사 실행기는 성공 시 0, 실패 시 1을 반환한다. 현재 **119개 검사**가 기존 기능, 저장 데이터 검증, 손상·부분 쓰기·교체 실패, 백업 복구, 저장 UI를 검증한다. 별도 writer 프로세스가 저장 후 종료하고, reader 프로세스가 모든 필드와 난수 연속성을 복원해 다시 저장·로드하는 검사도 포함한다.

UI 검사는 루트 뷰포트에 마우스 입력을 전달한다. 테스트는 실행별 고유 폴더를 사용하며 실제 `saves/ranch.json`을 건드리지 않는다. 성공하면 테스트 파일을 정리하고, 실패하면 출력된 경로에 증거를 남긴다.

그래픽 데스크톱에서 같은 검사를 실제 렌더링과 함께 수행할 수 있다.

```bash
godot --path . --script res://tests/run_tests.gd -- --screenshots=/tmp/horse-legacy-screenshots
```

이 경우 시작 화면·마방·불러온 화면 캡처 검사가 추가되어 총 **122개**다. 클라우드에서는 Xorg dummy 디스플레이와 Mesa 소프트웨어 렌더링으로 확인했다. 물리 장치 입력·다른 OS·게임 배포 빌드는 아직 검증하지 않았다.

## 구조와 다음 작업

- `src/domain/`: 화면과 독립적인 말·능력·목장·게임 상태.
- `src/application/`: 초기 설정 검증, 새 게임 생성, 선택 상태 관리.
- `src/presentation/`: 시작·마방·말 상세 화면.
- `src/persistence/`: 명시적인 DTO, 버전·참조 검증, 저장 파일 교체와 백업 복구.
- `data/rules/new_game.json`: 초기 말의 이름·성별·나이·능력·잠재력. 현재 값은 개발용 초기 콘텐츠이며 최종 밸런스가 아니다.
- `tests/run_tests.gd`: 의존성 없는 Godot 테스트 실행기.

다음 작업은 **P1-03: 주간 진행·나이·성장·회복의 연결**이다. 말 목록·상세 화면은 이미 구현되어 있다.

작업 전 [DEVLOG.md](DEVLOG.md)를 읽는다. 전체 계획은 [DEVELOPMENT_PLAN.md](DEVELOPMENT_PLAN.md), 확정된 규칙과 기술 선택은 [DESIGN_DECISIONS.md](DESIGN_DECISIONS.md)에 기록한다.
