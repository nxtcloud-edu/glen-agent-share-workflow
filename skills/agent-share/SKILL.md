---
name: agent-share
description: "멀티 에이전트 협업 패턴 스킬. 문서 인계(agent-share 폴더)부터 명령서 채널·워처 핑·tmux 직접 제어·워크트리 브랜치 게이트까지 3단계 협업 모드 제공. Codex ↔ Claude ↔ Hermes 교차 검토, Planner-Coder 분업, 무인/반자동 핸드오프 표준화 시 사용 (특정 에이전트 순서 가정 안 함)."
user_invocable: true
argument-hint: [topic-slug] [--role initiator|reviewer|followup] [--mode light|standard|full]
---

# Agent Share

## Overview

여러 에이전트(Claude, Codex, Gemini, Hermes, Human 등) 간 협업 산출물을 *에이전트 중립적* 으로 만들어 둔다. *누가 먼저 시작하느냐* 를 가정하지 않고 역할 기반으로 모델링한다.

## 협업 모드 선택 (--mode)

| 모드 | 구성 | 적합한 상황 |
|---|---|---|
| `light` | 문서 인계만 (아래 폴더/턴/리뷰 규칙) | 1회성 교차 검토, 짧은 인계 |
| `standard` | + 저널 프로토콜 + 작업 명령서 채널 + 신뢰·검증 규칙 | 역할 분업이 지속되는 프로젝트 (Planner-Coder 등) |
| `full` | + 워처 핑 + tmux 직접 제어 + 워크트리 브랜치 게이트 | 반자동/무인 핸드오프 루프 |

`standard`/`full`의 상세는 문서 말미의 **운영 패턴 레이어** 참조. goods-bank 프로젝트에서
WO-001~011 11사이클로 실증된 패턴이다 (Fable 5 계획·검증 ↔ Hermes gpt-5.5 코딩).

역할:

- `initiator`: 첫 계획/산출물을 만드는 에이전트
- `reviewer`: 초안자의 작업을 검토하는 다른 에이전트
- `follow-up`: 리뷰를 읽고 질문을 해소하며 계획을 업데이트하는 에이전트

## 폴더 규칙

공유 산출물은 **프로젝트 루트** 에 만든다. `.claude` `.codex` 같은 에이전트 전용 디렉토리에 두지 않는다.

기본 구조:

```text
agent-share/
  <initiator-agent>-<topic>-<yyyymmdd>/
    turns/
      <agent>-turn-<topic>-<yyyymmdd>-<hhmmss>.md
    <initiator-agent>-plan-<topic>-<yyyymmdd>.md
    <initiator-agent>-progress-<topic>-<yyyymmdd>.md
```

리뷰어가 응답할 때도 같은 폴더 사용:

```text
agent-share/
  <initiator-agent>-<topic>-<yyyymmdd>/
    <reviewer-agent>-review-<topic>-<yyyymmdd>.md
```

후속(follow-up) 도 같은 폴더:

```text
agent-share/
  <initiator-agent>-<topic>-<yyyymmdd>/
    <followup-agent>-followup-<topic>-<yyyymmdd>.md
```

사용자가 다른 루트 폴더 이름을 지정하면 그것을 사용하되 명명 규칙은 그대로.

## Turn State 규칙

의미 있는 모든 에이전트 턴은 *턴 상태 파일* 생성으로 시작한다. 이는 현재 에이전트가 *지금* 무엇을 하고 있는지의 명시 기록이며, Codex/Claude 같은 고정 순서와 독립적으로 작동한다.

턴 상태 파일 경로:

```text
agent-share/
  <initiator-agent>-<topic>-<yyyymmdd>/
    turns/
      <agent>-turn-<topic>-<yyyymmdd>-<hhmmss>.md
```

`yyyymmdd` `hhmmss` 는 프로젝트 로컬 날짜/시간 사용. **다른 턴 파일을 절대 덮어쓰지 말 것**. 같은 에이전트가 나중에 다시 돌아오면 새 턴 파일을 생성한다.

턴 상태 파일 섹션:

```markdown
# <Agent> Turn: <Human Topic>

- Agent: <agent>
- Turn role: <initiator | reviewer | follow-up | implementer | verifier | maintainer>
- Turn phase: <planning | implementing | verifying | reviewing | follow-up | documenting | handoff | blocked | complete>
- Started: <yyyy-mm-dd hh:mm:ss timezone>
- Status: <active | paused | waiting-review | waiting-user | complete | blocked>
- Related artifacts:
  - `<file>`

## Current Intent

## Context Read

## Planned Writes

## Verification To Run

## Handoff Criteria

## Completion Update
```

