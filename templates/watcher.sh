#!/bin/sh
# 완료 신호 워처 — Coder 워크트리에서 "새 커밋 + TURN_LOG 기록" 복합 조건 감지
# 사용: ./watcher.sh <coder-워크트리-경로> <WO번호 식별자(예: "Coder — WO-012")>
# 주의: 상태 줄(명령서의 '상태:') 단독 감시는 조기 신호가 난다 — 반드시 복합 조건으로.
W=${1:?워크트리 경로}; SIG=${2:?저널 식별자}
BASE=$(git -C "$W" log -1 --format=%H)
while true; do
  CUR=$(git -C "$W" log -1 --format=%H 2>/dev/null)
  if [ "$CUR" != "$BASE" ] && grep -q "$SIG" "$W/.agent/TURN_LOG.md" 2>/dev/null; then
    echo "완료 신호: $(git -C "$W" log -1 --oneline)"; exit 0
  fi
  [ "$CUR" != "$BASE" ] && { echo "커밋 감지(저널 대기): $(git -C "$W" log -1 --oneline)"; BASE="$CUR"; }
  sleep 30
done
