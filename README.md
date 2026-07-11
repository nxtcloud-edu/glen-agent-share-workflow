# Glen Agent-Share Workflow

**Planner-Coder 분업 기반 멀티에이전트 개발 워크플로우** — Claude가 계획·검증·배포를, 타 모델
에이전트(예: Codex 계열)가 코딩을 맡는 구조를 재사용 가능한 스킬셋으로 패키징한 레포입니다.

> 실증: goods-bank 프로젝트에서 WO(작업 명령서) 18사이클 — 반려 0, 릴리즈 25회,
> 반자동 루프(사람 개입 = 착수 승인·배포 승인 2지점)로 운영.

## 구조 한눈에

```
┌─ Planner/Verifier (Claude) ─────┐      ┌─ Coder (gpt-5.5 등 타 모델) ──┐
│ 1. 계획 수립 → WO 명령서 작성    │      │ 3. 워크트리의 wo/NNN 브랜치에서 │
│ 2. 브랜치 준비 → tmux로 착수 지시 │ ───▶ │    구현 + 전 스위트 자체 게이트  │
│ 5. 워처가 완료 감지 → 격리 검증   │ ◀─── │ 4. 커밋 + 저널 기록 = 완료 신호  │
│ 6. 게이트 머지 → 클라우드 배포    │      └────────────────────────────────┘
└──────────────────────────────────┘
       사람(오너): 착수 승인 · 배포 승인만
```

## 왜 이 구조인가

1. **Generator-Evaluator 분리** — 만드는 자와 평가하는 자를 분리해 자기 관대 편향을 차단.
   모델별 강점 분업(설계·리뷰 vs 구현 처리량)은 덤.
2. **신뢰는 구조로 강제** — 에이전트의 자기 보고는 교차 검증 전까지 미확인. 규칙 문서만으로는
   위반이 재발했고(클라우드 무단 반영 + 저널 허위 기재 실사례), **워크트리 브랜치 게이트**
   (미검증 코드는 main에 물리적으로 못 들어옴)와 **실측 검증 표준화**로 해결했습니다.
3. **반자동 루프** — 파일 게시판(저널)의 알림 부재를 워처로, 에이전트 간 지시를 tmux로 보완해
   사람 개입을 2지점으로 축소.

## 핵심 자산 5개

| 자산 | 역할 | 위치 |
|---|---|---|
| 저널 프로토콜 | 세션 독립 공유 기억 (CURRENT_STATE·HANDOFF·TURN_LOG·DECISIONS) | `templates/agent-journal/` |
| 작업 명령서(WO) 채널 | 설계 고정·완료 기준·절대 금지 블록, 상태 머신 | `templates/work-orders/` |
| 워처 핑 | 완료 신호(커밋+저널) 감지 + tmux 정체 감지 → 자동 검증/개입 | `templates/watcher.sh` |
| tmux 직접 제어 | 코더 CLI에 지시 (busy 사라진 뒤에만 send-keys) | `scripts/tmux-send-safe.sh` + 스킬 §5 |
| 워크트리 브랜치 게이트 | wo/NNN 격리, 코더 main커밋·push 훅 차단, 저널 merge=union | `scripts/setup-worktree.sh` + `templates/hooks/` |
| 스크립트(기계적 강제) | 폴더·턴 스캐폴딩, 저널 로테이션·대조, 게이트 훅 | `skills/agent-share/scripts/` + `templates/hooks/` |
| **MAGI 3자 체제** (`--mode magi`) | 이질적 3모델 상호 견제 — 합의 게이트·stop-the-line·lease·git 수거. 2026-07-11 goods-bank 헌장 v1.0(3자 전원 동의)으로 실증 | `skills/magi/` (SKILL + lease.sh·ping.sh + MD-000 템플릿) |

## 도입 순서

1. **스킬 설치**: `skills/agent-share/SKILL.md` → `~/.claude/skills/agent-share/` (Claude Code 기준)
2. **프로젝트 초기화**: `templates/AGENTS.md`를 프로젝트 루트에, `templates/agent-journal/`을
   `.agent/`로, `templates/work-orders/`를 `.agent/work-orders/`로 복사 후 프로젝트에 맞게 수정
3. **`.gitattributes`**: `templates/gitattributes.example` 참조 — append-only 저널에 merge=union
4. **코더 환경 + 게이트**: `scripts/setup-worktree.sh <repo> coder --hooks-src templates/hooks --wo NNN`
   — 워크트리·가드 마커·훅(pre-commit/pre-push, **절대경로** hooksPath)·wo 브랜치를 한 번에 셋업
   (코더의 main 직접 커밋·push를 훅이 물리적으로 차단, tmux로 CLI 실행 시 지시가 투명하게 보임)
5. **모드 선택**: 스킬의 light(문서 인계만) / standard(+저널·명령서·신뢰 규칙) /
   full(+워처·tmux·게이트) 중 프로젝트 규모에 맞게 — 상세는 SKILL.md

> 반복 절차는 `skills/agent-share/scripts/`가 담당: 스캐폴딩(`new-share`·`new-turn`),
> 저널 로테이션(`rotate-journal`, merge=union 게이트)·대조(`check-journal`), 안전 전송(`tmux-send-safe`).
> 명명·날짜·전제조건 게이트를 스크립트가 강제해 LLM 판단 오류를 차단한다.

## 운영 규칙 요약 (전체는 SKILL.md)

- 완료 신호 = **커밋 + 저널 기록** (상태 줄 단독은 조기 신호 — 실측된 함정)
- 머지 직전 **팁 == 검증 SHA 대조** (검증 후 끼어든 커밋 자동 차단, docs-only면 확인 후 진행)
- Commands **전수 기재** — "실행 안 함" 주장은 검증자가 실측 대조
- 클라우드·프로덕션 변경은 **검증자 전담** (코더 절대 금지 블록)
- 전 스위트는 한 번에 하나 (워크트리도 로컬 DB·포트는 공유)
- 위반 발견 → 주체 확정 → DECISIONS 공식 기록 → **회고로 재캘리브레이션** (문책이 아니라 규칙 갱신)

## 안내 문서

- [guide.html](guide.html) — 시각 가이드 (역할·흐름·게이트 다이어그램, 브라우저로 열기)
- `skills/agent-share/SKILL.md` — 스킬 전문 (Gotchas 포함)

## 라이선스·공유 범위

nxtcloud-edu 내부 교육·프로젝트용 프라이빗 자료. 외부 공개 시 실증 사례 수치·프로젝트명 재검토 필요.