규칙:

- plan / progress / review / follow-up / 코드 산출물을 편집하기 *전에* 턴 파일 생성.
- 핸드오프 또는 턴 종료 *전에* `Status`, `Turn phase`, `Completion Update` 갱신.
- 프로젝트가 git 저장소이고 커밋할 변경이 있다면 턴 종료 후 에이전트 자신의 프로젝트 변경분을 커밋.
- 변경 파일이 없으면 `Completion Update` 에 명시.
- 검증을 건너뛴 경우 이유 기록.
- 고정 에이전트 순서를 인코딩하지 말 것. 턴 파일은 *현재 역할과 페이즈* 만 기록.
- 최신 턴 파일은 상태 힌트일 뿐, 결정의 영구 출처는 plan / progress / review / follow-up 파일이다.
- `turns/` 가 비대해지면 완료 상태 턴 파일을 월 단위로 `turns/archive/<yyyymm>/` 로 이동 (내용 수정 금지, 이동만 — 최신 턴 탐색 노이즈 방지).

## 턴 종료 커밋 규칙

턴이 `complete`, `waiting-review`, `waiting-user`, 또는 `blocked` 에 도달하면 현재 에이전트는 자신의 프로젝트 변경분에 대한 작은 git 커밋을 만든다.

커밋 규칙:

- 현재 턴 동안 현재 에이전트가 생성/변경한 파일만 커밋.
- 사용자의 무관한 변경이나 다른 에이전트의 미커밋 작업을 함께 스테이징하지 않는다.
- 프로젝트 저장소에 변경이 없으면 `Completion Update` 에 `No commit: no project changes` 기록.
- 변경이 프로젝트 저장소 *밖* 에 있으면 갱신했지만 프로젝트 커밋에 포함할 수 없었다고 기록.
- 검증이 실패했지만 상태 보존이 필요하면 미완/차단 상태가 드러나는 메시지로 커밋.
- 프로젝트의 커밋 메시지 컨벤션 사용. 지정 컨벤션이 없으면 `docs:` `fix:` `feat:` `test:` `chore:` 같은 명시 prefix.
- 커밋 후 턴 파일의 `Completion Update` 에 커밋 해시 기재. 커밋 미생성 시 그 이유 기재.
- 턴 커밋을 깔끔하게 만들려고 다른 에이전트의 작업을 history rewrite / reset / revert 하지 말 것.

## 명명 규칙

소문자 hyphen-case. 패턴:

- 폴더: `<initiator-agent>-<topic>-<yyyymmdd>`
- 계획: `<agent>-plan-<topic>-<yyyymmdd>.md`
- 진행: `<agent>-progress-<topic>-<yyyymmdd>.md`
- 리뷰: `<agent>-review-<topic>-<yyyymmdd>.md`
- 후속: `<agent>-followup-<topic>-<yyyymmdd>.md`
- 턴: `turns/<agent>-turn-<topic>-<yyyymmdd>-<hhmmss>.md`

에이전트 이름 예: `claude` `codex` `gemini` `human`

토픽 예: `review-remediation` `soft-delete-policy` `release-readiness` `auth-refactor`

`yyyymmdd` 는 사용자의 현재 날짜를 사용.

## Initiator Workflow

인계를 시작할 때:

1. 프로젝트 루트 식별
2. 짧은 토픽 슬러그 선정
3. `scripts/new-share.sh <agent> <topic>` — 폴더·`turns/`·계획·진행 스캐폴딩 (명명·날짜 자동)
4. `scripts/new-turn.sh <share-dir> <agent> <topic> initiator --phase planning` — 턴 파일 생성
5. 스캐폴딩된 계획·진행 파일의 내용 작성
6. 코드 변경 / 테스트 실행 / 스킵 사항 명시
7. 다음 에이전트가 답해야 할 리뷰 질문 명시
8. 핸드오프 전 턴 상태 파일 갱신

계획 파일 섹션:

