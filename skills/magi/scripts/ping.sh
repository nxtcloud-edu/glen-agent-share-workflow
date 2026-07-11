#!/usr/bin/env bash
# MAGI tmux 핑 wrapper (헌장 §7.4·§7.5)
# 원칙: tmux 핑은 "문서를 읽으라"는 wake-up 신호만 — 결정·명령·승인은 Git 문서(SSOT)에 먼저 쓴다.
# 선검사: 세션 존재, 대상 워크트리의 branch·clean 여부를 출력해 잘못된 대상 전송을 막는다.
set -euo pipefail

usage() { echo "사용법: ping.sh <세션: codex-cli|hermes> <메시지>"; exit 1; }
[ $# -ge 2 ] || usage
SESSION="$1"; shift; MSG="$*"

# ▼ 배치 시 프로젝트의 세션→워크트리 매핑을 채운다 (예: goods-bank는 codex-cli/hermes)
case "$SESSION" in
  # <세션명>) WT="<워크트리 절대경로>";;
  *) echo "❌ 미등록 세션: $SESSION — 스크립트 상단 case문에 매핑을 추가하라"; exit 2;;
esac

tmux has-session -t "$SESSION" 2>/dev/null || { echo "❌ tmux 세션 없음: $SESSION"; exit 2; }

echo "── 선검사: $SESSION → $WT"
git -C "$WT" status --short --branch | head -3
BASE=$(git -C "$WT" rev-parse --short HEAD)
echo "── base SHA: $BASE"

ENVELOPE="[MAGI ping → $SESSION | base=$BASE | $(date '+%m-%d %H:%M')] $MSG"
tmux send-keys -t "$SESSION" -l "$ENVELOPE"
sleep 1
tmux send-keys -t "$SESSION" C-m
echo "✅ 전송 완료 (${#ENVELOPE}자)"
