# <프로젝트명> — 에이전트 공통 규칙 (템플릿)

## 멀티 에이전트 협업 프로토콜 (필수)

이 저장소는 여러 AI 에이전트가 함께 작업한다. 공유 저널은 `.agent/`.

1. **작업 시작 전**: `.agent/CURRENT_STATE.md` → `.agent/HANDOFF.md` 순으로 읽고,
   `git status --short --branch`로 자기 보고와 실제 상태를 대조한다.
   검증자는 `check-journal.sh .agent`로 HEAD·active 턴·WO↔브랜치 불일치를 기계 대조한다.
2. **의미 있는 턴 종료 시**: `.agent/TURN_LOG.md`에 append-only로 기록 —
   Intent / Files changed / **Commands·verification (전수 기재, 미실행은 "실행 안 함" 명시)** / Decisions / Handoff.
3. **상태 변화 시**: `CURRENT_STATE.md`(HEAD·활성 소유자·완료 목록)와 `HANDOFF.md`(다음 안전 액션)를 갱신한다.
4. 다른 에이전트 소유 파일은 명확한 사유 없이 수정하지 않는다.
5. 제품 결정은 `docs/planning/DECISIONS.md`, 협업 운영 결정·위반 기록은 `.agent/DECISIONS.md` — 섞지 않는다.
6. **작업 분업**: <Planner 에이전트>가 계획·명령서·검증·배포, <Coder 에이전트>가 코딩 실행.
   명령서 채널: `.agent/work-orders/` (규칙은 그 README 참조).
7. **저널 비대화**: `TURN_LOG.md`는 최근 엔트리만 tail로 읽는다. 500줄 초과 시 로테이션은
   검증자(<Planner 에이전트>)만, 모든 WO 브랜치가 main에 머지된 시점에 수행한다.

## 워크트리·브랜치 게이트

- Coder는 `../<repo>-coder` 워크트리의 `wo/NNN` 브랜치에서만 작업·커밋. main 직접 커밋·푸시 금지.
  이 금지는 권고가 아니라 훅이 강제한다 (`pre-commit`=main 커밋 차단, `pre-push`=push 차단;
  `.agent-coder-guard` 마커로 코더 워크트리에서만 발동). 셋업: `setup-worktree.sh`.
- 머지는 검증 통과 후 검증자(Planner)만 수행.
- 완료 신호 = "wo/NNN 커밋 + TURN_LOG 기록" (상태 줄만 먼저 바꾸지 않는다).
- 전 스위트(테스트)는 한 번에 하나만 실행 (로컬 DB·포트는 워크트리 간 공유).
- 백그라운드 프로세스(dev 서버 등)는 턴 종료 전 정리.

## 공통 작업 규칙

- 커밋 메시지는 <언어>, 한 커밋 = 한 목적. 정리와 기능을 섞지 않는다.
- 검증 없이 "완료"라고 기록하지 않는다: <프로젝트 검증 명령들 명시>
- <환경 분리 규칙: 로컬 전용 env vs 클라우드 자격 — Coder는 클라우드 자격 접근 금지>