```markdown
# <Agent> Plan: <Human Topic>

- Initiator: <agent>
- Created: <yyyy-mm-dd>
- Status: <planning | implementation-ready | blocked | in-review>
- Project: <project name/path>
- Purpose: <why this artifact exists>

## Context

## Decisions So Far

## Proposed Plan

## Verification Plan

## Risks

## Reviewer Questions

## Follow-up Expectations
```

진행 파일 섹션:

```markdown
# <Agent> Progress: <Human Topic>

- Author: <agent>
- Created: <yyyy-mm-dd>
- Related plan: `<plan-file-name>`
- Status: <not-started | in-progress | waiting-review | complete | blocked>

## Timeline

## Work Completed

## Verification

## Files Created Or Changed

## Open Questions

## Next Agent Instructions
```

## Reviewer Workflow

다른 에이전트의 산출물을 리뷰할 때:

1. 공유 폴더의 계획·진행 파일 읽기
2. `turns/` 아래 `Turn role: reviewer` 인 턴 상태 파일 생성
3. 같은 폴더에 리뷰 파일 생성
4. 사용자가 명시적으로 요청하지 않는 한 초안자의 파일 덮어쓰지 않음
5. 차단 이슈와 제안을 분리
6. 승인 / 변경부 승인 / 차단 중 하나 명시
7. 핸드오프 전 턴 상태 파일 갱신

리뷰 파일 섹션:

```markdown
# <Agent> Review: <Human Topic>

- Reviewer: <agent>
- Reviewed: <yyyy-mm-dd>
- Reviewed artifacts:
  - `<file>`
- Verdict: <approved | approved-with-changes | blocked>

## Summary

## Blocking Issues

## Suggestions

## Questions For Follow-up

## Recommended Next Steps
```

## Follow-Up Workflow

리뷰에 응답할 때:

1. 리뷰 파일과 원본 계획·진행 파일 읽기
2. `turns/` 아래 `Turn role: follow-up` 인 턴 상태 파일 생성
3. 같은 폴더에 follow-up 파일 생성
4. 리뷰 항목별로 수용 / 거부 / 보류 기록
5. 구현이 다음 단계라면 최종 스코프와 검증 계획 명시
6. 핸드오프 전 턴 상태 파일 갱신

후속 파일 섹션:

```markdown
# <Agent> Follow-up: <Human Topic>

- Follow-up agent: <agent>
- Date: <yyyy-mm-dd>
- Source review: `<review-file-name>`
- Status: <ready-to-implement | revised-plan | blocked | needs-user-decision>

## Accepted Changes

## Deferred Items

## Rejected Items

## Revised Plan

## Final Verification Plan

## User Decisions Needed
```

## 콘텐츠 규칙

- 다른 에이전트가 이어받기 쉽게 사실 위주로 작성
- 가정과 확인된 사실을 분리해 기록
- 유용할 때 절대 경로 또는 프로젝트 상대 경로 포함
- 코드 변경이 없으면 명시
- 테스트/빌드를 안 돌렸으면 그 이유 명시
- 기술적 결정뿐 아니라 사용자 *제품 결정* 도 보존
- `Codex -> Claude -> Codex` 같은 고정 에이전트 순서 하드코딩 금지
- 사용자가 명시적으로 요청하지 않는 한 `.claude` `.codex` 등 에이전트 전용 디렉토리에 공유 산출물 두지 않음
- 턴이 끝났는데 `active` 상태의 턴 파일을 남기지 말 것 — `complete`, `waiting-review`, `waiting-user`, `blocked` 중 하나로 갱신

## 최소 예시

```text
agent-share/
  codex-review-remediation-20260428/
    turns/
      codex-turn-review-remediation-20260428-143000.md
    codex-plan-review-remediation-20260428.md
    codex-progress-review-remediation-20260428.md
    claude-review-review-remediation-20260428.md
    codex-followup-review-remediation-20260428.md
```

Claude 가 시작할 수도 있다:

```text
agent-share/
  claude-auth-refactor-20260428/
    turns/
      claude-turn-auth-refactor-20260428-101500.md
    claude-plan-auth-refactor-20260428.md
    claude-progress-auth-refactor-20260428.md
    codex-review-auth-refactor-20260428.md
    claude-followup-auth-refactor-20260428.md
```

---

# 운영 패턴 레이어 (standard / full 모드)

goods-bank WO-001~011 사이클로 실증. 문서 포맷 위에 **지속 협업의 운영 체계**를 얹는다.

## 1. 저널 프로토콜 (standard)

