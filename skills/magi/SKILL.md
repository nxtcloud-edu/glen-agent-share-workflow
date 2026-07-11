---
name: magi
description: MAGI 3자 협업 시스템 운영 스킬 (일반화판) — 이질적 3개 모델(오케스트레이터·주 구현·독립 반증)의 작업 라우팅, 노드 간 핑·lease·합의 게이트·git 수거 절차. agent-share --mode magi의 실행 레이어. 프로젝트에 배치 시 노드·워크트리·세션 매핑을 채워 사용.
---

# MAGI 운영 스킬 (일반화판)

> **원본 실증**: goods-bank 프로젝트 `.magi/MAGI.md`(헌장 v1.0, 3자 전원 동의) + `.magi/skill/SKILL.md`.
> 이 일반화판은 프로젝트 특화값(노드 모델·워크트리·tmux 세션명)을 `<>` 자리로 비워뒀다 —
> 배치 시 채우고, **중립 위치 한 곳을 SSOT로 두고 각 하네스 스킬 경로에 symlink**한다
> (예: `.magi/skill/` ← `.claude/skills/magi`·`.agents/skills/magi`). 스킬 카탈로그는 대부분
> 세션 시작 시 스캔 — 등록 후 새 세션부터 인식된다.

## 0. 노드 자기 식별 (배치 시 채움)

| 실행 환경 | 노드 | 역할 |
|---|---|---|
| <오케스트레이터 하네스>, main 워크트리 | **카스파** | 계획·명령서·검증·머지·배포·저널·합의 집행. git 수거 대행 |
| <주 구현 하네스>, <워크트리> | **멜기오르** | 주 구현 + stop-and-replan 권한 (잘못된 전제 발견 시 중단·재계획 요구) |
| <독립 반증 하네스>, <워크트리> | **발타자르** | 독립 반증·QA·2nd 구현·(선택)이미지 생성. 샌드박스형이면 **git 쓰기 금지** — 읽기(status/log/diff)는 허용, 쓰기(stash/rebase/commit)는 카스파가 수거 |

모든 노드 공통 시작 절차: 공유 저널의 `CURRENT_STATE.md` → `HANDOFF.md` 읽기 → `git status --short --branch`로 자기 보고와 실제 대조.

## 1. 작업 라우팅 (카스파 판단)

- 기능·버그·리팩터 → 멜기오르 (명령서 `work-orders/WO-NNN-*.md`)
- 중대 변경 반증, 두 노드 결론 불일치, 광범위 QA → 발타자르 (반증 모드)
- 구현 병목·병렬 2nd impl → 발타자르 (구현 모드 — **반증과 같은 변경에서 겸임 금지**, 자기 구현 건은 정족수 제외)
- 게이트 대상(비가역 migration·auth/secret·breaking change·파괴적 운영·거버넌스) → `decisions/MD-NNN-*.md` 발의 (MD-000 템플릿)

## 2. 소통 2층 구조

**결정·명령·승인은 Git 문서 먼저, tmux는 wake-up 신호만.**

```bash
scripts/ping.sh <세션> "<읽을 문서 ID + 요지>"   # 선검사(브랜치·SHA) 후 전송 — 세션→워크트리 매핑은 스크립트 상단 case문에 채움
```

응답 감시는 **산출 파일 존재가 아니라 대상 pane의 턴 종료 마커**로 (Gotcha 3).

## 3. 공유 자원 lease

```bash
scripts/lease.sh acquire <자원> <노드명> [작업ID]   # 로컬 DB·테스트 포트·main 등 사용 전
scripts/lease.sh release <자원> <노드명>
scripts/lease.sh status                             # stale(4h) 표시
```

lock은 `git-common-dir/magi-locks/` — 모든 워크트리가 같은 잠금을 본다.

## 4. 검증·수거 (카스파)

1. 생성자 ≠ 검증자 — 자기 보고는 실측 재검증 전까지 미확인.
2. 샌드박스 노드 산출물은 카스파가 `git -C <워크트리> add/commit` 대행 → rebase → main 머지. 대용량 바이너리는 커밋 금지(외부 스토리지로).
3. 시각 산출물(이미지 등)은 마지막에 `open`으로 열어 **사람이 직접 판정**.
4. 머지·push·배포는 카스파 단일 집행, 프로덕션 최종 권한은 사람.

## 5. 합의 게이트

1. MD-000 템플릿 복사 → packet(diff SHA·영향·evidence·rollback·미해결 반대) → 커밋 → 핑.
2. 각 노드 approve/reject/abstain + 근거 (침묵 ≠ 동의). 표는 commit SHA 귀속, 실질 diff 시 재투표.
3. **stop-the-line**: P0·권한 우회·데이터 손실 근거 반대 1표면 다수결로 못 덮음.
4. break-glass(긴급 차단·rollback): 실행자 1 + 독립 확인자 1 + 사람 승인 → 사후 3자 검토 의무.

## Gotchas (goods-bank 실측, 2026-07-11)

1. **샌드박스 git 쓰기 차단**: workspace-write류 샌드박스는 워크트리여도 공용 `.git`(git-common-dir) 쓰기 불가 — 읽기는 됨. git 쓰기를 지시하지 말고 파일만 시켜라.
2. **lease는 작업 수명**: stale 판정에 PID 생존 검사를 쓰면 acquire한 셸 종료 즉시 전 lease 탈취 가능 — 시간 기준만.
3. **완료 감시는 pane 마커로**: 산출 파일 존재 기준은 노드가 차단·중단되면 영원히 대기. 노드별 독립 감시, AND 조건 금지.
4. **tmux 프롬프트 오인**: 에이전트 CLI 프롬프트는 셸과 똑같이 생길 수 있다 — send-keys 전에 상태줄로 CLI 여부 확인. 확인용 셸 명령이 에이전트 메시지로 들어간다.
5. **same-tail append는 union merge가 항상 안전하지 않다** — 구분자 유실 가능, 머지 후 끝부분 확인.
6. **앵커링 방지**: 반증 지시 시 원 요구사항·대상 SHA·검증 명령만 먼저 주고, 다른 노드의 결론은 1차 독립 보고 뒤 공개.
7. **스킬 SSOT + symlink**: 하네스별 스킬 복사본은 드리프트한다 — 중립 SSOT 한 곳 + symlink. 노드에게 "네 스킬 관리 방식으로 등록됐는지" 확인시키면 반증까지 얻는다(실측: 등록 첫날 노드 반증으로 규칙 정밀화 1건).
