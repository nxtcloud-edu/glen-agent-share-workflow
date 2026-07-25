#!/usr/bin/env bash
# MAGI tmux 핑 wrapper — 글로벌 도구 (~/.magi/scripts/ping.sh)
#
# 원칙: tmux 핑은 "문서를 읽으라"는 wake-up 신호만 — 결정·명령·승인은 Git 문서(SSOT)에 먼저 쓴다.
# 선검사: 세션 존재, 대상 워크트리의 branch·clean 여부를 출력해 잘못된 대상 전송을 막는다.
#
# 세션명·워크트리는 lib.sh에서 계산한다 — magi-up.sh와 같은 정의를 공유하므로 한쪽만 어긋날 수 없다.
set -euo pipefail

MAGI_HOME="$(cd "$(dirname "$0")/.." && pwd)"
. "$MAGI_HOME/scripts/lib.sh"

usage() { echo "사용법: magi ping <노드: claude|hermes|codex> <메시지>"; exit 1; }
[ $# -ge 2 ] || usage
NODE="$1"; shift; MSG="$*"

PROJ_ROOT=$(magi_project_root) || { echo "❌ git 저장소가 아니다 — 프로젝트 폴더에서 실행하라"; exit 1; }
PROJ=$(basename "$PROJ_ROOT")

# 별칭 흡수 — 문서·습관에 `codex-cli`가 남아 있다
case "$NODE" in codex-cli) NODE=codex;; esac

# 노드 정의(lib.sh)에서 워크트리를 찾는다 — nodes.conf 오버라이드도 그대로 반영된다
WT=$(magi_nodes "$PROJ_ROOT" | while IFS= read -r l; do
       [ "$(magi_field "$l" 1)" = "$NODE" ] && magi_field "$l" 2
     done)
[ -n "$WT" ] || { echo "❌ 미등록 노드: $NODE (claude|hermes|codex)"; exit 2; }

SESSION=$(magi_session "$PROJ" "$NODE")

# 오류 원문을 삼키지 않는다 — 샌드박스 소켓 차단(Operation not permitted)을 "세션 없음"으로
# 오진했던 전례가 있다 (SKILL Gotcha: 샌드박스 tmux 소켓).
TMUX_ERR=$(tmux has-session -t "$SESSION" 2>&1) || {
  echo "❌ tmux 세션 접근 실패($SESSION): ${TMUX_ERR:-세션 없음}"; exit 2; }

echo "── 선검사: $NODE ($SESSION) → $WT"
git -C "$WT" status --short --branch | head -3
BASE=$(git -C "$WT" rev-parse --short HEAD)
echo "── base SHA: $BASE"

ENVELOPE="[MAGI ping → $NODE | base=$BASE | $(date '+%m-%d %H:%M')] $MSG"
tmux send-keys -t "$SESSION" -l "$ENVELOPE"
sleep 1
tmux send-keys -t "$SESSION" C-m
echo "✅ 전송 완료 (${#ENVELOPE}자)"