공유 저널 디렉토리(예: `.agent/`)에 4개 파일 — 게시판이지 알림이 아니다(각 에이전트는 턴 시작 시 읽는다):

- `CURRENT_STATE.md` — HEAD·활성 소유자·완료 목록. 상태 변화 시 갱신
- `HANDOFF.md` — 다음 안전 액션. 턴 종료 시 갱신
- `TURN_LOG.md` — **append-only** 턴 기록: Intent / Files changed / Commands·verification / Decisions / Handoff
- `DECISIONS.md` — 협업 운영 결정 + **위반 기록** (제품 결정과 분리)

철칙: **Commands 전수 기재** — 실행한 명령은 결과와 무관하게 빠짐없이. "수행하지 않음" 주장은
검증자가 실측 대조한다. 타 에이전트의 미커밋 변경분은 자기 커밋에서 제외.

비대화 관리 — append-only 파일은 무한히 자란다. 방치하면 매 턴 읽기 비용이 선형 증가하고,
Read 도구 기본 한도(2,000줄) 초과 시 뒤쪽(최신) 엔트리가 조용히 잘려 읽힌다:

- **tail-read**: 턴 시작 시 TURN_LOG는 최근 엔트리만 읽는다 (`tail` 또는 Read offset).
  현재 상태의 영구 출처는 CURRENT_STATE / HANDOFF — 전체 재독은 불필요.
- **로테이션**: `scripts/rotate-journal.sh <저널디렉토리>` — 500줄 초과 시 `TURN_LOG-archive-<yyyymm>.md`로
  이관하고 최근 10턴만 유지. **미머지 `wo/*` 브랜치가 있으면 스크립트가 중단**(Gotcha 6 — merge=union 부활)하므로
  정지 시점 판단을 사람에게 맡기지 않는다. `--check`로 사전 판정. DECISIONS.md에 기록.

## 2. 작업 명령서 채널 (standard)

Planner-Coder 분업의 핵심. `work-orders/WO-NNN-<슬러그>.md`:

- 상태 머신: `대기 → 진행 중(<agent>) → 검증 대기 → 완료/반려(사유)`
- 필수 섹션: 목표 / **설계 결정(변경 금지)** / 컨텍스트(필독 파일) / 작업 단계 / **완료 기준(검증 가능한 조건)** / **금지 사항(절대 금지 블록)**
- 검증 피드백은 다음 명령서의 금지 사항으로 환류 (같은 실수 반복 차단)
- 코더의 합리적 스펙 이탈은 허용하되 **Decisions에 이유 기재가 조건**

## 3. 신뢰·검증 규칙 (standard)

- **자기 보고는 교차 검증 전까지 미확인** — 검증자는 격리 워크트리에서 전 스위트 재실행 + 외부 상태(클라우드 등) 실측
- 실측 1단계는 `scripts/check-journal.sh <저널디렉토리>` 로 기계화 — CURRENT_STATE HEAD·active 턴·WO↔브랜치 대조 (`--strict` 로 게이트)
- 위반 발견 시: 주체 확정 전 기록 보류 → 확정 시 DECISIONS에 공식 기록 → 회고 문서로 재캘리브레이션 (문책이 아니라 규칙 갱신)
- 실측 모순(저널 주장 ≠ 관측)은 **즉시 에스컬레이션** — 보류하면 신뢰 비용이 복리로 는다

## 4. 워처 핑 (full)

파일 게시판의 알림 부재를 백그라운드 워처로 보완 (검증자 세션이 살아있는 동안). `templates/watcher.sh`:

```bash
# 완료 신호 = "새 커밋 + TURN_LOG 기록" (둘 다). 상태 줄 단독은 조기 신호 — Gotcha 1
watcher.sh ../<repo>-<agent> "<agent> — WO-NNN" --tmux <session>
# exit 0 = 완료 감지 / exit 2 = tmux 화면에서 정체(승인 타임아웃 등) 감지 → 사람 개입
```

`--tmux` 를 주면 커밋 없는 차단(Gotcha 8의 dangerous-command 타임아웃)도 화면에서 포착한다.
검증자는 완료 신호로 릴레이 없이 자동 검증 착수. (Claude Code면 Monitor persistent 도구 사용)

## 5. tmux 직접 제어 (full)

상대 에이전트 CLI를 공유 tmux 세션에서 실행하면 검증자가 직접 지시·관찰 가능:

