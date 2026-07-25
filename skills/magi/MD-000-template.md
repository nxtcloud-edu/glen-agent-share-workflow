# MD-000 — <결정 제목> (템플릿)

> MAGI 합의 게이트(헌장 §7.2 대상) 결정 기록. 파일명: `MD-NNN-<슬러그>.md`.
> 상태 머신: `proposed → acknowledged → in-progress → evidence-ready → approved / rejected`.
> 표는 정확한 commit SHA에 귀속 — 실질 diff 발생 시 재투표 (§7.3).

## Envelope

| 필드 | 값 |
|---|---|
| id | MD-NNN |
| from | <발의 노드> |
| to | Claude · Hermes · Codex |
| intent | <한 줄> |
| branch+worktree | <브랜치 / 워크트리> |
| base SHA | <commit SHA — 표가 귀속되는 대상> |
| owned files | <이 결정이 소유하는 파일들> |
| forbidden actions | <금지 사항> |
| shared-resource need | <로컬 Supabase / E2E 포트 / main — lease 필요 여부> |
| expected artifact | <산출물> |
| status | proposed |

## Decision packet (§7.3 필수 필드)

- **변경 diff/commit SHA**:
- **영향 범위 (blast radius)**:
- **검증 evidence**:
- **rollback 계획**:
- **미해결 반대**:

## Votes (침묵 ≠ 동의 — 각 노드 approve/reject/abstain + 근거)

| 노드 | 표 | 근거 | 대상 SHA | 시각 |
|---|---|---|---|---|
| Claude (캐스퍼) | | | | |
| Hermes (메르키오르) | | | | |
| Codex (발타자르) | | | | |

> **stop-the-line**: 재현 가능한 P0·권한 우회·데이터 손실·개인정보 근거의 구체적 반대 1표가 있으면, 반증 해소 또는 Glen의 명시적 위험 인수 전까지 진행 금지 (2/3이어도).
> 생성 노드는 해당 건 정족수에서 제외 (생성자 ≠ 검증자).

## 결과

- **판정**: approved / rejected
- **Glen 최종 승인** (프로덕션 실행 권한):
- **집행** (Claude 단일):