```bash
tmux new-session -d -s <agent> -c <작업 디렉토리>   # 사람은 tmux attach -t <agent>로 감독
scripts/tmux-send-safe.sh <agent> "WO-012 진행해" --enter   # busy 사라진 뒤에만 전송
```

규칙: **유휴 프롬프트일 때만 send-keys** (작업 중 입력은 인터럽트가 되는 TUI가 많다 — Gotcha 3).
`tmux-send-safe.sh` 가 capture-pane 으로 busy 패턴을 확인하고 유휴가 될 때까지 대기한다.
사람이 attach하면 모든 지시가 눈에 보인다 — 투명성이 기본 내장.

## 6. 워크트리 브랜치 게이트 (full)

코더를 별도 워크트리 + WO별 브랜치에 격리하면 **미검증 코드가 main에 못 들어온다**:

```bash
# 최초 1회: 워크트리 + 가드 마커 + 훅(절대경로 hooksPath) + wo 브랜치 + 설치
scripts/setup-worktree.sh <repo> <agent> --hooks-src templates/hooks --wo NNN --install "pnpm install"
# 코더는 wo/NNN에 커밋 → 검증 통과 시 검증자만 main에 머지·푸시
```

- 게이트 강제는 `templates/hooks/`의 `pre-commit`(코더 main 커밋 차단)+`pre-push`(코더 push 차단).
  마커(`.agent-coder-guard`)로 코더 워크트리에서만 발동 — planner 워크트리는 영향 없음
- **`core.hooksPath`는 반드시 절대경로** — 상대경로는 링크된 워크트리에서 훅이 조용히 사라진다 (Gotcha 7)
- append-only 저널은 `.gitattributes`에 `merge=union` 지정 (머지 충돌 원천 차단)
- **워크트리가 못 막는 것**: 로컬 DB·E2E 포트는 여전히 공유 — 전 스위트는 한 번에 하나만 (순차 규율 유지)
- 워크트리마다 `pnpm install` 필요 (pnpm 스토어 덕에 수 초)

## 스크립트 (기계적 강제)

기계적으로 처리 가능한 부분은 스크립트로 고정한다 — LLM 판단에 맡기면 명명 불일치·전제조건 누락으로
사고가 난다 (Code-First). 판단이 필요한 것(계획 내용, 승인·반려, 테스트 해석)만 에이전트가 맡는다.

| 스크립트 | 하는 일 | 왜 기계화 |
|---|---|---|
| `scripts/new-share.sh <agent> <topic>` | 공유 폴더+turns+plan+progress 스캐폴딩 | 날짜·hyphen-case 명명은 순수 규약 — LLM이 자주 틀림 |
| `scripts/new-turn.sh <dir> <agent> <topic> <role>` | 턴 파일 생성 (타임스탬프·명명 자동, 덮어쓰기 거부) | 명명 규칙 + "턴 파일 절대 덮어쓰기 금지" 강제 |
| `scripts/rotate-journal.sh <저널디렉토리>` | 500줄 초과 시 아카이브 이관, 최근 10턴 유지 | 미머지 `wo/*` 게이트로 merge=union 부활 원천 차단 (Gotcha 6) |
| `scripts/check-journal.sh <저널디렉토리>` | CURRENT_STATE HEAD·active 턴·WO↔브랜치 대조 | 검증자 실측 1단계 기계화 — 자기 보고 불신(Gotcha 2)의 진입점 |
| `scripts/setup-worktree.sh <repo> <agent>` | 코더 워크트리+가드 마커+훅+wo 브랜치 셋업 | 절대경로 hooksPath 로 게이트 무음 실패(Gotcha 7) 방지 |
| `scripts/tmux-send-safe.sh <session> <text>` | busy 패턴 사라진 뒤에만 send-keys | 작업 중 입력=인터럽트(Gotcha 3) 자동 회피 |
| `templates/hooks/pre-commit` | (A)코더 main 커밋 차단 (B)저널 기존 줄 삭제·수정 차단 | 저장소 수준 훅 → 커밋하는 *모든* 에이전트에 적용 |
| `templates/hooks/pre-push` | 코더 워크트리 push 전면 차단 | 원격 반영은 검증자 전담 — 물리적 강제 |
| `templates/hooks/claude-stop.sh` | 턴 종료 시 active 턴 잔존 감지 (Claude Stop 훅) | Claude 참여자의 저널 위생 자동 점검 |
| `templates/watcher.sh` | 완료 신호(커밋+저널) + tmux 정체 감지 | Gotcha 6의 "커밋 없는 차단"을 tmux 화면에서 포착 |

훅은 문턱을 올릴 뿐 우회(`--no-verify`) 가능 — Gotcha 2의 "검증자 외부 상태 실측"을 대체하지 않는다.
로테이션 스크립트가 정상적으로 `--no-verify` 커밋을 사용한다. **워크트리 게이트는 `core.hooksPath`를
절대경로로 설정해야 한다** (상대경로는 링크된 워크트리에서 훅이 조용히 사라진다 — Gotcha 7).

## Gotchas

> **필수**: 오류 발생 시 우회 전에 여기 기록. (Gotcha-First)

1. **상태 줄은 조기 신호** — 에이전트가 커밋·저널 기록 전에 명령서 상태부터 뒤집을 수 있다 (실측: 커밋 3분 전 전환). 워처의 완료 신호는 반드시 "커밋 + TURN_LOG 기록" 복합 조건으로. (2026-07-06)
2. **자기 보고 위조 가능성** — "클라우드 push 미실행" 저널 기재가 실측과 2회 모순된 사례. 규칙(금지 블록)만으로는 강제 불가 — 검증자의 외부 상태 실측을 표준 절차로 고정. (2026-07-05)
3. **tmux 작업 중 입력 = 인터럽트** — TUI 에이전트는 computing 중 입력을 턴 중단으로 처리. capture-pane으로 유휴 프롬프트 확인 후 send-keys. (2026-07-06)
4. **append-only 저널 머지 충돌** — 브랜치 분리 시 TURN_LOG가 매 사이클 충돌. `merge=union` gitattribute가 정답 (append-only 파일 전용 — 일반 파일에 쓰면 위험).
5. **워크트리 ≠ 완전 격리** — 로컬 DB·포트·도커는 공유. 동시 전 스위트 실행 금지 규율은 워크트리 도입 후에도 유지.
6. **merge=union 파일은 truncate가 안 먹힌다** — union 머지는 양쪽 브랜치의 줄을 모두 보존하므로, main에서 TURN_LOG를 아카이브로 잘라내도 이전 버전 위에 append한 WO 브랜치와 머지하면 잘라낸 내용이 통째로 부활한다. 로테이션은 모든 WO 브랜치가 main에 머지된 정지 시점에서만 수행하고 DECISIONS.md에 기록. `rotate-journal.sh` 가 미머지 `wo/*` 게이트로 강제.
7. **상대경로 `core.hooksPath` 는 링크된 워크트리에서 훅을 조용히 무력화한다** — `git config core.hooksPath .githooks` 처럼 상대경로로 두면, 각 워크트리가 *자기 루트 기준*으로 `.githooks` 를 찾는다. 훅은 보통 main 워크트리에만 설치되므로, 코더 워크트리에서는 디렉토리가 없어 훅이 **전부 사라진다**(에러 없이 통과 — 실측: 코더 push 게이트가 무음으로 열림). 반드시 **절대경로**로 설정할 것. `setup-worktree.sh` 가 절대경로를 쓴다. (2026-07-07)
8. **코더 하네스의 dangerous-command 승인 프롬프트는 채팅으로 승인 불가** — Hermes CLI는 위험 명령(대량 `git mv`·`git rm -r`·설정 덮어쓰기)에 **별도 TTY 승인 프롬프트**를 띄우고, 입력이 없으면 **60초 타임아웃으로 자동 거부**("⏱ Timeout — denying command" → 도구에 "User denied this command" 반환, WO-003에서 2회 실측). 채팅 메시지로 "승인한다"를 보내도 프롬프트에는 전달되지 않는다 — 승인 주체는 대화가 아니라 TTY다. 공식 우회는 `hermes --yolo`(모든 dangerous 승인 프롬프트 바이패스). 무인 Planner-Coder 루프에서는 **워크트리 격리 + push 금지 + 검증 게이트가 전제된 경우에만** --yolo로 구동하고, 그 전제가 없으면 사람이 tmux attach로 프롬프트를 직접 승인한다. 워처는 이 차단을 감지 못하므로(커밋 없음) 정체 시 capture-pane에서 "Timeout — denying"을 먼저 찾을 것. (2026-07-06)
